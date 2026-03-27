import { pairAgent } from "./pair.js";
import { runAgent } from "./runner.js";

const readArg = (name: string): string | undefined => {
  const index = process.argv.findIndex((item) => item === `--${name}`);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
};

const command = process.argv[2] ?? "run";

const main = async (): Promise<void> => {
  if (command === "pair") {
    const serverUrl = readArg("server-url") ?? process.env.CONTROL_HTTP_URL;
    const pairingCode = readArg("pairing-code") ?? process.env.PAIRING_CODE;
    if (!serverUrl || !pairingCode) {
      throw new Error("pair requires --server-url and --pairing-code");
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
