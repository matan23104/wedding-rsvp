# Deployment Readiness

## Completed in code

- Replaced admin client-side password with Supabase Auth login in `MPadmin.html`.
- Removed plain-text `ADMIN_PASSWORD` from `config.js`.
- Switched public RSVP/question operations in `index.html` and `rsvp-connector.js` to RPC calls.
- Added `supabase/rls-policies.sql` to enforce strict table RLS and expose only safe public RPCs.

## One-time setup in Supabase (required)

1. In **Authentication > Users**, create at least one admin user (email/password).
2. In **SQL Editor**, run `supabase/rls-policies.sql`.
3. Verify RPC functions exist:
   - `get_guest_by_token`
   - `submit_rsvp_by_token`
   - `submit_rsvp_manual`
   - `submit_question_public`
4. Verify RLS is enabled on:
   - `public.guests`
   - `public.questions`

## Publish checklist

- Test guest flow:
  - Open `index.html` with a token (`?t=...`) and submit RSVP.
  - Submit a question from guest page.
- Test admin flow:
  - Login on `MPadmin.html` using Supabase user credentials.
  - Confirm guest list and CRUD actions work.
- Confirm no plain-text admin password remains in frontend source.
