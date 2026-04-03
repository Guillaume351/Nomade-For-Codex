import os from "node:os";
import { z } from "zod";
import { defaultConfigPath, writeConfig } from "./config.js";

const responseSchema = z.object({
  agentId: z.string(),
  agentToken: z.string()
});

interface PairArgs {
  serverUrl: string;
  pairingCode: string;
  name?: string;
  configPath?: string;
}

export const pairAgent = async (args: PairArgs): Promise<void> => {
  const name = args.name ?? os.hostname();
  const endpoint = `${args.serverUrl.replace(/\/$/, "")}/agents/register`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ pairingCode: args.pairingCode, name })
  });

  if (!response.ok) {
    const text = await response.text();
    if (response.status === 403) {
      let payload: Record<string, unknown> | null = null;
      try {
        payload = JSON.parse(text) as Record<string, unknown>;
      } catch {
        payload = null;
      }
      if (payload?.error === "device_limit_reached") {
        const upgradeUrl = typeof payload.upgradeUrl === "string" ? payload.upgradeUrl : "";
        throw new Error(
          `Pairing blocked: device_limit_reached (${payload.currentAgents ?? "?"}/${payload.maxAgents ?? "?"}). ${
            upgradeUrl ? `Upgrade: ${upgradeUrl}` : ""
          }`
        );
      }
    }
    throw new Error(`Pairing failed (${response.status}): ${text}`);
  }

  const payload = responseSchema.parse(await response.json());
  const controlHttpUrl = args.serverUrl.replace(/\/$/, "");
  const controlWsUrl = controlHttpUrl.replace(/^http/, "ws") + "/ws";

  const targetConfig = args.configPath ?? defaultConfigPath();
  await writeConfig(targetConfig, {
    controlHttpUrl,
    controlWsUrl,
    agentId: payload.agentId,
    agentToken: payload.agentToken,
    name
  });

  console.log(`[agent] paired and saved config to ${targetConfig}`);
};
