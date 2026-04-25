# Wedding RSVP: Publish, Unpublish, and Testing Guide

This guide is an end-to-end runbook for:

- Publishing the app
- Testing before and after go-live
- Unpublishing (turning off public access)

Use this file as your operational checklist.

---

## 1) Publish (Go Live)

### 1.1 Prerequisites

Make sure you have:

- GitHub repository with this project pushed
- Supabase project created
- Access to Supabase SQL Editor and Authentication settings

### 1.2 Push latest code

From project folder:

```bash
git add .
git commit -m "Prepare production publish"
git push origin main
```

### 1.3 Enable GitHub Pages

In GitHub:

1. Open repository
2. Go to `Settings` -> `Pages`
3. Under **Build and deployment**:
   - Source: `Deploy from a branch`
   - Branch: `main`
   - Folder: `/ (root)`
4. Save

Expected site URL:

- `https://matan23104.github.io/wedding-rsvp/`

Admin URL:

- `https://matan23104.github.io/wedding-rsvp/MPadmin.html`

### 1.4 Configure Supabase auth admin user

In Supabase:

1. `Authentication` -> `Users`
2. Create user with email/password
3. Keep credentials private (for admin dashboard login)

### 1.5 Apply RLS and RPC security setup

In Supabase SQL Editor:

1. Open file `supabase/rls-policies.sql`
2. Copy/paste and run all SQL

This enables:

- RLS on `guests` and `questions`
- Admin full access for authenticated users
- Public-safe RPCs used by guest flow

---

## 2) Testing Checklist

Run this checklist before sharing links broadly.

### 2.1 Test guest flow (public)

Open a known guest token URL:

- `https://matan23104.github.io/wedding-rsvp/?t=YOUR_TOKEN`

Validate:

- Page loads without JS/database errors
- Guest greeting appears (token recognized)
- RSVP submit works
- Question submit works
- Countdown and language switch work

### 2.2 Test admin flow

Open:

- `https://matan23104.github.io/wedding-rsvp/MPadmin.html`

Validate:

- Login works with Supabase email/password
- Guest list loads
- Add guest works
- Edit guest status works
- Delete guest works
- Questions tab load/update/delete works
- CSV import/export works
- Logout works

### 2.3 Data validation in Supabase

Run simple checks in SQL Editor:

```sql
-- Recent guest responses
select id, full_name, rsvp_status, guests_count, responded_at
from public.guests
order by responded_at desc
limit 20;
```

```sql
-- Recent questions
select id, guest_name, question_text, status, created_at
from public.questions
order by created_at desc
limit 20;
```

### 2.4 Token-link validation sample

```sql
select full_name, token
from public.guests
where token is not null
order by random()
limit 50;
```

Build links:

- `https://matan23104.github.io/wedding-rsvp/?t=<token>`

Manually open 5-10 random links and verify behavior.

---

## 3) Unpublish (Take Site Offline)

Choose one of these depending on urgency.

### Option A (fastest): disable GitHub Pages

In GitHub:

1. `Settings` -> `Pages`
2. Set source to `None` (or disable Pages)
3. Save

Effect:

- Public website becomes unavailable
- Admin page also unavailable from public URL

### Option B: keep site up but block data operations

In Supabase SQL Editor, temporarily revoke public RPC access:

```sql
revoke execute on function public.get_guest_by_token(text) from anon;
revoke execute on function public.submit_rsvp_by_token(text, text, integer, text) from anon;
revoke execute on function public.submit_rsvp_manual(text, text, text, integer) from anon;
revoke execute on function public.submit_question_public(text, text) from anon;
```

Effect:

- Site may still load static content
- RSVP and question operations stop for public users

To restore later:

```sql
grant execute on function public.get_guest_by_token(text) to anon, authenticated;
grant execute on function public.submit_rsvp_by_token(text, text, integer, text) to anon, authenticated;
grant execute on function public.submit_rsvp_manual(text, text, text, integer) to anon, authenticated;
grant execute on function public.submit_question_public(text, text) to anon, authenticated;
```

---

## 4) Post-Publish Monitoring (recommended)

For the first 48 hours after launch:

- Check admin dashboard every few hours
- Confirm new RSVP rows are being saved
- Confirm questions are being saved
- Export CSV backup at least once daily

---

## 5) Rollback Safety

If a bad deploy happens:

1. Disable GitHub Pages (Option A) to stop traffic
2. Revert broken commit locally or on GitHub
3. Push fixed commit
4. Re-enable GitHub Pages
5. Re-run testing checklist section 2

---

## 6) Useful Links

- Repository: `https://github.com/matan23104/wedding-rsvp`
- Site: `https://matan23104.github.io/wedding-rsvp/`
- Admin: `https://matan23104.github.io/wedding-rsvp/MPadmin.html`

