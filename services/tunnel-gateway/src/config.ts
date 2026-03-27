export interface GatewayConfig {
  port: number;
  controlApiUrl: string;
  gatewaySecret: string;
  previewBaseDomain: string;
}

const readInt = (name: string, fallback: number): number => {
  const value = process.env[name];
  if (!value) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed)) {
    throw new Error(`Invalid integer for ${name}`);
  }
  return parsed;
};

export const loadConfig = (): GatewayConfig => {
  return {
    port: readInt("PORT", 8081),
    controlApiUrl: process.env.CONTROL_API_URL ?? "http://localhost:8080",
    gatewaySecret: process.env.INTERNAL_GATEWAY_SECRET ?? "gateway-dev-secret",
    previewBaseDomain: process.env.PREVIEW_BASE_DOMAIN ?? "preview.localhost"
  };
};
