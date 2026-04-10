# Nuxt SaaS Big-Bang Cutover Checklist

This checklist is for the `nomade.d1.guillaumeclaverie.com` cutover where Nuxt becomes the single public service.

## 1) Current architecture in repo

- Public service: `apps/saas` (Nuxt fullstack).
- Backend contracts are preserved through an embedded backend in the same SaaS process.
- `tunnel-gateway` stays a separate service and must call `CONTROL_API_URL=http://saas:8080`.
- Canonical web routes are:
  - `/login`, `/signup`, `/forgot-password`, `/reset-password`, `/verify-email`
  - `/activate`, `/account`, `/devices`, `/billing`
- Legacy web routes are redirected from `/web/*` to canonical routes.

## 2) Required environment variables (deployed)

Core:
- `DATABASE_URL`
- `JWT_SECRET`
- `INTERNAL_GATEWAY_SECRET`
- `APP_BASE_URL` (public HTTPS URL)
- `BETTER_AUTH_SECRET`

Auth email:
- `AUTH_EMAIL_MODE=smtp`
- `AUTH_SMTP_HOST`
- `AUTH_SMTP_PORT`
- `AUTH_SMTP_SECURE`
- `AUTH_SMTP_FROM`
- `AUTH_SMTP_USER`
- `AUTH_SMTP_PASS`
- `AUTH_MAGIC_LINK_ALLOWED_ATTEMPTS` (default `5`)
- `AUTH_MAGIC_LINK_EXPIRES_SEC` (default `900`)

Observability:
- `HTTP_ACCESS_LOGS=true`
- `AUTH_DEBUG_LOGS=true` (temporary for debug, then set back to `false`)

Optional social login (UI buttons shown only when configured):
- Google: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- Apple: `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`, optional `APPLE_BUNDLE_ID`

Optional Stripe:
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRO_PRICE_ID`

Gateway wiring:
- `CONTROL_API_URL=http://saas:8080`

## 3) Database migrations

No additional schema migration is required for the Nuxt cutover itself.

Auth schema requirements are unchanged and already defined by Better Auth rollout:
- `users` extended columns (`name`, `email_verified`, `image`, `updated_at`)
- `auth_sessions`, `auth_accounts`, `auth_verifications`

If your DB missed these migrations, run:

```bash
psql "$DATABASE_URL" -f deploy/selfhost/sql/2026-04-03-better-auth.sql
```

## 4) Deployment cutover steps

1. Publish/pull `saas` and `tunnel-gateway` images.
2. Update compose env (`SAAS_IMAGE`, `CONTROL_API_URL=http://saas:8080`, SMTP vars).
3. `docker compose up -d`.
4. Check logs:

```bash
docker compose logs -f saas
docker compose logs -f tunnel-gateway
```

5. Health check:

```bash
curl -i https://<domain>/health
```

## 5) Validation checks

Auth/UI:
1. `/login?email=you@example.com` (prefill + access log with masked email)
2. signup
3. verify email
4. login
5. forgot/reset password
6. magic link
7. `/account`, `/devices`, `/billing`

Device flow:
1. `POST /auth/device/start`
2. open `verificationUriComplete`
3. approve on `/activate`
4. `POST /auth/device/poll` -> `ok`

Gateway:
1. tunnel open from agent
2. preview HTTP proxy via gateway
3. internal WS path works (`/internal/tunnels/:slug/ws`)

## 6) Logging expectations

Expected logs in `saas` output:
- `[saas-http]` for every request (`requestId`, method, path, status, duration, ip)
- `[saas-auth] login_query_prefill` for `/login?email=...` (masked)
- `[saas-auth-http]` for `/api/auth/*`
- `[saas-billing-http]` for `/billing/*`
- `[billing-checkout]` / `[billing-portal]` for Stripe session creation (embedded backend)
- `[billing-webhook]` with Stripe `eventId` / `eventType`
- existing auth mail logs for SMTP attempt/success/failure

## 7) Final cleanup milestone

After full endpoint rewrite inside Nuxt (no embedded backend dependency), remove `services/control-api` from repo and image build graph.
