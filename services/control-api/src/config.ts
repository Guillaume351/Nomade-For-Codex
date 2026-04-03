export interface Config {
  port: number;
  databaseUrl: string;
  jwtSecret: string;
  accessTtlSec: number;
  refreshTtlSec: number;
  deviceCodeTtlSec: number;
  pairingCodeTtlSec: number;
  gatewaySecret: string;
  previewBaseDomain: string;
  previewBaseOrigin: string;
  appBaseUrl: string;
  webSessionTtlSec: number;
  webSessionCookieName: string;
  devLoginEnabled: boolean;
  legacyDeviceApproveEnabled: boolean;
  oidcEnabled: boolean;
  oidcAuthorizationUrl?: string;
  oidcTokenUrl?: string;
  oidcUserInfoUrl?: string;
  oidcClientId?: string;
  oidcClientSecret?: string;
  oidcRedirectUrl?: string;
  oidcIssuer?: string;
  oidcScope: string;
  stripeEnabled: boolean;
  stripeSecretKey?: string;
  stripeWebhookSecret?: string;
  stripeProPriceId?: string;
  paidMaxAgents: number;
  freeMaxAgents: number;
}

const readInt = (name: string, defaultValue: number): number => {
  const raw = process.env[name];
  if (!raw) {
    return defaultValue;
  }
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed)) {
    throw new Error(`Invalid integer for ${name}: ${raw}`);
  }
  return parsed;
};

const readBool = (name: string, defaultValue: boolean): boolean => {
  const raw = process.env[name];
  if (!raw) {
    return defaultValue;
  }
  const normalized = raw.trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "on";
};

const readRequired = (name: string): string => {
  const raw = process.env[name]?.trim();
  if (!raw) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return raw;
};

const ensureNotWeakSecret = (name: string, value: string): string => {
  const lowered = value.toLowerCase();
  const knownWeak =
    lowered === "change-me" ||
    lowered === "dev-secret-change-me" ||
    lowered === "gateway-dev-secret" ||
    lowered.includes("change-me");
  if (knownWeak || value.length < 24) {
    throw new Error(`${name} is too weak. Provide a strong random value (>=24 chars).`);
  }
  return value;
};

export const loadConfig = (): Config => {
  const nodeEnv = process.env.NODE_ENV?.trim().toLowerCase() ?? "";
  const isProduction = nodeEnv === "production";
  const previewBaseDomain = process.env.PREVIEW_BASE_DOMAIN ?? "preview.localhost";
  const previewBaseOrigin = process.env.PREVIEW_BASE_ORIGIN ?? `https://${previewBaseDomain}`;
  const appBaseUrl = process.env.APP_BASE_URL ?? "http://localhost:8080";

  const oidcAuthorizationUrl = process.env.OIDC_AUTHORIZATION_URL;
  const oidcTokenUrl = process.env.OIDC_TOKEN_URL;
  const oidcUserInfoUrl = process.env.OIDC_USERINFO_URL;
  const oidcClientId = process.env.OIDC_CLIENT_ID;
  const oidcClientSecret = process.env.OIDC_CLIENT_SECRET;
  const oidcRedirectUrl = process.env.OIDC_REDIRECT_URL;
  const oidcIssuer = process.env.OIDC_ISSUER;
  const oidcEnabled = Boolean(
    oidcAuthorizationUrl &&
      oidcTokenUrl &&
      oidcUserInfoUrl &&
      oidcClientId &&
      oidcClientSecret &&
      oidcRedirectUrl &&
      oidcIssuer
  );

  const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
  const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  const stripeProPriceId = process.env.STRIPE_PRO_PRICE_ID;
  const stripeEnabled = Boolean(stripeSecretKey);

  const jwtSecret = ensureNotWeakSecret("JWT_SECRET", readRequired("JWT_SECRET"));
  const gatewaySecret = ensureNotWeakSecret("INTERNAL_GATEWAY_SECRET", readRequired("INTERNAL_GATEWAY_SECRET"));

  const devLoginEnabled = readBool("DEV_LOGIN_ENABLED", false);
  if (isProduction && devLoginEnabled) {
    throw new Error("DEV_LOGIN_ENABLED must be false in production.");
  }
  const legacyDeviceApproveEnabled = readBool("LEGACY_DEVICE_APPROVE_ENABLED", false);
  if (isProduction && legacyDeviceApproveEnabled) {
    throw new Error("LEGACY_DEVICE_APPROVE_ENABLED must be false in production.");
  }

  return {
    port: readInt("PORT", 8080),
    databaseUrl: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/nomade",
    jwtSecret,
    accessTtlSec: readInt("ACCESS_TOKEN_TTL_SEC", 900),
    refreshTtlSec: readInt("REFRESH_TOKEN_TTL_SEC", 60 * 60 * 24 * 30),
    deviceCodeTtlSec: readInt("DEVICE_CODE_TTL_SEC", 600),
    pairingCodeTtlSec: readInt("PAIRING_CODE_TTL_SEC", 600),
    gatewaySecret,
    previewBaseDomain,
    previewBaseOrigin,
    appBaseUrl,
    webSessionTtlSec: readInt("WEB_SESSION_TTL_SEC", 60 * 60 * 24 * 7),
    webSessionCookieName: process.env.WEB_SESSION_COOKIE_NAME ?? "nomade_web_session",
    devLoginEnabled,
    legacyDeviceApproveEnabled,
    oidcEnabled,
    oidcAuthorizationUrl,
    oidcTokenUrl,
    oidcUserInfoUrl,
    oidcClientId,
    oidcClientSecret,
    oidcRedirectUrl,
    oidcIssuer,
    oidcScope: process.env.OIDC_SCOPE ?? "openid profile email",
    stripeEnabled,
    stripeSecretKey,
    stripeWebhookSecret,
    stripeProPriceId,
    paidMaxAgents: readInt("PAID_MAX_AGENTS", 10),
    freeMaxAgents: readInt("FREE_MAX_AGENTS", 1)
  };
};
