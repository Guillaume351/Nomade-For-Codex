#!/usr/bin/env node

import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { pairAgent } from "./pair.js";
import { runAgent } from "./runner.js";
import {
  createPairingCodeFromSession,
  ensureSession,
  loginWithDeviceCode,
  logoutSession,
  printWhoAmI
} from "./user-auth.js";
import {
  readConfig,
  readUserSession,
  defaultConfigPath,
  defaultControlHttpUrl,
  defaultSessionPath,
  type KeepAwakeMode,
  type OfflineTurnDefault
} from "./config.js";
import { hasOption, parseCliArgs, readOption } from "./cli-args.js";
import {
  defaultLogPath,
  defaultRuntimePath,
  inspectRuntime,
  readLastLogLines,
  removeAgentState,
  startRuntime,
  stopRuntime
} from "./lifecycle.js";

const readKeepAwake = (options: Map<string, string | true>): KeepAwakeMode | undefined => {
  const value = readOption(options, "keep-awake");
  if (!value) {
    return undefined;
  }
  if (value === "never" || value === "active") {
    return value;
  }
  throw new Error(`invalid --keep-awake value: ${value} (expected never|active)`);
};

const readOfflineTurnDefault = (
  options: Map<string, string | true>
): OfflineTurnDefault | undefined => {
  const value = readOption(options, "offline-turn-default");
  if (!value) {
    return undefined;
  }
  if (value === "prompt" || value === "defer" || value === "fail") {
    return value;
  }
  throw new Error(`invalid --offline-turn-default value: ${value} (expected prompt|defer|fail)`);
};

const readReconnectMaxSeconds = (options: Map<string, string | true>): number | undefined => {
  const raw = readOption(options, "reconnect-max-seconds");
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

const isNotFoundError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") {
    return false;
  }
  return (error as NodeJS.ErrnoException).code === "ENOENT";
};

const normalizeServerUrl = (value: string): string => value.replace(/\/$/, "");

const printHelp = (): void => {
  console.log(`
Nomade Agent CLI
----------------
Commands:
  install       Guided setup (login + pair + optional start)
  login         Authenticate your user session
  whoami        Show authenticated account and plan entitlements
  pair          Register/pair this machine as an agent
  start         Start agent in background (daemon mode)
  stop          Stop background agent
  restart       Restart background agent
  status        Show setup + runtime status
  logs          Print agent daemon logs
  run           Run agent in foreground
  logout        Revoke/clear local user session
  uninstall     Stop daemon and remove local agent state
  help          Show this help

Main options:
  --server-url <url>            Control API base URL
  --config <path>               Agent config file path
  --session <path>              User session file path
  --runtime <path>              Runtime state file path (daemon)
  --log-file <path>             Daemon log file path
  --name <value>                Agent name for pairing
  --pairing-code <value>        Pairing code (optional, auto-generated otherwise)
  --open-browser                Open browser during login (legacy flow)
  --no-start                    For install: skip daemon start
  --keep-awake <never|active>   Runtime keep-awake mode
  --offline-turn-default <prompt|defer|fail>
  --reconnect-max-seconds <5-300>
  --lines <n>                   For logs: number of lines (default 120)
  --all                         For logs: print full log file
  --json                        For status: machine-readable output
`.trim());
};

const resolvePaths = (options: Map<string, string | true>) => {
  return {
    configPath: readOption(options, "config") ?? defaultConfigPath(),
    sessionPath: readOption(options, "session") ?? defaultSessionPath(),
    runtimePath: readOption(options, "runtime") ?? defaultRuntimePath(),
    logPath: readOption(options, "log-file") ?? defaultLogPath()
  };
};

const buildRunArgs = (params: {
  options: Map<string, string | true>;
  configPath: string;
}): string[] => {
  const keepAwake = readKeepAwake(params.options);
  const offlineTurnDefault = readOfflineTurnDefault(params.options);
  const reconnectMaxSeconds = readReconnectMaxSeconds(params.options);
  const runArgs = ["--config", params.configPath];
  if (keepAwake) {
    runArgs.push("--keep-awake", keepAwake);
  }
  if (offlineTurnDefault) {
    runArgs.push("--offline-turn-default", offlineTurnDefault);
  }
  if (typeof reconnectMaxSeconds === "number") {
    runArgs.push("--reconnect-max-seconds", String(reconnectMaxSeconds));
  }
  return runArgs;
};

const readLogLinesOption = (options: Map<string, string | true>): number => {
  const raw = readOption(options, "lines");
  if (!raw) {
    return 120;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || Number.isNaN(parsed) || parsed <= 0) {
    throw new Error(`invalid --lines value: ${raw}`);
  }
  return parsed;
};

const startDaemon = async (options: Map<string, string | true>): Promise<void> => {
  const paths = resolvePaths(options);
  await readConfig(paths.configPath);
  const runtime = await inspectRuntime({
    runtimePath: paths.runtimePath,
    cleanupStale: true
  });
  if (runtime.running && runtime.state) {
    console.log(`[agent] daemon already running (pid ${runtime.state.pid})`);
    return;
  }
  const scriptPath = fileURLToPath(import.meta.url);
  const started = await startRuntime({
    scriptPath,
    runtimePath: paths.runtimePath,
    logPath: paths.logPath,
    configPath: paths.configPath,
    runArgs: buildRunArgs({
      options,
      configPath: paths.configPath
    })
  });
  console.log(`[agent] daemon started (pid ${started.pid})`);
  console.log(`[agent] logs: ${started.logPath}`);
};

const stopDaemon = async (options: Map<string, string | true>): Promise<void> => {
  const { runtimePath } = resolvePaths(options);
  const stopped = await stopRuntime({ runtimePath });
  if (!stopped.state) {
    console.log("[agent] daemon is not running");
    return;
  }
  if (stopped.staleState) {
    console.log("[agent] cleaned stale runtime state");
    return;
  }
  console.log(
    `[agent] daemon stopped (pid ${stopped.state.pid}${stopped.forced ? ", forced shutdown" : ""})`
  );
};

const statusCommand = async (options: Map<string, string | true>): Promise<void> => {
  const paths = resolvePaths(options);
  const runtime = await inspectRuntime({
    runtimePath: paths.runtimePath,
    cleanupStale: false
  });

  const config = await readConfig(paths.configPath).catch(() => null);
  const session = await readUserSession(paths.sessionPath).catch(() => null);
  const runtimeLogPath = runtime.state?.logPath || paths.logPath;
  const logExists = await fs
    .stat(runtimeLogPath)
    .then(() => true)
    .catch((error) => {
      if (isNotFoundError(error)) {
        return false;
      }
      throw error;
    });

  const payload = {
    running: runtime.running,
    pid: runtime.state?.pid ?? null,
    staleRuntimeState: runtime.staleState,
    serverUrl: config?.controlHttpUrl ?? session?.controlHttpUrl ?? null,
    userEmail: session?.email ?? null,
    configPath: paths.configPath,
    configPresent: Boolean(config),
    sessionPath: paths.sessionPath,
    sessionPresent: Boolean(session),
    runtimePath: paths.runtimePath,
    logPath: runtimeLogPath,
    logPresent: logExists
  };

  if (hasOption(options, "json")) {
    console.log(JSON.stringify(payload, null, 2));
    return;
  }

  console.log("Nomade Agent Status");
  console.log("-------------------");
  console.log(`Running: ${payload.running ? `yes (pid ${payload.pid})` : "no"}`);
  console.log(`Config: ${payload.configPresent ? "present" : "missing"} (${payload.configPath})`);
  console.log(`Session: ${payload.sessionPresent ? "present" : "missing"} (${payload.sessionPath})`);
  if (payload.userEmail) {
    console.log(`User: ${payload.userEmail}`);
  }
  if (payload.serverUrl) {
    console.log(`Server: ${payload.serverUrl}`);
  }
  console.log(`Runtime state: ${payload.runtimePath}${payload.staleRuntimeState ? " (stale)" : ""}`);
  console.log(`Log file: ${payload.logPresent ? "present" : "missing"} (${payload.logPath})`);
  if (!payload.sessionPresent) {
    console.log("Next step: nomade-agent login --server-url <url>");
  } else if (!payload.configPresent) {
    console.log("Next step: nomade-agent pair --server-url <url>");
  } else if (!payload.running) {
    console.log("Next step: nomade-agent start");
  }
};

const logsCommand = async (options: Map<string, string | true>): Promise<void> => {
  const paths = resolvePaths(options);
  const runtime = await inspectRuntime({
    runtimePath: paths.runtimePath,
    cleanupStale: false
  });
  const logPath = runtime.state?.logPath || paths.logPath;
  console.log(`[agent] log file: ${logPath}`);

  if (hasOption(options, "all")) {
    const raw = await fs.readFile(logPath, "utf8").catch((error) => {
      if (isNotFoundError(error)) {
        return "";
      }
      throw error;
    });
    if (!raw.trim().length) {
      console.log("[agent] log file is empty");
      return;
    }
    process.stdout.write(raw.endsWith("\n") ? raw : `${raw}\n`);
    return;
  }

  const lines = await readLastLogLines(logPath, readLogLinesOption(options));
  if (lines.length === 0) {
    console.log("[agent] log file is empty");
    return;
  }
  console.log(lines.join("\n"));
};

const installCommand = async (options: Map<string, string | true>): Promise<void> => {
  const paths = resolvePaths(options);
  const serverUrl = normalizeServerUrl(readOption(options, "server-url") ?? defaultControlHttpUrl());
  const name = readOption(options, "name");
  const openBrowser = hasOption(options, "open-browser");
  const skipStart = hasOption(options, "no-start");
  const suppliedPairingCode = readOption(options, "pairing-code") ?? process.env.PAIRING_CODE;

  console.log(`[agent] install target server ${serverUrl}`);

  let hasValidSession = false;
  try {
    await ensureSession({
      serverUrl,
      sessionPath: paths.sessionPath
    });
    hasValidSession = true;
    console.log("[agent] session ready");
  } catch {
    hasValidSession = false;
  }

  if (!hasValidSession) {
    console.log("[agent] no valid session found, starting login");
    await loginWithDeviceCode({
      serverUrl,
      sessionPath: paths.sessionPath,
      openBrowser
    });
  }

  let shouldPair = true;
  try {
    const config = await readConfig(paths.configPath);
    if (normalizeServerUrl(config.controlHttpUrl) === serverUrl) {
      shouldPair = false;
      console.log("[agent] pairing already configured");
    } else {
      console.log("[agent] existing config points to another server, re-pairing");
    }
  } catch {
    shouldPair = true;
  }

  if (shouldPair) {
    let pairingCode = suppliedPairingCode;
    if (!pairingCode) {
      const generated = await createPairingCodeFromSession({
        serverUrl,
        sessionPath: paths.sessionPath
      });
      pairingCode = generated.pairingCode;
      console.log(`[agent] generated pairing code (expires in ${generated.expiresInSec}s)`);
    }
    await pairAgent({
      serverUrl,
      pairingCode,
      name,
      configPath: paths.configPath
    });
  }

  if (skipStart) {
    console.log("[agent] install complete (daemon not started: --no-start)");
    console.log("Start manually with: nomade-agent start");
    return;
  }

  const runtime = await inspectRuntime({
    runtimePath: paths.runtimePath,
    cleanupStale: true
  });
  if (runtime.running && runtime.state) {
    console.log(`[agent] daemon already running (pid ${runtime.state.pid})`);
    return;
  }

  await startDaemon(options);
};

const uninstallCommand = async (options: Map<string, string | true>): Promise<void> => {
  const paths = resolvePaths(options);
  const runtimeStopped = await stopRuntime({ runtimePath: paths.runtimePath });
  if (runtimeStopped.stopped && runtimeStopped.state) {
    console.log(`[agent] stopped daemon (pid ${runtimeStopped.state.pid})`);
  }

  const session = await readUserSession(paths.sessionPath).catch(() => null);
  if (session) {
    await logoutSession({
      serverUrl: readOption(options, "server-url") ?? session.controlHttpUrl,
      sessionPath: paths.sessionPath
    });
  }

  await removeAgentState({
    configPath: paths.configPath,
    sessionPath: paths.sessionPath,
    runtimePath: paths.runtimePath,
    logPath: paths.logPath
  });

  console.log("[agent] local state removed");
  console.log("[agent] to remove the CLI binary: npm uninstall -g @nomade/agent");
};

const main = async (): Promise<void> => {
  const parsed = parseCliArgs(process.argv.slice(2));
  const options = parsed.options;
  const command = parsed.command;

  if (command === "help" || command === "--help" || hasOption(options, "help")) {
    printHelp();
    return;
  }

  if (command === "install" || command === "setup") {
    await installCommand(options);
    return;
  }

  if (command === "start") {
    await startDaemon(options);
    return;
  }

  if (command === "stop") {
    await stopDaemon(options);
    return;
  }

  if (command === "restart") {
    await stopDaemon(options);
    await startDaemon(options);
    return;
  }

  if (command === "status") {
    await statusCommand(options);
    return;
  }

  if (command === "logs") {
    await logsCommand(options);
    return;
  }

  if (command === "uninstall") {
    await uninstallCommand(options);
    return;
  }

  if (command === "login") {
    const serverUrl = readOption(options, "server-url") ?? defaultControlHttpUrl();
    await loginWithDeviceCode({
      serverUrl,
      sessionPath: readOption(options, "session") ?? defaultSessionPath(),
      openBrowser: hasOption(options, "open-browser")
    });
    return;
  }

  if (command === "logout") {
    await logoutSession({
      serverUrl: readOption(options, "server-url"),
      sessionPath: readOption(options, "session") ?? defaultSessionPath()
    });
    console.log("[agent] user session cleared");
    return;
  }

  if (command === "whoami") {
    const serverUrl = readOption(options, "server-url") ?? defaultControlHttpUrl();
    await printWhoAmI({
      serverUrl,
      sessionPath: readOption(options, "session") ?? defaultSessionPath()
    });
    return;
  }

  if (command === "pair") {
    const serverUrl = readOption(options, "server-url") ?? defaultControlHttpUrl();
    let pairingCode = readOption(options, "pairing-code") ?? process.env.PAIRING_CODE;
    if (!pairingCode) {
      const sessionPath = readOption(options, "session") ?? defaultSessionPath();
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
      name: readOption(options, "name"),
      configPath: readOption(options, "config")
    });
    return;
  }

  if (command === "run") {
    await runAgent({
      configPath: readOption(options, "config"),
      keepAwakeMode: readKeepAwake(options),
      offlineTurnDefault: readOfflineTurnDefault(options),
      reconnectMaxSeconds: readReconnectMaxSeconds(options)
    });
    return;
  }

  printHelp();
  throw new Error(`unknown_command:${command}`);
};

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error("[agent] fatal", message);
  process.exit(1);
});
