# Kaia Booking — Netlify readiness

## Build/runtime
- Static site: `public/`
- Netlify Function: `netlify/functions/api.js`
- Express API routes remain under `/api/*`.
- `netlify/functions/api.js` restores the `/api` prefix after the Netlify redirect so production routing matches local routing.
- Build command: `npm install`
- Functions directory: `netlify/functions`

## Required Netlify environment variables
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ADMIN_JWT_SECRET`
- `ADMIN_EMAIL`
- `ADMIN_PASSWORD`

For Google Calendar/Drive:
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REDIRECT_URI`
- `GOOGLE_TOKEN_ENCRYPTION_KEY`
- `GOOGLE_CALENDAR_ID` (or the stored setting)
- `PUBLIC_SITE_URL`

## Supabase
Fresh installation: run `supabase/schema.sql`.
Existing installation: run migrations in order:
1. `002_hardening_calendar_drive_selection.sql`
2. `003_final_concurrency_oauth_hardening.sql`
3. `004_security_selection_access.sql`

## Important live verification
The repository can be statically/syntax checked without credentials. Before production use, verify:
1. normal booking
2. same-slot concurrent booking (one succeeds, one receives conflict)
3. idempotent retry (same key/request does not create a second booking)
4. admin login/logout
5. Google OAuth connection
6. Calendar event creation and retry
7. Drive folder validation and customer photo selection
8. Family Jadoel remains manual because duration is unspecified
9. KP1–KP5 remain `REFERENCE_MISSING` until the original visual references are supplied
