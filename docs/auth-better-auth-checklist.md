# Better Auth Rollout Checklist

This runbook is the reference for deploying Nomade authentication with:
- Email/password
- Mandatory email verification
- Password reset
- Magic link login
- Optional Google/Apple (disabled by default)

## 1) What Is Already Implemented

Server integration:
- Better Auth handler mounted at `/api/auth/*` in `services/control-api/src/server.ts`
- Better Auth runtime and providers in `services/control-api/src/better-auth.ts`
- Device flow compatibility kept (`/auth/device/start`, `/auth/device/poll`, `/auth/device/approve`)

Web pages:
- `/web/login`
- `/web/signup`
- `/web/forgot-password`
- `/web/reset-password`
- `/web/verify-email`
- `/web/activate` (approval page for device code)

Mobile:
- Browser-based device flow (`verificationUriComplete` + poll)
- No legacy `{ userCode, email }` approve call

## 2) Required Environment Variables (Minimum)

Set these for a real deployment:

- `DATABASE_URL`
- `JWT_SECRET` (strong, >=24 chars)
- `INTERNAL_GATEWAY_SECRET` (strong, >=24 chars)
- `BETTER_AUTH_SECRET` (strong, >=24 chars; if empty, falls back to `JWT_SECRET`, but explicit value is recommended)
- `APP_BASE_URL` (public URL, ex: `https://nomade.example.com`)
- `AUTH_EMAIL_MODE=smtp`
- `AUTH_SMTP_HOST`
- `AUTH_SMTP_PORT`
- `AUTH_SMTP_SECURE` (`true` on 465, often `false` on 587/STARTTLS)
- `AUTH_SMTP_FROM`
- `AUTH_SMTP_USER` and `AUTH_SMTP_PASS` (if required by provider)

Optional social login (prepared, disabled until both vars exist):
- Google: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- Apple: `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`, optional `APPLE_BUNDLE_ID`

## 3) Email Delivery Options

Local/dev (free):
- `AUTH_EMAIL_MODE=log` (emails logged in backend logs), or
- Mailpit SMTP (`deploy/selfhost/docker-compose.dev.yml` already includes it)

Deployed/prod (low cost / free tier available):
- Use an SMTP provider (example: Brevo SMTP free tier)
- Configure DNS for deliverability:
  - SPF
  - DKIM
  - DMARC

## 4) Database Migrations (Important)

Auth schema migration is already handled automatically on control-api startup by:
- `ensureSchema(pool)` in `services/control-api/src/server.ts`
- SQL DDL in `services/control-api/src/db.ts`

Auth-related changes applied by startup:
- `users` extension:
  - `name` (backfilled from email local part)
  - `email_verified`
  - `image`
  - `updated_at`
- Better Auth tables:
  - `auth_sessions`
  - `auth_accounts`
  - `auth_verifications`
- Indexes on these tables

Manual fallback migration SQL is provided here:
- `deploy/selfhost/sql/2026-04-03-better-auth.sql`

Run manually if your runtime DB user cannot run DDL on startup:

```bash
psql "$DATABASE_URL" -f deploy/selfhost/sql/2026-04-03-better-auth.sql
```

## 5) Deployment Steps

1. Backup DB.
2. Deploy the new `control-api` image/code.
3. Set env vars from section 2.
4. Restart `control-api` (this triggers automatic schema migration).
5. Verify health:

```bash
curl -i https://<your-domain>/health
```

6. Verify auth routes reachable:

```bash
curl -i https://<your-domain>/api/auth/get-session
```

7. Open browser:
- `https://<your-domain>/web/signup`
- Create account
- Confirm verification email
- Log in

8. Verify reset flow:
- `https://<your-domain>/web/forgot-password`

9. Verify device flow compatibility:
- Start login from CLI/mobile
- Open `verificationUriComplete`
- Approve on `/web/activate`
- Poll reaches `status=ok`

10. (Optional) Enable Google/Apple by setting provider env vars and redeploy.

## 6) Post-Deploy Validation SQL

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'users'
  AND column_name IN ('name', 'email_verified', 'image', 'updated_at');

SELECT table_name
FROM information_schema.tables
WHERE table_name IN ('auth_sessions', 'auth_accounts', 'auth_verifications');
```

## 7) Notes

- Existing accounts migration strategy is `claim via reset`: users with pre-existing email identities can claim access via forgot-password.
- `AUTH_EMAIL_MODE=log` is acceptable for local/dev only.
- Apple login in production requires HTTPS and Apple-side app/service configuration.
