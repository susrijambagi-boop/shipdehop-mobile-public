-- Additive upgrade. Reject every uncovered segment, including short border crossings.
-- No blanket bridge exemption; unsupported geometry remains unavailable.
CREATE OR REPLACE FUNCTION public.is_route_in_india(p_route_polyline geography)
RETURNS boolean LANGUAGE sql STABLE SET search_path = public, extensions
AS $$
 SELECT CASE WHEN p_route_polyline IS NULL THEN false
 WHEN ST_GeometryType(p_route_polyline::geometry) <> 'ST_LineString'
 OR ST_IsEmpty(p_route_polyline::geometry) OR ST_NPoints(p_route_polyline::geometry) < 2 THEN false
 ELSE COALESCE((SELECT ST_Covers(ST_UnaryUnion(ST_Collect(ST_MakeValid(geom))), p_route_polyline::geometry)
 FROM public.india_spatial_boundaries), false) END;
$$;

-- Evaluate linked stored records before new reservations, acceptance, or funding.
-- Historical reads, refunds, cancellation and completed deliveries are unaffected.
CREATE OR REPLACE FUNCTION public.assert_india_order_eligible(p_order public.escrow_orders)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE t public.trip_routes; s public.shipment_tasks; m public.marketplace_items;
BEGIN
 IF p_order.currency IS DISTINCT FROM 'INR' THEN RAISE EXCEPTION 'Currently available in India.'; END IF;
 IF p_order.trip_id IS NOT NULL THEN
  SELECT * INTO t FROM public.trip_routes WHERE id = p_order.trip_id FOR SHARE;
  IF NOT FOUND OR t.currency IS DISTINCT FROM 'INR' OR t.jurisdiction_code IS DISTINCT FROM 'IN'
   OR NOT public.is_coord_in_india(ST_Y(t.origin_geo::geometry), ST_X(t.origin_geo::geometry))
   OR NOT public.is_coord_in_india(ST_Y(t.dest_geo::geometry), ST_X(t.dest_geo::geometry))
   OR NOT public.is_route_in_india(t.route_polyline) THEN RAISE EXCEPTION 'Currently available in India.'; END IF;
 END IF;
 IF p_order.shipment_task_id IS NOT NULL THEN
  SELECT * INTO s FROM public.shipment_tasks WHERE id = p_order.shipment_task_id FOR SHARE;
  IF NOT FOUND OR s.currency IS DISTINCT FROM 'INR' OR s.pickup_geo IS NULL OR s.drop_geo IS NULL
   OR NOT public.is_coord_in_india(ST_Y(s.pickup_geo::geometry), ST_X(s.pickup_geo::geometry))
   OR NOT public.is_coord_in_india(ST_Y(s.drop_geo::geometry), ST_X(s.drop_geo::geometry))
   THEN RAISE EXCEPTION 'Currently available in India.'; END IF;
 END IF;
 IF p_order.marketplace_item_id IS NOT NULL THEN
  SELECT * INTO m FROM public.marketplace_items WHERE id = p_order.marketplace_item_id FOR SHARE;
  IF NOT FOUND OR m.currency IS DISTINCT FROM 'INR' OR m.jurisdiction_code IS DISTINCT FROM 'IN'
   OR m.location_geo IS NULL
   OR NOT public.is_coord_in_india(ST_Y(m.location_geo::geometry), ST_X(m.location_geo::geometry))
   THEN RAISE EXCEPTION 'Currently available in India.'; END IF;
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_india_order_eligible(public.escrow_orders) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assert_india_order_eligible(public.escrow_orders) TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_india_new_order() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF TG_OP = 'INSERT' THEN
  PERFORM public.assert_india_order_eligible(NEW);
 ELSIF (OLD.escrow_status = 'PENDING' AND NEW.escrow_status = 'LOCKED')
    OR (OLD.fulfillment_status = 'CREATED' AND NEW.fulfillment_status = 'READY') THEN
  PERFORM public.assert_india_order_eligible(NEW);
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.enforce_india_new_order() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER enforce_india_new_order BEFORE INSERT OR UPDATE ON public.escrow_orders
FOR EACH ROW EXECUTE FUNCTION public.enforce_india_new_order();
