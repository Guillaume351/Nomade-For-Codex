#!/usr/bin/env node

import { pairAgent } from "./pair.js";
import { runAgent } from "./runner.js";
import {
  createPairingCodeFromSession,
  loginWithDeviceCode,
  logoutSession,
  printWhoAmI
} from "./user-auth.js";
import {
  defaultConfigPath,
  defaultControlHttpUrl,
  defaultSessionPath,
  type KeepAwakeMode,
  type OfflineTurnDefault
} from "./config.js";

const readArg = (name: string): string | undefined => {
  const index = process.argv.findIndex((item) => item === `--${name}`);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
};

const hasFlag = (name: string): boolean => process.argv.includes(`--${name}`);
const readKeepAwake = (): KeepAwakeMode | undefined => {
  const value = readArg("keep-awake");
  if (!value) {
    return undefined;
  }
  if (value === "never" || value === "active") {
    return value;
  }
  throw new Error(`invalid --keep-awake value: ${value} (expected never|active)`);
};

const readOfflineTurnDefault = (): OfflineTurnDefault | undefined => {
  const value = readArg("offline-turn-default");
  if (!value) {
    return undefined;
  }
  if (value === "prompt" || value === "defer" || value === "fail") {
    return value;
  }
  throw new Error(`invalid --offline-turn-default value: ${value} (expected prompt|defer|fail)`);
};

const readReconnectMaxSeconds = (): number | undefined => {
  const raw = readArg("reconnect-max-seconds");
  if (!raw) {
    return undefined;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || Number.isNaN(parsed)) {
    throw new Error(`invalid --reconnect-max-seconds value: ${raw}`);
  }
  if (parsed < 5 || parsed > 300) {
    throw new Error("--reconnect-max-seconds must be between 5 and 300");
  }
  return parsed;
};

const command = process.argv[2] ?? "run";

const main = async (): Promise<void> => {
  if (command === "login") {
    const serverUrl = readArg("server-url") ?? defaultControlHttpUrl();
    await loginWithDeviceCode({
      serverUrl,
      sessionPath: readArg("session") ?? defaultSessionPath(),
      openBrowser: hasFlag("open-browser")
    });
    return;
  }

  if (command === "logout") {
    await logoutSession({
      serverUrl: readArg("server-url"),
      sessionPath: readArg("session") ?? defaultSessionPath()
    });
    console.log("[agent] user session cleared");
    return;
  }

  if (command === "whoami") {
    const configPath = readArg("config") ?? defaultConfigPath();
    const serverUrl = readArg("server-url") ?? defaultControlHttpUrl();
    await printWhoAmI({
      serverUrl,
      sessionPath: readArg("session") ?? defaultSessionPath()
    });
    return;
  }

  if (command === "pair") {
    const serverUrl = readArg("server-url") ?? defaultControlHttpUrl();
    let pairingCode = readArg("pairing-code") ?? process.env.PAIRING_CODE;
    if (!pairingCode) {
      const sessionPath = readArg("session") ?? defaultSessionPath();
      const generated = await createPairingCodeFromSession({
        serverUrl,
        sessionPath
      }).catch((error) => {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(
          `pair could not create a pairing code from user session (${sessionPath}): ${message}. Run login first or pass --pairing-code.`
        );
      });
      pairingCode = generated.pairingCode;
      console.log(`[agent] generated pairing code (expires in ${generated.expiresInSec}s)`);
    }
    await pairAgent({
      serverUrl,
      pairingCode,
      name: readArg("name"),
      configPath: readArg("config")
    });
    return;
  }

  if (command === "run") {
    await runAgent({
      configPath: readArg("config"),
      keepAwakeMode: readKeepAwake(),
      offlineTurnDefault: readOfflineTurnDefault(),
      reconnectMaxSeconds: readReconnectMaxSeconds()
    });
    return;
  }

  throw new Error(`Unknown command: ${command}`);
};

main().catch((error) => {
  console.error("[agent] fatal", error);
  process.exit(1);
});
