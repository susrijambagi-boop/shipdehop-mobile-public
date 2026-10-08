-- Migration: 004_restore_service_role_isolation.sql
-- Restores least privilege on internal service_* functions.
-- Revokes EXECUTE from public, anon, and authenticated so Flutter clients cannot invoke service_* RPCs directly.
-- Execution remains granted ONLY to service_role.

revoke execute on function public.service_attach_payment_reference(uuid, public.payment_provider, text) from public, anon, authenticated;
revoke execute on function public.service_lock_order_payment(uuid, public.payment_provider, text, text, text) from public, anon, authenticated;
revoke execute on function public.service_cancel_pending_order(uuid, text) from public, anon, authenticated;

grant execute on function public.service_attach_payment_reference(uuid, public.payment_provider, text) to service_role;
grant execute on function public.service_lock_order_payment(uuid, public.payment_provider, text, text, text) to service_role;
grant execute on function public.service_cancel_pending_order(uuid, text) to service_role;
