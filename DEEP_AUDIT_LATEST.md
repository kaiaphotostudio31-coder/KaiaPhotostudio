# Kaia Booking — Deep Audit Latest

Baseline audited: `kaia-booking (2).zip` (uploaded source).

## Executed
- `npm test` — PASS
- `node --check` on all 13 JavaScript files — PASS

## Findings
1. The schema still contained the legacy `create_booking` overload. This was a real security/integrity gap because PostgreSQL function overloading can leave the old callable signature in place after the new function is created.
2. The schema did not explicitly revoke browser-role execution on the booking/calendar/blocking RPCs.
3. The schema did not explicitly enable RLS on application tables.

## Repairs
- Drop the legacy `create_booking(...)` overload.
- Revoke `EXECUTE` from `public`, `anon`, and `authenticated` for booking, calendar-claim, and blocked-slot RPCs.
- Enable RLS on application tables. The backend uses Supabase service role, which bypasses RLS; no browser-facing policies are intentionally granted.
- Existing booking-code counter/idempotency/concurrency implementation retained.
- Existing Family Jadoel NULL duration and unspecified prewedding/Pas Foto-without-print min people retained.
- Existing Calendar/Drive/photo-selection architecture retained.

## Not live-verified
- Real Supabase transaction/concurrency test
- Google OAuth
- Google Calendar event creation
- Google Drive access
- Production Netlify runtime

These require real credentials/services.
