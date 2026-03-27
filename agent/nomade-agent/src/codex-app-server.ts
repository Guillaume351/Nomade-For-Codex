import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import readline from "node:readline";

interface JsonRpcErrorShape {
  code?: number;
  message?: string;
}

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

interface ThreadStartResult {
  thread: {
    id: string;
  };
}

interface TurnStartResult {
  turn: {
    id: string;
  };
}

export interface AppServerNotification {
  method: string;
  params: Record<string, unknown>;
}

export class CodexAppServerClient {
  private child: ChildProcessWithoutNullStreams | null = null;
  private nextRequestId = 1;
  private readonly pending = new Map<number, PendingRequest>();
  private readonly threadStartLock = new Map<string, Promise<string>>();

  constructor(private readonly onNotification: (notification: AppServerNotification) => void) {}

  async start(): Promise<void> {
    if (this.child) {
      return;
    }

    const child = spawn("codex", ["app-server", "--listen", "stdio://"], {
      stdio: "pipe",
      env: process.env
    });
    this.child = child;

    const lineReader = readline.createInterface({ input: child.stdout });
    lineReader.on("line", (line) => this.handleLine(line));

    child.stderr.on("data", (chunk: Buffer) => {
      const value = chunk.toString("utf8").trim();
      if (value) {
        console.error("[agent] codex app-server stderr:", value);
      }
    });

    child.on("exit", (code, signal) => {
      const reason = `codex app-server exited (code=${code ?? "null"} signal=${signal ?? "null"})`;
      const error = new Error(reason);
      for (const [id, pending] of this.pending.entries()) {
        clearTimeout(pending.timeout);
        pending.reject(error);
        this.pending.delete(id);
      }
      this.threadStartLock.clear();
      this.child = null;
    });

    await this.request("initialize", {
      clientInfo: {
        name: "nomade-agent",
        version: "0.1.0"
      }
    });
  }

  async ensureThread(params: {
    conversationId: string;
    cwd?: string;
    model?: string;
  }): Promise<string> {
    const existing = this.threadStartLock.get(params.conversationId);
    if (existing) {
      return existing;
    }

    const pending = this.threadStart(params);
    this.threadStartLock.set(params.conversationId, pending);
    try {
      return await pending;
    } finally {
      this.threadStartLock.delete(params.conversationId);
    }
  }

  async threadStart(params: { cwd?: string; model?: string }): Promise<string> {
    const response = (await this.request("thread/start", {
      cwd: params.cwd,
      model: params.model,
      approvalPolicy: "never",
      ephemeral: true
    })) as ThreadStartResult;

    const threadId = response?.thread?.id;
    if (!threadId) {
      throw new Error("thread_start_missing_id");
    }
    return threadId;
  }

  async turnStart(params: {
    threadId: string;
    prompt: string;
    cwd?: string;
    model?: string;
  }): Promise<string> {
    const response = (await this.request("turn/start", {
      threadId: params.threadId,
      input: [{ type: "text", text: params.prompt }],
      cwd: params.cwd,
      model: params.model,
      approvalPolicy: "never"
    })) as TurnStartResult;

    const turnId = response?.turn?.id;
    if (!turnId) {
      throw new Error("turn_start_missing_id");
    }
    return turnId;
  }

  async turnInterrupt(params: { threadId: string; turnId: string }): Promise<void> {
    await this.request("turn/interrupt", {
      threadId: params.threadId,
      turnId: params.turnId
    });
  }

  close(): void {
    if (!this.child) {
      return;
    }
    this.child.kill("SIGTERM");
    this.child = null;
  }

  private handleLine(line: string): void {
    const trimmed = line.trim();
    if (!trimmed) {
      return;
    }

    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(trimmed) as Record<string, unknown>;
    } catch {
      return;
    }

    const idValue = payload.id;
    const method = payload.method;

    if (typeof idValue === "number" && Object.hasOwn(payload, "result")) {
      this.resolvePending(idValue, payload.result);
      return;
    }

    if (typeof idValue === "number" && Object.hasOwn(payload, "error")) {
      const error = payload.error as JsonRpcErrorShape | undefined;
      this.rejectPending(idValue, new Error(error?.message ?? "jsonrpc_error"));
      return;
    }

    if (typeof idValue === "number" && typeof method === "string") {
      // This is a server-initiated request; we currently don't support it.
      this.writeJson({
        jsonrpc: "2.0",
        id: idValue,
        error: {
          code: -32601,
          message: `Unsupported method: ${method}`
        }
      });
      return;
    }

    if (typeof method === "string") {
      this.onNotification({
        method,
        params: (payload.params as Record<string, unknown>) ?? {}
      });
    }
  }

  private resolvePending(id: number, result: unknown): void {
    const pending = this.pending.get(id);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timeout);
    this.pending.delete(id);
    pending.resolve(result);
  }

  private rejectPending(id: number, error: Error): void {
    const pending = this.pending.get(id);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timeout);
    this.pending.delete(id);
    pending.reject(error);
  }

  private async request(method: string, params: Record<string, unknown>): Promise<unknown> {
    if (!this.child) {
      throw new Error("codex_app_server_not_started");
    }

    const id = this.nextRequestId++;
    const payload = {
      jsonrpc: "2.0",
      id,
      method,
      params
    };

    return new Promise<unknown>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`jsonrpc_timeout:${method}`));
      }, 30_000);

      this.pending.set(id, { resolve, reject, timeout });
      this.writeJson(payload);
    });
  }

  private writeJson(value: unknown): void {
    if (!this.child) {
      return;
    }
    this.child.stdin.write(`${JSON.stringify(value)}\n`);
  }
}
