import { randomUUID } from 'crypto';
import { adminSupabase } from '../lib/supabase.js';
import { config } from '../config.js';

export const MARKETPLACE_BUCKET = 'marketplace-images';
export const MAX_IMAGES_PER_LISTING = 4;
export const MAX_DECODED_IMAGE_BYTES = 2 * 1024 * 1024; // 2 MB
export const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export type AllowedMimeType = (typeof ALLOWED_MIME_TYPES)[number];

let bucketEnsured = false;

export async function ensureMarketplaceBucket(): Promise<void> {
  if (bucketEnsured) return;
  try {
    const { data: buckets, error: listError } = await adminSupabase.storage.listBuckets();
    if (listError) {
      console.warn('[MarketplaceStorage] Failed to list buckets:', listError.message);
      return;
    }
    const exists = buckets?.some(b => b.id === MARKETPLACE_BUCKET || b.name === MARKETPLACE_BUCKET);
    if (!exists) {
      const { error: createError } = await adminSupabase.storage.createBucket(MARKETPLACE_BUCKET, {
        public: true,
        fileSizeLimit: MAX_DECODED_IMAGE_BYTES,
        allowedMimeTypes: [...ALLOWED_MIME_TYPES],
      });
      if (createError && !createError.message?.includes('already exists')) {
        console.warn('[MarketplaceStorage] Failed to create bucket:', createError.message);
      }
    }
    bucketEnsured = true;
  } catch (err) {
    console.warn('[MarketplaceStorage] ensureMarketplaceBucket error:', err);
  }
}

export interface DecodedImage {
  buffer: Buffer;
  mimeType: AllowedMimeType;
  extension: 'jpg' | 'png' | 'webp';
}

export function validateAndDecodeImage(rawInput: string): DecodedImage {
  if (!rawInput || typeof rawInput !== 'string' || rawInput.trim().length === 0) {
    throw new Error('Image payload cannot be empty.');
  }

  let mimeType: string | null = null;
  let base64Data = rawInput.trim();

  // Match data URI pattern: data:<mime>;base64,<payload>
  const dataUriMatch = base64Data.match(/^data:([^;]+);base64,(.+)$/is);
  if (dataUriMatch && dataUriMatch[1] && dataUriMatch[2]) {
    mimeType = dataUriMatch[1].toLowerCase().trim();
    base64Data = dataUriMatch[2].trim();
  }

  // Reject SVG explicitly
  if (mimeType && (mimeType.includes('svg') || mimeType.includes('xml') || mimeType.includes('html'))) {
    throw new Error('Unsupported image format. SVG and XML formats are strictly forbidden.');
  }

  let buffer: Buffer;
  try {
    buffer = Buffer.from(base64Data, 'base64');
  } catch {
    throw new Error('Invalid Base64 image encoding.');
  }

  if (buffer.length === 0) {
    throw new Error('Decoded image is empty (0 bytes).');
  }

  if (buffer.length > MAX_DECODED_IMAGE_BYTES) {
    throw new Error(
      `Image size (${(buffer.length / (1024 * 1024)).toFixed(2)} MB) exceeds the maximum allowed limit of 2 MB.`
    );
  }

  // Validate magic bytes to prevent spoofing
  const detectedMime = detectMimeFromMagicBytes(buffer);
  if (!detectedMime) {
    throw new Error('Unsupported image file format. Only JPEG, PNG, and WebP images are accepted.');
  }

  // If MIME was supplied in data URI, ensure it matches detected type
  if (mimeType && mimeType !== detectedMime && !(mimeType === 'image/jpg' && detectedMime === 'image/jpeg')) {
    throw new Error(`MIME type mismatch: declared '${mimeType}' but detected '${detectedMime}'.`);
  }

  const finalMime = detectedMime;
  const extension: 'jpg' | 'png' | 'webp' =
    finalMime === 'image/jpeg' ? 'jpg' : finalMime === 'image/png' ? 'png' : 'webp';

  return {
    buffer,
    mimeType: finalMime,
    extension,
  };
}

function detectMimeFromMagicBytes(buffer: Buffer): AllowedMimeType | null {
  if (buffer.length < 4) return null;

  // JPEG: FF D8 FF
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'image/jpeg';
  }

  // PNG: 89 50 4E 47
  if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
    return 'image/png';
  }

  // WebP: RIFF .... WEBP
  if (
    buffer.length >= 12 &&
    buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46 && // "RIFF"
    buffer[8] === 0x57 && buffer[9] === 0x45 && buffer[10] === 0x42 && buffer[11] === 0x50  // "WEBP"
  ) {
    return 'image/webp';
  }

  return null;
}

export interface UploadResult {
  urls: string[];
  paths: string[];
}

export async function processAndUploadMarketplaceImages(
  sellerId: string,
  images: string[]
): Promise<UploadResult> {
  if (!images || images.length === 0) {
    return { urls: [], paths: [] };
  }

  if (images.length > MAX_IMAGES_PER_LISTING) {
    throw new Error(`Marketplace listings support a maximum of ${MAX_IMAGES_PER_LISTING} photos.`);
  }

  await ensureMarketplaceBucket();

  // First validate and decode ALL images before uploading any to ensure atomicity
  const decodedList: DecodedImage[] = [];
  for (const raw of images) {
    // If it's already an existing Supabase Storage URL (e.g. from an existing listing test or re-save)
    if (typeof raw === 'string' && raw.startsWith('https://') && raw.includes('/storage/v1/object/public/marketplace-images/')) {
      continue;
    }
    if (typeof raw !== 'string') {
      throw new Error('Invalid image entry: expected string');
    }
    const decoded = validateAndDecodeImage(raw);
    decodedList.push(decoded);
  }

  const uploadedUrls: string[] = [];
  const uploadedPaths: string[] = [];

  try {
    for (let i = 0; i < images.length; i++) {
      const raw = images[i];
      if (typeof raw === 'string' && raw.startsWith('https://') && raw.includes('/storage/v1/object/public/marketplace-images/')) {
        uploadedUrls.push(raw);
        continue;
      }

      const decoded = decodedList.shift()!;
      const fileUuid = randomUUID();
      const filePath = `${sellerId}/${fileUuid}.${decoded.extension}`;

      const { data, error } = await adminSupabase.storage
        .from(MARKETPLACE_BUCKET)
        .upload(filePath, decoded.buffer, {
          contentType: decoded.mimeType,
          upsert: false,
        });

      if (error || !data) {
        throw new Error(`Failed to upload listing photo: ${error?.message ?? 'Unknown storage error'}`);
      }

      uploadedPaths.push(filePath);

      const publicUrl = `${config.SUPABASE_URL}/storage/v1/object/public/${MARKETPLACE_BUCKET}/${filePath}`;
      uploadedUrls.push(publicUrl);
    }

    return { urls: uploadedUrls, paths: uploadedPaths };
  } catch (err) {
    // If any upload fails, clean up whatever was uploaded in this batch
    if (uploadedPaths.length > 0) {
      await cleanupMarketplaceImages(uploadedPaths);
    }
    throw err;
  }
}

export async function cleanupMarketplaceImages(paths: string[]): Promise<void> {
  if (!paths || paths.length === 0) return;
  try {
    await adminSupabase.storage.from(MARKETPLACE_BUCKET).remove(paths);
  } catch (err) {
    console.warn('[MarketplaceStorage] Best-effort cleanup failed for paths:', paths, err);
  }
}
