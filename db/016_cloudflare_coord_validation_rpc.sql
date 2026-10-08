-- Migration 016: Cloudflare Coordinate Validation RPC
-- Provides service-role-only is_coord_in_india_f64(double precision, double precision)

CREATE OR REPLACE FUNCTION public.is_coord_in_india_f64(p_lat double precision, p_lon double precision)
RETURNS boolean
LANGUAGE plpgsql
STRICT
SECURITY DEFINER
AS $$
BEGIN
  IF p_lat IS NULL OR p_lon IS NULL OR p_lat < -90 OR p_lat > 90 OR p_lon < -180 OR p_lon > 180 THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.india_spatial_boundary
    WHERE ST_Intersects(
      geom,
      ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_coord_in_india_f64(double precision, double precision) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_coord_in_india_f64(double precision, double precision) TO service_role;
