import fs from "node:fs";
import { spawn, type ChildProcess } from "node:child_process";
import type { KeepAwakeMode } from "./config.js";

type KeepAwakeCapability = "none" | "macos_caffeinate" | "linux_systemd_inhibit";

interface KeepAwakeDetection {
  capability: KeepAwakeCapability;
  reason?: string;
}

const fileContainsMicrosoftMarker = (filePath: string): boolean => {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    return content.toLowerCase().includes("microsoft");
  } catch {
    return false;
  }
};

const isWslRuntime = (): boolean => {
  if (process.platform !== "linux") {
    return false;
  }
  if (process.env.WSL_DISTRO_NAME || process.env.WSL_INTEROP) {
    return true;
  }
  return fileContainsMicrosoftMarker("/proc/version") || fileContainsMicrosoftMarker("/proc/sys/kernel/osrelease");
};

const commandExists = (command: string): boolean => {
  const pathValue = process.env.PATH ?? "";
  if (!pathValue) {
    return false;
  }
  for (const segment of pathValue.split(":")) {
    if (!segment) {
      continue;
    }
    const candidate = `${segment}/${command}`;
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {
      // no-op
    }
  }
  return false;
};

const detectCapability = (): KeepAwakeDetection => {
  if (process.platform === "darwin") {
    if (commandExists("caffeinate")) {
      return { capability: "macos_caffeinate" };
    }
    return { capability: "none", reason: "caffeinate_not_found" };
  }

  if (process.platform === "linux") {
    if (isWslRuntime()) {
      return {
        capability: "none",
        reason: "wsl_sleep_control_not_supported"
      };
    }
    if (commandExists("systemd-inhibit")) {
      return { capability: "linux_systemd_inhibit" };
    }
    return { capability: "none", reason: "systemd_inhibit_not_found" };
  }

  return {
    capability: "none",
    reason: `unsupported_platform_${process.platform}`
  };
};

export class KeepAwakeManager {
  private readonly detection: KeepAwakeDetection;
  private inhibitorProcess: ChildProcess | null = null;

  constructor(private readonly mode: KeepAwakeMode) {
    this.detection = detectCapability();
  }

  describe(): string {
    if (this.mode === "never") {
      return "disabled";
    }
    if (this.detection.capability === "none") {
      return `active_requested_but_unavailable:${this.detection.reason ?? "unknown"}`;
    }
    return this.detection.capability;
  }

  setActive(active: boolean): void {
    if (this.mode !== "active") {
      return;
    }
    if (active) {
      this.ensureInhibitor();
      return;
    }
    this.stopInhibitor();
  }

  close(): void {
    this.stopInhibitor();
  }

  private ensureInhibitor(): void {
    if (this.inhibitorProcess || this.detection.capability === "none") {
      return;
    }

    try {
      if (this.detection.capability === "macos_caffeinate") {
        const child = spawn("caffeinate", ["-dimsu"], {
          stdio: "ignore"
        });
        child.unref();
        this.attachChild(child);
        return;
      }

      if (this.detection.capability === "linux_systemd_inhibit") {
        const child = spawn(
          "systemd-inhibit",
          [
            "--what=sleep",
            "--why=nomade-agent-active-work",
            "--mode=block",
            "sh",
            "-c",
            "while true; do sleep 3600; done"
          ],
          {
            stdio: "ignore"
          }
        );
        child.unref();
        this.attachChild(child);
      }
    } catch (error) {
      console.warn("[agent] keep-awake inhibitor failed to start", error);
      this.inhibitorProcess = null;
    }
  }

  private attachChild(child: ChildProcess): void {
    this.inhibitorProcess = child;
    const currentPid = child.pid;
    child.on("exit", () => {
      if (this.inhibitorProcess?.pid === currentPid) {
        this.inhibitorProcess = null;
      }
    });
    child.on("error", (error) => {
      if (this.inhibitorProcess?.pid === currentPid) {
        this.inhibitorProcess = null;
      }
      console.warn("[agent] keep-awake inhibitor errored", error);
    });
  }

  private stopInhibitor(): void {
    const child = this.inhibitorProcess;
    this.inhibitorProcess = null;
    if (!child) {
      return;
    }
    try {
      child.kill("SIGTERM");
    } catch {
      // no-op
    }
  }
}
