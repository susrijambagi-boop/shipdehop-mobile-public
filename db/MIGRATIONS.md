# ShipdeHop Migration Manifest

> **The authoritative, machine-readable sequence is [`db/migrations.json`](./migrations.json).**
> This document is generated from that file for human reference.
> When in doubt, the JSON file wins.

## Canonical migration order (20 files)

Apply migrations in **exactly** this order for both a fresh install and an incremental upgrade.

| # | File | Purpose |
|---|------|---------|
| 1 | `001_shipdehop.sql` | Core schema: users, trips, shipments, orders, RLS |
| 2 | `002_ride_requests.sql` | Ride request capability |
| 3 | `002_grant_reserve_shipment_order_to_authenticated.sql` | Grant: reserve/shipment RPCs to `authenticated` |
| 4 | `003_parcel_capacity.sql` | Parcel capacity on trips |
| 5 | `003_grant_funding_services_to_authenticated.sql` | Grant: funding/payment RPCs to `authenticated` |
| 6 | `004_notifications.sql` | Notification events table |
| 7 | `004_restore_service_role_isolation.sql` | Security: revoke from `anon`/`authenticated` where over-granted |
| 8 | `005_marketplace_integration.sql` | HopShop marketplace listings |
| 9 | `006_unified_history_messages_trust.sql` | Unified order history + chat + trust score |
| 10 | `007_phone_identity_verification.sql` | eKYC phone identity |
| 11 | `008_identity_beta_hardening.sql` | Identity beta hardening constraints |
| 12 | `009_india_location_enforcement.sql` | India geometry boundary + location enforcement |
| 13 | `010_india_route_coverage.sql` | India route spatial coverage |
| 14 | `010_journey_capabilities_matching_security.sql` | Journey capability flags + matcher security |
| 15 | `011_accepts_parcels_capability.sql` | `accepts_parcels` capability on trips |
| 16 | `012_release_contract_fixes.sql` | Release contract fixes + RPC column alignment |
| 17 | `013_release_closeout_hardening.sql` | DB-level PIN enforcement + currency ISO format + ship_eligible invariant |
| 18 | `014_production_security_hardening.sql` | Production security hardening for verification sessions |
| 19 | `015_cloudflare_route_validation_rpc.sql` | GeoJSON LineString route validation RPC for Cloudflare Workers |
| 20 | `016_cloudflare_coord_validation_rpc.sql` | Service-role-only float64 coordinate validation RPC for Cloudflare Workers |

## Rules

- **Never reorder** entries once merged to `main`.
- **Append only** — new migrations go at the bottom.
- Migrations 001–004 are already applied on production. Do not re-run them there.
- All constraints in 013 use `NOT VALID` for safe incremental deployment.
- The automated test in `backend/src/test_migration_order_suite.ts` enforces that:
  - all 20 files exist on disk
  - no unlisted `.sql` files are present in `db/`
  - a fresh-install PGlite run applies all 20 migrations successfully
  - a pre-013 → 013 upgrade run succeeds without corrupting legacy data
