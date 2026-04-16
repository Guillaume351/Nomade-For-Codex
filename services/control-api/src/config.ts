export type AuthEmailMode = "log" | "smtp";
export type BillingMode = "cloud" | "self_host";

export interface Config {
  port: number;
  databaseUrl: string;
  jwtSecret: string;
  betterAuthSecret: string;
  authDebugLogs: boolean;
  httpAccessLogs: boolean;
  accessTtlSec: number;
  refreshTtlSec: number;
  deviceCodeTtlSec: number;
  pairingCodeTtlSec: number;
  gatewaySecret: string;
  previewBaseDomain: string;
  previewBaseOrigin: string;
  appBaseUrl: string;
  authEmailMode: AuthEmailMode;
  magicLinkAllowedAttempts: number;
  magicLinkExpiresInSec: number;
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
  revenueCatWebhookAuth?: string;
  revenueCatProductPlanMap: Record<string, string>;
  billingMode: BillingMode;
  pushEnabled: boolean;
  firebaseProjectId?: string;
  firebaseClientEmail?: string;
  firebasePrivateKey?: string;
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

const parseBillingMode = (raw: string | undefined): BillingMode => {
  const normalized = (raw ?? "cloud").trim().toLowerCase();
  if (normalized === "cloud" || normalized === "self_host") {
    return normalized;
  }
  throw new Error(`Invalid BILLING_MODE: ${raw}. Expected \"cloud\" or \"self_host\".`);
};

const parseJsonObjectRecord = (
  name: string,
  raw: string | undefined
): Record<string, string> => {
  if (!raw || raw.trim().length === 0) {
    return {};
  }
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch {
    throw new Error(`Invalid JSON for ${name}.`);
  }
  if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new Error(`Invalid JSON object for ${name}.`);
  }

  const map: Record<string, string> = {};
  for (const [key, value] of Object.entries(decoded as Record<string, unknown>)) {
    const normalizedKey = key.trim();
    if (normalizedKey.length === 0) {
      continue;
    }
    const normalizedValue = typeof value === "string" ? value.trim() : "";
    if (normalizedValue.length === 0) {
      continue;
    }
    map[normalizedKey] = normalizedValue;
  }
  return map;
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
  const revenueCatWebhookAuth = readOptional("REVENUECAT_WEBHOOK_AUTH");
  const revenueCatProductPlanMap = parseJsonObjectRecord(
    "REVENUECAT_PRODUCT_PLAN_MAP",
    process.env.REVENUECAT_PRODUCT_PLAN_MAP
  );
  const billingMode = parseBillingMode(process.env.BILLING_MODE);
  const firebaseProjectId = readOptional("FIREBASE_PROJECT_ID");
  const firebaseClientEmail = readOptional("FIREBASE_CLIENT_EMAIL");
  const firebasePrivateKeyRaw = readOptional("FIREBASE_PRIVATE_KEY");
  const firebasePrivateKey = firebasePrivateKeyRaw ? firebasePrivateKeyRaw.replace(/\\n/g, "\n") : undefined;
  const pushEnabled = Boolean(firebaseProjectId && firebaseClientEmail && firebasePrivateKey);
  if (!pushEnabled && (firebaseProjectId || firebaseClientEmail || firebasePrivateKey)) {
    console.warn("[control-api] push notifications disabled: incomplete Firebase config.");
  }
  const magicLinkAllowedAttempts = readInt("AUTH_MAGIC_LINK_ALLOWED_ATTEMPTS", 5);
  const magicLinkExpiresInSec = readInt("AUTH_MAGIC_LINK_EXPIRES_SEC", 60 * 15);
  if (magicLinkAllowedAttempts < 1) {
    throw new Error("AUTH_MAGIC_LINK_ALLOWED_ATTEMPTS must be >= 1.");
  }
  if (magicLinkExpiresInSec < 60) {
    throw new Error("AUTH_MAGIC_LINK_EXPIRES_SEC must be >= 60.");
  }

  return {
    port: readInt("PORT", 8080),
    databaseUrl: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/nomade",
    jwtSecret,
    betterAuthSecret,
    authDebugLogs: readBool("AUTH_DEBUG_LOGS", false),
    httpAccessLogs: readBool("HTTP_ACCESS_LOGS", true),
    accessTtlSec: readInt("ACCESS_TOKEN_TTL_SEC", 900),
    refreshTtlSec: readInt("REFRESH_TOKEN_TTL_SEC", 60 * 60 * 24 * 30),
    deviceCodeTtlSec: readInt("DEVICE_CODE_TTL_SEC", 600),
    pairingCodeTtlSec: readInt("PAIRING_CODE_TTL_SEC", 600),
    gatewaySecret,
    previewBaseDomain,
    previewBaseOrigin,
    appBaseUrl,
    authEmailMode,
    magicLinkAllowedAttempts,
    magicLinkExpiresInSec,
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
    revenueCatWebhookAuth,
    revenueCatProductPlanMap,
    billingMode,
    pushEnabled,
    firebaseProjectId,
    firebaseClientEmail,
    firebasePrivateKey,
    paidMaxAgents: readInt("PAID_MAX_AGENTS", 10),
    freeMaxAgents: readInt("FREE_MAX_AGENTS", 1)
  };
};
