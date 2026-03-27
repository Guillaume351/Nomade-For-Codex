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

export const defaultConfigPath = (): string => {
  return path.join(os.homedir(), ".config", "nomade-agent", "config.json");
};

export const readConfig = async (filePath: string): Promise<AgentConfig> => {
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw) as AgentConfig;
};

export const writeConfig = async (filePath: string, config: AgentConfig): Promise<void> => {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(config, null, 2));
};
