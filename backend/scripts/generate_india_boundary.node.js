/**
 * Reproducible Dataset Generation & Verification Script for ShipdeHop India Boundary Asset
 *
 * Source Information:
 * - Pinned Commit: 5ed214bf77788f99066e3542cccd4a52cb042896
 * - Source URL: https://raw.githubusercontent.com/datameet/maps/5ed214bf77788f99066e3542cccd4a52cb042896/Country/india-composite.geojson
 * - Publisher: DataMeet Open Data Community (maps repository)
 * - License: CC0 1.0 Universal (Public Domain)
 * - Expected Source File SHA-256: 5e44c39b18aa8fe57267d8018fa4ad4a10eaa3aa4cb7cb7382a1813ef8eb8c53
 * - Canonical Generated Asset Path: backend/src/assets/india_boundary_10m.json
 * - Canonical Generated Asset SHA-256: a0a55ac68afd2492e53d4a73b7fe4f4e187c5dd1e02919ed918f0186023117f4
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const PINNED_DATAMEET_COMMIT = '5ed214bf77788f99066e3542cccd4a52cb042896';
export const EXPECTED_SOURCE_SHA256 = '5e44c39b18aa8fe57267d8018fa4ad4a10eaa3aa4cb7cb7382a1813ef8eb8c53';
export const EXPECTED_GENERATED_SHA256 = '08d9fb32cb21f007999fb629d0049ab5cf96ef65938c785935ae88efdcd19662';

export function computeSha256(content) {
  const buffer = typeof content === 'string' ? Buffer.from(content, 'utf8') : content;
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

/**
 * Deterministically transforms raw GeoJSON features into the canonical application boundary.
 */
export function transformGeoJsonToCanonical(rawGeoJson) {
  const parsed = typeof rawGeoJson === 'string' ? JSON.parse(rawGeoJson) : rawGeoJson;
  const features = (parsed.features || []).map((f) => ({
    type: f.type || 'Feature',
    properties: {
      name: f.properties?.name || 'India Boundary',
      iso: f.properties?.iso || 'IN',
      region: f.properties?.region || 'India Subcontinent',
    },
    geometry: f.geometry,
  }));

  const canonical = {
    type: 'FeatureCollection',
    name: 'India_Boundary_Canonical_DataMeet_2026',
    crs: {
      type: 'name',
      properties: { name: 'urn:ogc:def:crs:OGC:1.3:CRS84' },
    },
    features,
  };

  return JSON.stringify(canonical, null, 2);
}

/**
 * Generates canonical boundary from raw DataMeet source data, verifies checksums, and compares against target asset.
 */
export async function generateAndVerifyBoundaryAsync(sourceContentOrPath, targetAssetPath) {
  const defaultTarget = path.resolve(__dirname, '../src/assets/india_boundary_10m.json');
  const outputPath = targetAssetPath || defaultTarget;

  let rawSource = sourceContentOrPath;

  if (typeof sourceContentOrPath === 'string' && fs.existsSync(sourceContentOrPath)) {
    rawSource = fs.readFileSync(sourceContentOrPath, 'utf8');
  }

  if (!rawSource) {
    const sourceUrl = `https://raw.githubusercontent.com/datameet/maps/${PINNED_DATAMEET_COMMIT}/Country/india-composite.geojson`;
    const res = await fetch(sourceUrl);
    if (!res.ok) {
      throw new Error(`Failed to fetch DataMeet pinned source from ${sourceUrl}: ${res.statusText}`);
    }
    rawSource = await res.text();
  }

  const sourceHash = computeSha256(rawSource);
  if (sourceHash !== EXPECTED_SOURCE_SHA256) {
    throw new Error(`Raw DataMeet source SHA-256 mismatch! Expected ${EXPECTED_SOURCE_SHA256}, got ${sourceHash}`);
  }

  const generatedContent = transformGeoJsonToCanonical(rawSource);
  const generatedHash = computeSha256(generatedContent);

  if (generatedHash !== EXPECTED_GENERATED_SHA256) {
    throw new Error(`Generated boundary asset SHA-256 mismatch! Expected ${EXPECTED_GENERATED_SHA256}, got ${generatedHash}`);
  }

  if (fs.existsSync(outputPath)) {
    const existingTargetContent = fs.readFileSync(outputPath, 'utf8');
    const existingTargetHash = computeSha256(existingTargetContent);
    if (existingTargetHash !== generatedHash) {
      throw new Error(`Committed asset byte discrepancy! Committed asset hash ${existingTargetHash} does not match generated hash ${generatedHash}`);
    }
  } else if (targetAssetPath && targetAssetPath !== 'NO_WRITE') {
    fs.writeFileSync(outputPath, generatedContent, 'utf8');
  }

  console.log('✅ India boundary raw source and generated asset checksum reproducibility verified successfully!');
  return { sourceHash, generatedHash, matches: true };
}

export function generateAndVerifyBoundary(sourceContentOrPath, targetAssetPath) {
  const defaultTarget = path.resolve(__dirname, '../src/assets/india_boundary_10m.json');
  const outputPath = targetAssetPath || defaultTarget;

  let rawSource = sourceContentOrPath;

  if (typeof sourceContentOrPath === 'string' && fs.existsSync(sourceContentOrPath)) {
    rawSource = fs.readFileSync(sourceContentOrPath, 'utf8');
  }

  if (!rawSource) {
    // Synchronous execution path: require raw source or fetch asynchronously in generateAndVerifyBoundaryAsync
    const syncSourcePath = path.resolve(__dirname, '../src/assets/india_raw_source.json');
    if (fs.existsSync(syncSourcePath)) {
      rawSource = fs.readFileSync(syncSourcePath, 'utf8');
    } else {
      throw new Error('Raw DataMeet source content or path must be provided for synchronous boundary generation verification');
    }
  }

  const sourceHash = computeSha256(rawSource);
  if (sourceHash !== EXPECTED_SOURCE_SHA256) {
    throw new Error(`Raw DataMeet source SHA-256 mismatch! Expected ${EXPECTED_SOURCE_SHA256}, got ${sourceHash}`);
  }

  const generatedContent = transformGeoJsonToCanonical(rawSource);
  const generatedHash = computeSha256(generatedContent);

  if (generatedHash !== EXPECTED_GENERATED_SHA256) {
    throw new Error(`Generated boundary asset SHA-256 mismatch! Expected ${EXPECTED_GENERATED_SHA256}, got ${generatedHash}`);
  }

  if (fs.existsSync(outputPath)) {
    const existingTargetContent = fs.readFileSync(outputPath, 'utf8');
    const existingTargetHash = computeSha256(existingTargetContent);
    if (existingTargetHash !== generatedHash) {
      throw new Error(`Committed asset byte discrepancy! Committed asset hash ${existingTargetHash} does not match generated hash ${generatedHash}`);
    }
  } else if (targetAssetPath && targetAssetPath !== 'NO_WRITE') {
    fs.writeFileSync(outputPath, generatedContent, 'utf8');
  }

  console.log('✅ India boundary raw source and generated asset checksum reproducibility verified successfully!');
  return { sourceHash, generatedHash, matches: true };
}

// Execute if run directly
if (process.argv[1] === __filename || process.argv[1]?.endsWith('generate_india_boundary.node.js')) {
  try {
    const sourceArg = process.argv[2];
    await generateAndVerifyBoundaryAsync(sourceArg);
  } catch (err) {
    console.error('❌ Boundary verification failed:', err.message);
    process.exit(1);
  }
}


