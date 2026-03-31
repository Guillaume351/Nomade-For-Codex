import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

interface SessionRuntime {
  process: ChildProcessWithoutNullStreams;
  cursor: number;
}

export interface SessionCallbacks {
  onOutput: (sessionId: string, stream: "stdout" | "stderr", data: string, cursor: number) => void;
  onStatus: (sessionId: string, status: "running" | "exited" | "failed", exitCode?: number) => void;
}

export class SessionManager {
  private readonly sessions = new Map<string, SessionRuntime>();

  constructor(private readonly callbacks: SessionCallbacks) {}

  createSession(params: { sessionId: string; command: string; cwd?: string; env?: Record<string, string> }): void {
    if (this.sessions.has(params.sessionId)) {
      return;
    }

    const shell = process.env.SHELL ?? "/bin/bash";
    const child = spawn(shell, ["-lc", params.command], {
      cwd: params.cwd,
      stdio: "pipe",
      env: {
        ...process.env,
        ...(params.env ?? {})
      }
    });

    this.sessions.set(params.sessionId, { process: child, cursor: 0 });
    this.callbacks.onStatus(params.sessionId, "running");

    child.stdout.on("data", (chunk: Buffer) => {
      const runtime = this.sessions.get(params.sessionId);
      if (!runtime) {
        return;
      }
      runtime.cursor += chunk.length;
      this.callbacks.onOutput(params.sessionId, "stdout", chunk.toString("utf8"), runtime.cursor);
    });

    child.stderr.on("data", (chunk: Buffer) => {
      const runtime = this.sessions.get(params.sessionId);
      if (!runtime) {
        return;
      }
      runtime.cursor += chunk.length;
      this.callbacks.onOutput(params.sessionId, "stderr", chunk.toString("utf8"), runtime.cursor);
    });

    child.on("close", (code) => {
      this.sessions.delete(params.sessionId);
      this.callbacks.onStatus(params.sessionId, "exited", code ?? 0);
    });

    child.on("error", () => {
      this.sessions.delete(params.sessionId);
      this.callbacks.onStatus(params.sessionId, "failed");
    });
  }

  input(sessionId: string, data: string): void {
    const runtime = this.sessions.get(sessionId);
    if (!runtime) {
      return;
    }
    runtime.process.stdin.write(data);
  }

  terminate(sessionId: string): void {
    const runtime = this.sessions.get(sessionId);
    if (!runtime) {
      return;
    }
    runtime.process.kill("SIGTERM");
    this.sessions.delete(sessionId);
  }
}
