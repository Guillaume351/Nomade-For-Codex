import { pairAgent } from "./pair.js";
import { runAgent } from "./runner.js";
import {
  createPairingCodeFromSession,
  loginWithDeviceCode,
  logoutSession,
  printWhoAmI
} from "./user-auth.js";
import { defaultConfigPath, defaultSessionPath } from "./config.js";

const readArg = (name: string): string | undefined => {
  const index = process.argv.findIndex((item) => item === `--${name}`);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
};

const hasFlag = (name: string): boolean => process.argv.includes(`--${name}`);

const command = process.argv[2] ?? "run";

const main = async (): Promise<void> => {
  if (command === "login") {
    const serverUrl = readArg("server-url") ?? process.env.CONTROL_HTTP_URL;
    if (!serverUrl) {
      throw new Error("login requires --server-url (or CONTROL_HTTP_URL)");
    }
    await loginWithDeviceCode({
      serverUrl,
      sessionPath: readArg("session") ?? defaultSessionPath(),
      openBrowser: hasFlag("no-open") ? false : true
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
    const serverUrl = readArg("server-url") ?? process.env.CONTROL_HTTP_URL;
    if (!serverUrl) {
      throw new Error(
        `whoami requires --server-url (or CONTROL_HTTP_URL). Agent config path hint: ${configPath}`
      );
    }
    await printWhoAmI({
      serverUrl,
      sessionPath: readArg("session") ?? defaultSessionPath()
    });
    return;
  }

  if (command === "pair") {
    const serverUrl = readArg("server-url") ?? process.env.CONTROL_HTTP_URL;
    let pairingCode = readArg("pairing-code") ?? process.env.PAIRING_CODE;
    if (!serverUrl) {
      throw new Error("pair requires --server-url (or CONTROL_HTTP_URL)");
    }
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
    await runAgent({ configPath: readArg("config") });
    return;
  }

  throw new Error(`Unknown command: ${command}`);
};

main().catch((error) => {
  console.error("[agent] fatal", error);
  process.exit(1);
});
