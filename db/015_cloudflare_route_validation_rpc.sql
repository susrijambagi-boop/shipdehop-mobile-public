-- Migration 015: Cloudflare Route Validation RPC
-- Provides is_route_geojson_in_india(jsonb) for GeoJSON LineString coverage verification in India

CREATE OR REPLACE FUNCTION public.is_route_geojson_in_india(p_route_geojson jsonb)
RETURNS boolean
LANGUAGE plpgsql
STRICT
SECURITY DEFINER
AS $$
DECLARE
  v_geom geometry;
BEGIN
  IF p_route_geojson IS NULL THEN
    RETURN false;
  END IF;

  BEGIN
    v_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_route_geojson), 4326);
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;

  IF v_geom IS NULL THEN
    RETURN false;
  END IF;

  RETURN ST_Covers(
    (SELECT ST_Union(geom) FROM public.india_spatial_boundary),
    v_geom
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_route_geojson_in_india(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_route_geojson_in_india(jsonb) TO service_role;
