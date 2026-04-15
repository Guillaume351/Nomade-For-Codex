import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { inspectRuntime, readLastLogLines, stopRuntime } from "./lifecycle.js";

const tempDirs: string[] = [];

const makeTempDir = async (): Promise<string> => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "nomade-agent-test-"));
  tempDirs.push(dir);
  return dir;
};

afterEach(async () => {
  await Promise.all(
    tempDirs.splice(0).map((dir) =>
      fs.rm(dir, {
        recursive: true,
        force: true
      })
    )
  );
});

describe("inspectRuntime", () => {
  it("detects stale runtime state and cleans file by default", async () => {
    const dir = await makeTempDir();
    const runtimePath = path.join(dir, "runtime.json");
    await fs.writeFile(
      runtimePath,
      JSON.stringify({
        pid: 999_999,
        startedAt: new Date().toISOString(),
        configPath: "/tmp/config.json",
        logPath: "/tmp/agent.log",
        argv: []
      })
    );

    const inspection = await inspectRuntime({ runtimePath });
    expect(inspection.running).toBe(false);
    expect(inspection.staleState).toBe(true);
    await expect(fs.stat(runtimePath)).rejects.toMatchObject({ code: "ENOENT" });
  });
});

describe("stopRuntime", () => {
  it("reports stale state when pid no longer exists", async () => {
    const dir = await makeTempDir();
    const runtimePath = path.join(dir, "runtime.json");
    await fs.writeFile(
      runtimePath,
      JSON.stringify({
        pid: 999_999,
        startedAt: new Date().toISOString(),
        configPath: "/tmp/config.json",
        logPath: "/tmp/agent.log",
        argv: []
      })
    );

    const stopped = await stopRuntime({ runtimePath });
    expect(stopped.staleState).toBe(true);
    expect(stopped.stopped).toBe(false);
    await expect(fs.stat(runtimePath)).rejects.toMatchObject({ code: "ENOENT" });
  });
});

describe("readLastLogLines", () => {
  it("returns tail lines", async () => {
    const dir = await makeTempDir();
    const logPath = path.join(dir, "agent.log");
    await fs.writeFile(logPath, "a\nb\nc\nd\n");

    const lines = await readLastLogLines(logPath, 2);
    expect(lines).toEqual(["c", "d"]);
  });
});
