import fs from "node:fs/promises";
import fsSync from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const sleep = async (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

const defaultAgentDir = (): string => path.join(os.homedir(), ".config", "nomade-agent");

export const defaultRuntimePath = (): string => {
  return path.join(defaultAgentDir(), "runtime.json");
};

export const defaultLogPath = (): string => {
  return path.join(defaultAgentDir(), "agent.log");
};

export interface RuntimeState {
  pid: number;
  startedAt: string;
  configPath: string;
  logPath: string;
  argv: string[];
}

export interface RuntimeInspection {
  running: boolean;
  state: RuntimeState | null;
  staleState: boolean;
}

const isNotFoundError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") {
    return false;
  }
  return (error as NodeJS.ErrnoException).code === "ENOENT";
};

const readRuntimeState = async (runtimePath: string): Promise<RuntimeState | null> => {
  try {
    const raw = await fs.readFile(runtimePath, "utf8");
    const parsed = JSON.parse(raw) as Partial<RuntimeState>;
    const pid = typeof parsed.pid === "number" ? parsed.pid : Number.NaN;
    if (!Number.isInteger(pid) || pid <= 0) {
      return null;
    }
    return {
      pid,
      startedAt: typeof parsed.startedAt === "string" ? parsed.startedAt : new Date().toISOString(),
      configPath: typeof parsed.configPath === "string" ? parsed.configPath : "",
      logPath: typeof parsed.logPath === "string" ? parsed.logPath : "",
      argv: Array.isArray(parsed.argv) ? parsed.argv.map((item) => String(item)) : []
    };
  } catch (error) {
    if (isNotFoundError(error)) {
      return null;
    }
    throw error;
  }
};

const writeRuntimeState = async (runtimePath: string, state: RuntimeState): Promise<void> => {
  await fs.mkdir(path.dirname(runtimePath), { recursive: true, mode: 0o700 });
  await fs.writeFile(runtimePath, JSON.stringify(state, null, 2), { mode: 0o600 });
  await fs.chmod(runtimePath, 0o600);
};

const deleteRuntimeState = async (runtimePath: string): Promise<void> => {
  try {
    await fs.unlink(runtimePath);
  } catch (error) {
    if (!isNotFoundError(error)) {
      throw error;
    }
  }
};

export const isPidRunning = (pid: number): boolean => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "EPERM") {
      return true;
    }
    if (code === "ESRCH") {
      return false;
    }
    throw error;
  }
};

export const inspectRuntime = async (params?: {
  runtimePath?: string;
  cleanupStale?: boolean;
}): Promise<RuntimeInspection> => {
  const runtimePath = params?.runtimePath ?? defaultRuntimePath();
  const state = await readRuntimeState(runtimePath);
  if (!state) {
    return {
      running: false,
      state: null,
      staleState: false
    };
  }
  const running = isPidRunning(state.pid);
  if (running) {
    return {
      running: true,
      state,
      staleState: false
    };
  }
  if (params?.cleanupStale !== false) {
    await deleteRuntimeState(runtimePath);
  }
  return {
    running: false,
    state,
    staleState: true
  };
};

export const readLastLogLines = async (logPath: string, lines = 50): Promise<string[]> => {
  if (lines <= 0) {
    return [];
  }
  try {
    const raw = await fs.readFile(logPath, "utf8");
    return raw
      .split(/\r?\n/)
      .filter((line) => line.length > 0)
      .slice(-lines);
  } catch (error) {
    if (isNotFoundError(error)) {
      return [];
    }
    throw error;
  }
};

const awaitPidExit = async (pid: number, timeoutMs: number): Promise<boolean> => {
  const timeoutAt = Date.now() + Math.max(100, timeoutMs);
  while (Date.now() < timeoutAt) {
    if (!isPidRunning(pid)) {
      return true;
    }
    await sleep(200);
  }
  return !isPidRunning(pid);
};

export const startRuntime = async (params: {
  scriptPath: string;
  runtimePath?: string;
  logPath?: string;
  configPath: string;
  runArgs?: string[];
}): Promise<RuntimeState> => {
  const runtimePath = params.runtimePath ?? defaultRuntimePath();
  const logPath = params.logPath ?? defaultLogPath();
  const runArgs = params.runArgs ?? [];
  const existing = await inspectRuntime({ runtimePath });
  if (existing.running && existing.state) {
    throw new Error(`already_running:${existing.state.pid}`);
  }

  await fs.mkdir(path.dirname(logPath), { recursive: true, mode: 0o700 });
  const logFd = fsSync.openSync(logPath, "a", 0o600);
  const argv = [...process.execArgv, params.scriptPath, "run", ...runArgs];
  const child = spawn(process.execPath, argv, {
    detached: true,
    stdio: ["ignore", logFd, logFd],
    cwd: process.cwd(),
    env: process.env
  });
  child.unref();
  fsSync.closeSync(logFd);

  const pid = child.pid;
  if (!pid || pid <= 0) {
    throw new Error("start_failed:no_pid");
  }

  const state: RuntimeState = {
    pid,
    startedAt: new Date().toISOString(),
    configPath: params.configPath,
    logPath,
    argv
  };
  await writeRuntimeState(runtimePath, state);
  await sleep(400);
  if (!isPidRunning(pid)) {
    await deleteRuntimeState(runtimePath);
    const lines = await readLastLogLines(logPath, 20);
    const details = lines.length > 0 ? lines.join("\n") : "no log output";
    throw new Error(`start_failed:agent_exited_early\n${details}`);
  }
  return state;
};

export interface StopRuntimeResult {
  stopped: boolean;
  forced: boolean;
  state: RuntimeState | null;
  staleState: boolean;
}

export const stopRuntime = async (params?: {
  runtimePath?: string;
  graceMs?: number;
}): Promise<StopRuntimeResult> => {
  const runtimePath = params?.runtimePath ?? defaultRuntimePath();
  const inspection = await inspectRuntime({
    runtimePath,
    cleanupStale: false
  });
  if (!inspection.state) {
    return {
      stopped: false,
      forced: false,
      state: null,
      staleState: false
    };
  }
  if (!inspection.running) {
    await deleteRuntimeState(runtimePath);
    return {
      stopped: false,
      forced: false,
      state: inspection.state,
      staleState: true
    };
  }

  const graceMs = params?.graceMs ?? 8_000;
  try {
    process.kill(inspection.state.pid, "SIGTERM");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ESRCH") {
      throw error;
    }
  }

  const stoppedGracefully = await awaitPidExit(inspection.state.pid, graceMs);
  let forced = false;
  if (!stoppedGracefully) {
    forced = true;
    try {
      process.kill(inspection.state.pid, "SIGKILL");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ESRCH") {
        throw error;
      }
    }
    const stoppedAfterForce = await awaitPidExit(inspection.state.pid, 2_000);
    if (!stoppedAfterForce) {
      throw new Error(`stop_failed:pid_${inspection.state.pid}_still_running`);
    }
  }
  await deleteRuntimeState(runtimePath);
  return {
    stopped: true,
    forced,
    state: inspection.state,
    staleState: false
  };
};

export const removeAgentState = async (params: {
  configPath: string;
  sessionPath: string;
  runtimePath?: string;
  logPath?: string;
}): Promise<void> => {
  const runtimePath = params.runtimePath ?? defaultRuntimePath();
  const logPath = params.logPath ?? defaultLogPath();
  const files = [params.configPath, params.sessionPath, runtimePath, logPath];
  for (const filePath of files) {
    try {
      await fs.unlink(filePath);
    } catch (error) {
      if (!isNotFoundError(error)) {
        throw error;
      }
    }
  }

  const dir = defaultAgentDir();
  try {
    const entries = await fs.readdir(dir);
    if (entries.length === 0) {
      await fs.rmdir(dir);
    }
  } catch (error) {
    if (!isNotFoundError(error)) {
      throw error;
    }
  }
};
