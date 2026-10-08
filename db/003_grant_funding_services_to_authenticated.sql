-- Migration: 003_grant_funding_services_to_authenticated.sql
-- Grant EXECUTE on funding pipeline service RPCs to authenticated role.
-- Keeps anon and public execution revoked to prevent unauthenticated access.

grant execute on function public.service_attach_payment_reference(uuid, public.payment_provider, text) to authenticated;
grant execute on function public.service_lock_order_payment(uuid, public.payment_provider, text, text, text) to authenticated;
grant execute on function public.service_cancel_pending_order(uuid, text) to authenticated;
