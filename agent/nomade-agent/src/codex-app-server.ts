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

interface ThreadListEntry {
  id: string;
  preview: string;
  cwd: string;
  updatedAt: number;
  name: string | null;
}

interface ThreadListResult {
  data: ThreadListEntry[];
  nextCursor: string | null;
}

interface ThreadReadResult {
  thread: Record<string, unknown>;
}

interface ModelListReasoningEffortEntry {
  reasoningEffort?: unknown;
  description?: unknown;
}

interface ModelListEntry {
  id?: unknown;
  model?: unknown;
  displayName?: unknown;
  description?: unknown;
  isDefault?: unknown;
  hidden?: unknown;
  defaultReasoningEffort?: unknown;
  supportedReasoningEfforts?: unknown;
}

interface ModelListResult {
  data?: unknown;
  nextCursor?: unknown;
}

interface CollaborationModeListResult {
  data?: unknown;
}

interface SkillListResult {
  data?: unknown;
}

interface ConfigReadResult {
  config?: unknown;
}

export interface AppServerNotification {
  method: string;
  params: Record<string, unknown>;
}

export interface AppServerServerRequest {
  requestId: string;
  method: string;
  params: Record<string, unknown>;
}

export interface AppServerServerRequestResolution {
  result?: unknown;
  error?: string;
}

export type CodexApprovalPolicy = "untrusted" | "on-failure" | "on-request" | "never";
export type CodexSandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type CodexReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh";

export interface CodexModelSummary {
  id: string;
  model: string;
  displayName: string;
  description: string;
  isDefault: boolean;
  hidden: boolean;
  defaultReasoningEffort: CodexReasoningEffort;
  supportedReasoningEfforts: Array<{
    reasoningEffort: CodexReasoningEffort;
    description: string;
  }>;
}

export interface CodexCollaborationModeSummary {
  slug: string;
  label: string;
  description: string;
  value: Record<string, unknown>;
}

export interface CodexSkillSummary {
  name: string;
  path: string;
}

const toSandboxPolicy = (sandboxMode?: CodexSandboxMode): Record<string, unknown> | undefined => {
  if (!sandboxMode) {
    return undefined;
  }
  if (sandboxMode === "read-only") {
    return { type: "readOnly" };
  }
  if (sandboxMode === "workspace-write") {
    return { type: "workspaceWrite" };
  }
  return { type: "dangerFullAccess" };
};

export class CodexAppServerClient {
  private child: ChildProcessWithoutNullStreams | null = null;
  private nextRequestId = 1;
  private readonly pending = new Map<number, PendingRequest>();
  private readonly threadStartLock = new Map<string, Promise<string>>();

  constructor(
    private readonly onNotification: (notification: AppServerNotification) => void,
    private readonly onServerRequest?: (
      request: AppServerServerRequest
    ) => Promise<AppServerServerRequestResolution>
  ) {}

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
    approvalPolicy?: CodexApprovalPolicy;
    sandboxMode?: CodexSandboxMode;
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

  async threadStart(params: {
    cwd?: string;
    model?: string;
    approvalPolicy?: CodexApprovalPolicy;
    sandboxMode?: CodexSandboxMode;
  }): Promise<string> {
    const response = (await this.request("thread/start", {
      cwd: params.cwd,
      model: params.model,
      approvalPolicy: params.approvalPolicy ?? "never",
      sandbox: params.sandboxMode,
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
    prompt?: string;
    inputItems?: Array<Record<string, unknown>>;
    collaborationMode?: Record<string, unknown>;
    cwd?: string;
    model?: string;
    approvalPolicy?: CodexApprovalPolicy;
    sandboxMode?: CodexSandboxMode;
    effort?: CodexReasoningEffort;
  }): Promise<string> {
    const inputItems =
      Array.isArray(params.inputItems) && params.inputItems.length > 0
        ? params.inputItems
        : params.prompt
          ? [{ type: "text", text: params.prompt }]
          : [];
    if (inputItems.length === 0) {
      throw new Error("turn_start_missing_input");
    }

    const response = (await this.request("turn/start", {
      threadId: params.threadId,
      input: inputItems,
      collaborationMode: params.collaborationMode,
      cwd: params.cwd,
      model: params.model,
      approvalPolicy: params.approvalPolicy ?? "never",
      sandboxPolicy: toSandboxPolicy(params.sandboxMode),
      effort: params.effort
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

  async threadList(params?: { limit?: number; cursor?: string | null }): Promise<ThreadListResult> {
    const response = (await this.request("thread/list", {
      limit: params?.limit ?? 50,
      cursor: params?.cursor ?? null
    })) as ThreadListResult;

    const data = Array.isArray(response?.data)
      ? response.data
          .filter((entry) => typeof entry?.id === "string")
          .map((entry) => ({
            id: entry.id,
            preview: typeof entry.preview === "string" ? entry.preview : "",
            cwd: typeof entry.cwd === "string" ? entry.cwd : ".",
            updatedAt: typeof entry.updatedAt === "number" ? entry.updatedAt : 0,
            name: typeof entry.name === "string" ? entry.name : null
          }))
      : [];

    return {
      data,
      nextCursor: typeof response?.nextCursor === "string" ? response.nextCursor : null
    };
  }

  async threadRead(params: { threadId: string; includeTurns?: boolean }): Promise<Record<string, unknown>> {
    const response = (await this.request("thread/read", {
      threadId: params.threadId,
      includeTurns: params.includeTurns ?? true
    })) as ThreadReadResult;

    if (!response?.thread || typeof response.thread !== "object") {
      throw new Error("thread_read_missing_thread");
    }
    return response.thread;
  }

  async modelList(params?: {
    limit?: number;
    cursor?: string | null;
    includeHidden?: boolean;
  }): Promise<{ data: CodexModelSummary[]; nextCursor: string | null }> {
    const response = (await this.request("model/list", {
      limit: params?.limit ?? 100,
      cursor: params?.cursor ?? null,
      includeHidden: params?.includeHidden ?? false
    })) as ModelListResult;

    const rawData = Array.isArray(response?.data) ? response.data : [];
    const data = rawData
      .filter((entry) => typeof entry === "object" && entry !== null)
      .map((entry) => {
        const model = entry as ModelListEntry;
        const defaultEffort = this.normalizeReasoningEffort(model.defaultReasoningEffort) ?? "medium";
        const supportedReasoningEfforts = Array.isArray(model.supportedReasoningEfforts)
          ? model.supportedReasoningEfforts
              .filter((effort) => typeof effort === "object" && effort !== null)
              .map((effort) => {
                const value = effort as ModelListReasoningEffortEntry;
                return {
                  reasoningEffort: this.normalizeReasoningEffort(value.reasoningEffort),
                  description: typeof value.description === "string" ? value.description : ""
                };
              })
              .filter(
                (value): value is { reasoningEffort: CodexReasoningEffort; description: string } =>
                  value.reasoningEffort !== undefined
              )
          : [];

        return {
          id: typeof model.id === "string" ? model.id : "",
          model: typeof model.model === "string" ? model.model : "",
          displayName: typeof model.displayName === "string" ? model.displayName : "",
          description: typeof model.description === "string" ? model.description : "",
          isDefault: model.isDefault === true,
          hidden: model.hidden === true,
          defaultReasoningEffort: defaultEffort,
          supportedReasoningEfforts
        };
      })
      .filter((entry) => entry.model.length > 0 && entry.displayName.length > 0);

    return {
      data,
      nextCursor: typeof response?.nextCursor === "string" ? response.nextCursor : null
    };
  }

  async collaborationModeList(params?: { cwd?: string | null }): Promise<CodexCollaborationModeSummary[]> {
    const response = (await this.request("collaborationMode/list", {
      cwd: params?.cwd ?? null
    })) as CollaborationModeListResult;
    const rawModes = Array.isArray(response?.data) ? response.data : [];
    return rawModes
      .filter((entry) => typeof entry === "object" && entry !== null)
      .map((entry) => {
        const value = entry as Record<string, unknown>;
        const rawSlug = typeof value.slug === "string" ? value.slug : "";
        const rawLabel = typeof value.label === "string" ? value.label : rawSlug;
        return {
          slug: rawSlug,
          label: rawLabel,
          description: typeof value.description === "string" ? value.description : "",
          value
        };
      })
      .filter((entry) => entry.slug.length > 0);
  }

  async skillsList(params: { cwd: string }): Promise<CodexSkillSummary[]> {
    const response = (await this.request("skills/list", {
      cwd: params.cwd
    })) as SkillListResult;
    const rawSkills = Array.isArray(response?.data) ? response.data : [];
    return rawSkills
      .filter((entry) => typeof entry === "object" && entry !== null)
      .map((entry) => {
        const value = entry as Record<string, unknown>;
        return {
          name: typeof value.name === "string" ? value.name : "",
          path: typeof value.path === "string" ? value.path : ""
        };
      })
      .filter((entry) => entry.path.length > 0);
  }

  async configRead(params?: { cwd?: string | null }): Promise<Record<string, unknown>> {
    const response = (await this.request("config/read", {
      cwd: params?.cwd ?? null,
      includeLayers: false
    })) as ConfigReadResult;
    if (!response?.config || typeof response.config !== "object") {
      return {};
    }
    return response.config as Record<string, unknown>;
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
      if (!this.onServerRequest) {
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

      void this.onServerRequest({
        requestId: String(idValue),
        method,
        params: (payload.params as Record<string, unknown>) ?? {}
      })
        .then((resolution) => {
          if (resolution.error) {
            this.writeJson({
              jsonrpc: "2.0",
              id: idValue,
              error: {
                code: -32000,
                message: resolution.error
              }
            });
            return;
          }
          this.writeJson({
            jsonrpc: "2.0",
            id: idValue,
            result: resolution.result ?? {}
          });
        })
        .catch((error) => {
          this.writeJson({
            jsonrpc: "2.0",
            id: idValue,
            error: {
              code: -32000,
              message: error instanceof Error ? error.message : "server_request_failed"
            }
          });
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

  private normalizeReasoningEffort(value: unknown): CodexReasoningEffort | undefined {
    if (
      value === "none" ||
      value === "minimal" ||
      value === "low" ||
      value === "medium" ||
      value === "high" ||
      value === "xhigh"
    ) {
      return value;
    }
    return undefined;
  }
}
