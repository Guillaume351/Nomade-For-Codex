import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export type KeepAwakeMode = "never" | "active";
export type OfflineTurnDefault = "prompt" | "defer" | "fail";

export interface AgentConfig {
  controlHttpUrl: string;
  controlWsUrl: string;
  agentId: string;
  agentToken: string;
  name: string;
  keepAwakeMode?: KeepAwakeMode;
  offlineTurnDefault?: OfflineTurnDefault;
  reconnectMaxSeconds?: number;
}

export interface UserSessionConfig {
  controlHttpUrl: string;
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
  email?: string;
  e2e?: {
    epoch: number;
    rootKey: string;
    device: {
      deviceId: string;
      encPublicKey: string;
      encPrivateKey: string;
      signPublicKey: string;
      signPrivateKey: string;
      createdAt: string;
    };
    peers: Record<
      string,
      {
        deviceId: string;
        encPublicKey: string;
        signPublicKey: string;
        addedAt: string;
      }
    >;
    seqByScope?: Record<string, number>;
  };
}

export const defaultConfigPath = (): string => {
  return path.join(os.homedir(), ".config", "nomade-agent", "config.json");
};

export const defaultSessionPath = (): string => {
  return path.join(os.homedir(), ".config", "nomade-agent", "session.json");
};

export const defaultControlHttpUrl = (): string => {
  return process.env.CONTROL_HTTP_URL?.trim() || "https://nomade.d1.guillaumeclaverie.com";
};

const parseKeepAwakeMode = (value: unknown): KeepAwakeMode | undefined => {
  if (value === "never" || value === "active") {
    return value;
  }
  return undefined;
};

const parseOfflineTurnDefault = (value: unknown): OfflineTurnDefault | undefined => {
  if (value === "prompt" || value === "defer" || value === "fail") {
    return value;
  }
  return undefined;
};

const parseReconnectMaxSeconds = (value: unknown): number | undefined => {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }
  const normalized = Math.round(value);
  if (normalized < 5) {
    return 5;
  }
  if (normalized > 300) {
    return 300;
  }
  return normalized;
};

export const readConfig = async (filePath: string): Promise<AgentConfig> => {
  const raw = await fs.readFile(filePath, "utf8");
  const parsed = JSON.parse(raw) as Partial<AgentConfig>;
  const controlHttpUrl =
    typeof parsed.controlHttpUrl === "string" ? parsed.controlHttpUrl.trim() : "";
  const controlWsUrl = typeof parsed.controlWsUrl === "string" ? parsed.controlWsUrl.trim() : "";
  const agentId = typeof parsed.agentId === "string" ? parsed.agentId.trim() : "";
  const agentToken = typeof parsed.agentToken === "string" ? parsed.agentToken.trim() : "";
  const name = typeof parsed.name === "string" ? parsed.name.trim() : "";
  if (!controlHttpUrl || !controlWsUrl || !agentId || !agentToken || !name) {
    throw new Error(`invalid_agent_config:${filePath}`);
  }
  return {
    controlHttpUrl,
    controlWsUrl,
    agentId,
    agentToken,
    name,
    keepAwakeMode: parseKeepAwakeMode(parsed.keepAwakeMode),
    offlineTurnDefault: parseOfflineTurnDefault(parsed.offlineTurnDefault),
    reconnectMaxSeconds: parseReconnectMaxSeconds(parsed.reconnectMaxSeconds)
  };
};

export const writeConfig = async (filePath: string, config: AgentConfig): Promise<void> => {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(config, null, 2));
};

export const readUserSession = async (filePath: string): Promise<UserSessionConfig> => {
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw) as UserSessionConfig;
};

export const writeUserSession = async (filePath: string, config: UserSessionConfig): Promise<void> => {
  await fs.mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
  await fs.writeFile(filePath, JSON.stringify(config, null, 2), { mode: 0o600 });
  await fs.chmod(filePath, 0o600);
};
