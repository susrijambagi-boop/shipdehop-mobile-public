-- Migration: 002_grant_reserve_shipment_order_to_authenticated.sql
-- Grant EXECUTE on reserve_shipment_order to authenticated role so authenticated carriers can claim eligible matched shipments.
-- Keeps anon and public execution revoked to prevent unauthenticated access.

grant execute on function public.reserve_shipment_order(uuid, uuid, uuid, uuid, integer, integer) to authenticated;
