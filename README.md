# ShipdeHop Public CI Mirror

Sanitized public release-validation mirror for ShipdeHop.

## Provenance
- **Private Source Commit**: `27f2ae3cdfedc9006fc7a51b563409afcc73b735`
- **Modules Included**: `mobile`, `backend`, `db`

## CI Workflow
Automated release CI validation runs via GitHub Actions on `.github/workflows/release-ci.yml`:
- Flutter pub get, analyze, & expanded test suite
- Backend npm ci, build, & PostgreSQL/PostGIS test suites
- Unsigned iOS release compile on `macos-latest`
