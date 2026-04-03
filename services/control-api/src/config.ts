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

export const loadConfig = (): Config => {
  const previewBaseDomain = process.env.PREVIEW_BASE_DOMAIN ?? "preview.localhost";
  const previewBaseOrigin = process.env.PREVIEW_BASE_ORIGIN ?? `https://${previewBaseDomain}`;

  return {
    port: readInt("PORT", 8080),
    databaseUrl: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/nomade",
    jwtSecret: process.env.JWT_SECRET ?? "dev-secret-change-me",
    accessTtlSec: readInt("ACCESS_TOKEN_TTL_SEC", 900),
    refreshTtlSec: readInt("REFRESH_TOKEN_TTL_SEC", 60 * 60 * 24 * 30),
    deviceCodeTtlSec: readInt("DEVICE_CODE_TTL_SEC", 600),
    pairingCodeTtlSec: readInt("PAIRING_CODE_TTL_SEC", 600),
    gatewaySecret: process.env.INTERNAL_GATEWAY_SECRET ?? "gateway-dev-secret",
    previewBaseDomain,
    previewBaseOrigin
  };
};
