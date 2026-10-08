export function computeSha256(content: string | Buffer): string;
export function transformGeoJsonToCanonical(rawGeoJson: any): string;
export function generateAndVerifyBoundary(sourceContentOrPath?: string, targetAssetPath?: string): { sourceHash: string; generatedHash: string; matches: boolean };
export function generateAndVerifyBoundaryAsync(sourceContentOrPath?: string, targetAssetPath?: string): Promise<{ sourceHash: string; generatedHash: string; matches: boolean }>;
export const PINNED_DATAMEET_COMMIT: string;
export const EXPECTED_SOURCE_SHA256: string;
export const EXPECTED_GENERATED_SHA256: string;

