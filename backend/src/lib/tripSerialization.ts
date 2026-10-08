/** Decode PostGIS EWKB, WKT, or explicit GeoJSON without manufacturing coordinates. */
export function decodePoint(value: unknown, lat?: unknown, lon?: unknown): [number, number] {
  let coordinates: unknown;
  if (lat != null && lon != null) coordinates = [Number(lon), Number(lat)];
  else if (value && typeof value === 'object' && 'type' in value && value.type === 'Point' && 'coordinates' in value) coordinates = value.coordinates;
  else if (typeof value === 'string') {
    const wkt = /^(?:SRID=4326;)?POINT\s*\(\s*([-+\d.eE]+)\s+([-+\d.eE]+)\s*\)$/i.exec(value);
    if (wkt) coordinates = [Number(wkt[1]), Number(wkt[2])];
    else {
      const hex = value.replace(/^\\x/, '');
      if (/^(?:[a-f0-9]{2})+$/i.test(hex)) {
        const bytes = Buffer.from(hex, 'hex');
        if (bytes.length >= 21 && (bytes[0] === 0 || bytes[0] === 1)) {
          const little = bytes[0] === 1;
          const uint = (offset: number) => little ? bytes.readUInt32LE(offset) : bytes.readUInt32BE(offset);
          const double = (offset: number) => little ? bytes.readDoubleLE(offset) : bytes.readDoubleBE(offset);
          const type = uint(1);
          const srid = (type & 0x20000000) !== 0;
          const offset = srid ? 9 : 5;
          if ((type & 0xdfffffff) === 1 && bytes.length === offset + 16 && (!srid || uint(5) === 4326)) {
            coordinates = [double(offset), double(offset + 8)];
          }
        }
      }
    }
  }
  if (!Array.isArray(coordinates) || coordinates.length !== 2 || !coordinates.every(v => typeof v === 'number' && Number.isFinite(v)) || Math.abs(coordinates[0]) > 180 || Math.abs(coordinates[1]) > 90) {
    throw new Error('Stored trip location is missing or invalid');
  }
  return coordinates as [number, number];
}

export function formatTripToJourneyJson(row: any): any {
  if (!row) return row;
  const [originLon, originLat] = decodePoint(row.origin_geo, row.origin_lat, row.origin_lon);
  const [destLon, destLat] = decodePoint(row.dest_geo, row.dest_lat, row.dest_lon);

  const departureIso = new Date(row.departure_time).toISOString();
  const tier = row.parcel_capacity_tier || row.parcelCapacityTier || 'MEDIUM';
  const defaultUnits = tier === 'NONE' ? 0 : tier === 'ENVELOPE' ? 2 : tier === 'MEDIUM' ? 6 : 12;

  const acceptsPassengers = row.accepts_passengers ?? row.acceptsPassengers ?? (Number(row.seat_capacity ?? row.seatCapacity ?? 0) > 0);
  const acceptsParcels = row.accepts_parcels ?? row.acceptsParcels ?? (tier !== 'NONE');
  const acceptsShoppingRequests = row.accepts_shopping_requests ?? row.acceptsShoppingRequests ?? false;

  const journeyFormatted = {
    id: row.id,
    origin: {
      displayLabel: row.origin_name || 'Origin',
      formattedAddress: row.origin_name || 'Origin',
      latitude: originLat,
      longitude: originLon,
      countryCode: row.jurisdiction_code ?? '',
      countryName: row.jurisdiction_code === 'IN' ? 'India' : '',
    },
    destination: {
      displayLabel: row.dest_name || 'Destination',
      formattedAddress: row.dest_name || 'Destination',
      latitude: destLat,
      longitude: destLon,
      countryCode: row.jurisdiction_code ?? '',
      countryName: row.jurisdiction_code === 'IN' ? 'India' : '',
    },
    timing: {
      earliestDateTime: departureIso,
      latestDateTime: departureIso,
      isFlexible: false,
    },
    travellerName: row.driver_name || row.traveller_name || 'Traveller',
    seatCapacity: Number(row.seat_capacity ?? row.seatCapacity ?? 0),
    availableSeats: Number(row.available_seats ?? row.availableSeats ?? 0),
    acceptsPassengers,
    acceptsParcels,
    parcelCapacityTier: tier,
    parcelCapacityUnitsTotal: Number(row.parcel_capacity_units_total ?? defaultUnits),
    parcelCapacityUnitsAvailable: Number(row.parcel_capacity_units_available ?? defaultUnits),
    acceptsShoppingRequests,
    pricePerSeat: Number(row.price_per_seat || row.pricePerSeat || 0),
    estimatedTripCost: Number(row.estimated_trip_cost || row.estimatedTripCost || 0),
    currency: row.currency ?? '',
    jurisdictionCode: row.jurisdiction_code ?? '',
    status: row.status || 'SCHEDULED',
  };

  return { ...row, ...journeyFormatted };
}

