import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export interface AgentConfig {
  controlHttpUrl: string;
  controlWsUrl: string;
  agentId: string;
  agentToken: string;
  name: string;
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

export const readConfig = async (filePath: string): Promise<AgentConfig> => {
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw) as AgentConfig;
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
