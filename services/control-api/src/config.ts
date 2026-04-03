export type AuthEmailMode = "log" | "smtp";

export interface Config {
  port: number;
  databaseUrl: string;
  jwtSecret: string;
  betterAuthSecret: string;
  accessTtlSec: number;
  refreshTtlSec: number;
  deviceCodeTtlSec: number;
  pairingCodeTtlSec: number;
  gatewaySecret: string;
  previewBaseDomain: string;
  previewBaseOrigin: string;
  appBaseUrl: string;
  authEmailMode: AuthEmailMode;
  smtpHost?: string;
  smtpPort: number;
  smtpSecure: boolean;
  smtpUser?: string;
  smtpPass?: string;
  smtpFrom: string;
  googleClientId?: string;
  googleClientSecret?: string;
  appleClientId?: string;
  appleClientSecret?: string;
  appleBundleId?: string;
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

const readOptional = (name: string): string | undefined => {
  const raw = process.env[name]?.trim();
  if (!raw) {
    return undefined;
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

const parseAuthEmailMode = (raw: string): AuthEmailMode => {
  const normalized = raw.trim().toLowerCase();
  if (normalized === "log" || normalized === "smtp") {
    return normalized;
  }
  throw new Error(`Invalid AUTH_EMAIL_MODE: ${raw}. Expected \"log\" or \"smtp\".`);
};

export const loadConfig = (): Config => {
  const nodeEnv = process.env.NODE_ENV?.trim().toLowerCase() ?? "";
  const isProduction = nodeEnv === "production";

  const previewBaseDomain = process.env.PREVIEW_BASE_DOMAIN ?? "preview.localhost";
  const previewBaseOrigin = process.env.PREVIEW_BASE_ORIGIN ?? `https://${previewBaseDomain}`;
  const appBaseUrl = process.env.APP_BASE_URL ?? "http://localhost:8080";

  const jwtSecret = ensureNotWeakSecret("JWT_SECRET", readRequired("JWT_SECRET"));
  const betterAuthSecret = ensureNotWeakSecret(
    "BETTER_AUTH_SECRET",
    readOptional("BETTER_AUTH_SECRET") ?? jwtSecret
  );
  const gatewaySecret = ensureNotWeakSecret("INTERNAL_GATEWAY_SECRET", readRequired("INTERNAL_GATEWAY_SECRET"));

  const smtpHost = readOptional("AUTH_SMTP_HOST");
  const smtpPort = readInt("AUTH_SMTP_PORT", 587);
  const authEmailMode = parseAuthEmailMode(process.env.AUTH_EMAIL_MODE ?? (smtpHost ? "smtp" : "log"));
  if (authEmailMode === "smtp" && !smtpHost) {
    throw new Error("AUTH_SMTP_HOST is required when AUTH_EMAIL_MODE=smtp.");
  }

  if (isProduction && authEmailMode === "log") {
    console.warn("[control-api] AUTH_EMAIL_MODE=log in production. Email links will be logged only.");
  }

  const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
  const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  const stripeProPriceId = process.env.STRIPE_PRO_PRICE_ID;
  const stripeEnabled = Boolean(stripeSecretKey);

  return {
    port: readInt("PORT", 8080),
    databaseUrl: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/nomade",
    jwtSecret,
    betterAuthSecret,
    accessTtlSec: readInt("ACCESS_TOKEN_TTL_SEC", 900),
    refreshTtlSec: readInt("REFRESH_TOKEN_TTL_SEC", 60 * 60 * 24 * 30),
    deviceCodeTtlSec: readInt("DEVICE_CODE_TTL_SEC", 600),
    pairingCodeTtlSec: readInt("PAIRING_CODE_TTL_SEC", 600),
    gatewaySecret,
    previewBaseDomain,
    previewBaseOrigin,
    appBaseUrl,
    authEmailMode,
    smtpHost,
    smtpPort,
    smtpSecure: readBool("AUTH_SMTP_SECURE", smtpPort === 465),
    smtpUser: readOptional("AUTH_SMTP_USER"),
    smtpPass: readOptional("AUTH_SMTP_PASS"),
    smtpFrom: process.env.AUTH_SMTP_FROM ?? "Nomade <no-reply@nomade.local>",
    googleClientId: readOptional("GOOGLE_CLIENT_ID"),
    googleClientSecret: readOptional("GOOGLE_CLIENT_SECRET"),
    appleClientId: readOptional("APPLE_CLIENT_ID"),
    appleClientSecret: readOptional("APPLE_CLIENT_SECRET"),
    appleBundleId: readOptional("APPLE_BUNDLE_ID"),
    stripeEnabled,
    stripeSecretKey,
    stripeWebhookSecret,
    stripeProPriceId,
    paidMaxAgents: readInt("PAID_MAX_AGENTS", 10),
    freeMaxAgents: readInt("FREE_MAX_AGENTS", 1)
  };
};
