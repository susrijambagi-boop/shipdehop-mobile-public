import { isPointInIndia } from './locationValidation.js';
export const INDIA_ONLY_MESSAGE =
  'ShipdeHop is currently available only for routes within India.';

export type GeoPoint = { lat: number; lon: number };

export function isIndiaPoint(point: GeoPoint): boolean {
  return isPointInIndia(point.lat, point.lon);
}

export function assertIndiaRoute(
  origin: GeoPoint,
  destination: GeoPoint,
  currency?: string,
  jurisdictionCode?: string,
): void {
  const currencyOk = currency == null || currency.trim().toUpperCase() === 'INR';
  const jurisdictionOk =
    jurisdictionCode == null ||
    ['IN', 'IND', 'INDIA'].includes(jurisdictionCode.trim().toUpperCase());

  if (!isIndiaPoint(origin) || !isIndiaPoint(destination) || !currencyOk || !jurisdictionOk) {
    throw new Error(INDIA_ONLY_MESSAGE);
  }
}

