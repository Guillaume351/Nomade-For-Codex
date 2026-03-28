import {
  CodexAppServerClient,
  type AppServerNotification,
  type CodexApprovalPolicy,
  type CodexModelSummary,
  type CodexReasoningEffort,
  type CodexSandboxMode
} from "./codex-app-server.js";

interface ConversationTurnStartParams {
  conversationId: string;
  turnId: string;
  threadId?: string;
  prompt: string;
  model?: string;
  cwd?: string;
  approvalPolicy?: CodexApprovalPolicy;
  sandboxMode?: CodexSandboxMode;
  effort?: CodexReasoningEffort;
}

interface ConversationTurnInterruptParams {
  conversationId: string;
  turnId: string;
}

interface TurnContext {
  conversationId: string;
  turnId: string;
}

export interface CodexThreadSummary {
  threadId: string;
  title: string;
  preview: string;
  cwd: string;
  updatedAt: number;
}

export interface CodexThreadItemSummary {
  itemId: string;
  itemType: string;
  payload: Record<string, unknown>;
}

export interface CodexThreadTurnSummary {
  turnId: string;
  status: "running" | "completed" | "interrupted" | "failed";
  error?: string;
  userPrompt: string;
  items: CodexThreadItemSummary[];
}

export interface CodexThreadReadSummary {
  threadId: string;
  title: string;
  preview: string;
  cwd: string;
  updatedAt: number;
  turns: CodexThreadTurnSummary[];
}

export interface CodexRuntimeOptions {
  models: CodexModelSummary[];
  approvalPolicies: CodexApprovalPolicy[];
  sandboxModes: CodexSandboxMode[];
  reasoningEfforts: CodexReasoningEffort[];
  defaults: {
    model?: string;
    approvalPolicy?: CodexApprovalPolicy;
    sandboxMode?: CodexSandboxMode;
    effort?: CodexReasoningEffort;
  };
}

const codexApprovalPolicies: CodexApprovalPolicy[] = ["untrusted", "on-failure", "on-request", "never"];
const codexSandboxModes: CodexSandboxMode[] = ["read-only", "workspace-write", "danger-full-access"];
const codexReasoningEfforts: CodexReasoningEffort[] = ["none", "minimal", "low", "medium", "high", "xhigh"];

const buildTurnKey = (threadId: string, codexTurnId: string): string => `${threadId}:${codexTurnId}`;

export class ConversationManager {
  private readonly codexClient: CodexAppServerClient;
  private readonly threadByConversation = new Map<string, string>();
  private readonly turnByCodex = new Map<string, TurnContext>();
  private readonly codexByTurn = new Map<string, { threadId: string; codexTurnId: string }>();
  private readonly pendingTurnByThread = new Map<string, TurnContext>();

  constructor(private readonly emit: (payload: Record<string, unknown>) => void) {
    this.codexClient = new CodexAppServerClient((notification) => this.onNotification(notification));
  }

  async startTurn(params: ConversationTurnStartParams): Promise<void> {
    let currentThreadId = params.threadId ?? this.threadByConversation.get(params.conversationId) ?? "";
    try {
      await this.codexClient.start();

      if (!currentThreadId) {
        currentThreadId = await this.codexClient.ensureThread({
          conversationId: params.conversationId,
          cwd: params.cwd,
          model: params.model,
          approvalPolicy: params.approvalPolicy,
          sandboxMode: params.sandboxMode
        });
        this.threadByConversation.set(params.conversationId, currentThreadId);
        this.emit({
          type: "conversation.thread.started",
          conversationId: params.conversationId,
          threadId: currentThreadId
        });
      } else {
        this.threadByConversation.set(params.conversationId, currentThreadId);
      }

      const runTurnStart = async (threadId: string): Promise<string> => {
        this.pendingTurnByThread.set(threadId, {
          conversationId: params.conversationId,
          turnId: params.turnId
        });
        try {
          return await this.codexClient.turnStart({
            threadId,
            prompt: params.prompt,
            cwd: params.cwd,
            model: params.model,
            approvalPolicy: params.approvalPolicy,
            sandboxMode: params.sandboxMode,
            effort: params.effort
          });
        } catch (error) {
          this.pendingTurnByThread.delete(threadId);
          throw error;
        }
      };

      let codexTurnId: string;
      try {
        codexTurnId = await runTurnStart(currentThreadId);
      } catch (error) {
        if (!this.isThreadNotFoundError(error)) {
          throw error;
        }

        this.pendingTurnByThread.delete(currentThreadId);
        this.threadByConversation.delete(params.conversationId);

        currentThreadId = await this.codexClient.ensureThread({
          conversationId: params.conversationId,
          cwd: params.cwd,
          model: params.model,
          approvalPolicy: params.approvalPolicy,
          sandboxMode: params.sandboxMode
        });
        this.threadByConversation.set(params.conversationId, currentThreadId);
        this.emit({
          type: "conversation.thread.started",
          conversationId: params.conversationId,
          threadId: currentThreadId
        });

        codexTurnId = await runTurnStart(currentThreadId);
      }

      this.bindTurn(currentThreadId, codexTurnId, {
        conversationId: params.conversationId,
        turnId: params.turnId
      });

      this.emit({
        type: "conversation.turn.started",
        conversationId: params.conversationId,
        turnId: params.turnId,
        threadId: currentThreadId,
        codexTurnId
      });
    } catch (error) {
      this.emit({
        type: "conversation.turn.completed",
        conversationId: params.conversationId,
        turnId: params.turnId,
        threadId: currentThreadId,
        codexTurnId: "",
        status: "failed",
        error: error instanceof Error ? error.message : "turn_start_failed"
      });
    }
  }

  async interruptTurn(params: ConversationTurnInterruptParams): Promise<void> {
    const mapping = this.codexByTurn.get(params.turnId);
    if (!mapping) {
      return;
    }
    await this.codexClient.turnInterrupt({
      threadId: mapping.threadId,
      turnId: mapping.codexTurnId
    });
  }

  async listThreads(params?: { limit?: number }): Promise<CodexThreadSummary[]> {
    await this.codexClient.start();

    const target = Math.max(1, Math.min(params?.limit ?? 200, 1000));
    const collected: CodexThreadSummary[] = [];
    let cursor: string | null = null;

    while (collected.length < target) {
      const page = await this.codexClient.threadList({
        limit: Math.min(100, target - collected.length),
        cursor
      });

      for (const thread of page.data) {
        const preview = thread.preview.trim();
        const fallbackTitle = preview.split("\n").find((line) => line.trim().length > 0)?.trim() ?? "Codex thread";
        const rawName = thread.name?.trim() ?? "";
        const title = rawName.length > 0 ? rawName : fallbackTitle;

        collected.push({
          threadId: thread.id,
          title: title.length > 240 ? `${title.substring(0, 240)}...` : title,
          preview,
          cwd: thread.cwd || ".",
          updatedAt: thread.updatedAt
        });
      }

      if (!page.nextCursor || page.data.length === 0) {
        break;
      }
      cursor = page.nextCursor;
    }

    return collected;
  }

  async readThread(params: { threadId: string }): Promise<CodexThreadReadSummary> {
    await this.codexClient.start();
    const thread = await this.codexClient.threadRead({
      threadId: params.threadId,
      includeTurns: true
    });

    const preview = typeof thread.preview === "string" ? thread.preview.trim() : "";
    const rawName = typeof thread.name === "string" ? thread.name.trim() : "";
    const fallbackTitle = preview.split("\n").find((line) => line.trim().length > 0)?.trim() ?? "Codex thread";
    const turnsRaw = Array.isArray(thread.turns) ? thread.turns : [];

    const turns: CodexThreadTurnSummary[] = turnsRaw
      .filter((entry) => typeof entry === "object" && entry !== null)
      .map((entry, index) => {
        const turn = entry as Record<string, unknown>;
        const rawStatus = String(turn.status ?? "failed");
        const status =
          rawStatus === "completed" || rawStatus === "interrupted" || rawStatus === "failed" ? rawStatus : "running";

        const rawError = turn.error as Record<string, unknown> | null | undefined;
        const errorMessage = typeof rawError?.message === "string" ? rawError.message : undefined;
        const itemsRaw = Array.isArray(turn.items) ? turn.items : [];
        const items = itemsRaw
          .filter((item) => typeof item === "object" && item !== null)
          .map((item, itemIndex) => {
            const payload = (item as Record<string, unknown>) ?? {};
            const itemId = typeof payload.id === "string" ? payload.id : `item-${itemIndex + 1}`;
            const itemType = typeof payload.type === "string" ? payload.type : "unknown";
            return {
              itemId,
              itemType,
              payload
            };
          });

        const userItem = items.find((item) => item.itemType == "userMessage");
        const userPrompt = this.extractUserPrompt(userItem?.payload);

        return {
          turnId: typeof turn.id === "string" ? turn.id : `turn-${index + 1}`,
          status,
          error: errorMessage,
          userPrompt,
          items
        };
      });

    return {
      threadId: typeof thread.id === "string" ? thread.id : params.threadId,
      title: rawName.length > 0 ? rawName : fallbackTitle,
      preview,
      cwd: typeof thread.cwd === "string" && thread.cwd.length > 0 ? thread.cwd : ".",
      updatedAt: typeof thread.updatedAt === "number" ? thread.updatedAt : 0,
      turns
    };
  }

  async getRuntimeOptions(params?: { cwd?: string }): Promise<CodexRuntimeOptions> {
    await this.codexClient.start();

    const [modelPage, config] = await Promise.all([
      this.codexClient.modelList({
        limit: 200,
        includeHidden: false
      }),
      this.codexClient.configRead({ cwd: params?.cwd ?? null })
    ]);

    const approvalRaw = config.approval_policy;
    const sandboxRaw = config.sandbox_mode;
    const effortRaw = config.model_reasoning_effort;
    const modelRaw = config.model;

    const defaults: CodexRuntimeOptions["defaults"] = {};
    if (typeof modelRaw === "string" && modelRaw.trim().length > 0) {
      defaults.model = modelRaw.trim();
    }
    if (this.isApprovalPolicy(approvalRaw)) {
      defaults.approvalPolicy = approvalRaw;
    }
    if (this.isSandboxMode(sandboxRaw)) {
      defaults.sandboxMode = sandboxRaw;
    }
    if (this.isReasoningEffort(effortRaw)) {
      defaults.effort = effortRaw;
    }

    return {
      models: modelPage.data,
      approvalPolicies: codexApprovalPolicies,
      sandboxModes: codexSandboxModes,
      reasoningEfforts: codexReasoningEfforts,
      defaults
    };
  }

  close(): void {
    this.codexClient.close();
  }

  private onNotification(notification: AppServerNotification): void {
    const method = notification.method;
    const params = notification.params;
    const threadId = typeof params.threadId === "string" ? params.threadId : "";
    const codexTurnId = this.extractTurnId(method, params);
    const context = threadId && codexTurnId ? this.turnByCodex.get(buildTurnKey(threadId, codexTurnId)) : undefined;

    if (method === "thread/started") {
      const thread = (params.thread as Record<string, unknown>) ?? {};
      const createdThreadId = String(thread.id ?? "");
      if (!createdThreadId) {
        return;
      }

      const pending = this.pendingTurnByThread.get(createdThreadId);
      if (!pending) {
        return;
      }

      this.threadByConversation.set(pending.conversationId, createdThreadId);
      this.emit({
        type: "conversation.thread.started",
        conversationId: pending.conversationId,
        threadId: createdThreadId
      });
      return;
    }

    if (method === "turn/started" && threadId && codexTurnId) {
      const pending = this.pendingTurnByThread.get(threadId);
      if (!pending) {
        return;
      }
      this.bindTurn(threadId, codexTurnId, pending);
      this.emit({
        type: "conversation.turn.started",
        conversationId: pending.conversationId,
        turnId: pending.turnId,
        threadId,
        codexTurnId
      });
      return;
    }

    if (!context || !threadId || !codexTurnId) {
      return;
    }

    if (method === "turn/diff/updated") {
      this.emit({
        type: "conversation.turn.diff.updated",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId,
        diff: String(params.diff ?? "")
      });
      return;
    }

    if (method === "item/completed") {
      const item = (params.item as Record<string, unknown>) ?? {};
      const itemId = String(item.id ?? params.itemId ?? "");
      const itemType = String(item.type ?? "unknown");
      if (!itemId) {
        return;
      }
      this.emit({
        type: "conversation.item.completed",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId,
        itemId,
        itemType,
        item
      });
      return;
    }

    if (
      method === "item/agentMessage/delta" ||
      method === "item/commandExecution/outputDelta" ||
      method === "item/fileChange/outputDelta" ||
      method === "item/reasoning/textDelta" ||
      method === "item/reasoning/summaryTextDelta" ||
      method === "item/plan/delta"
    ) {
      const itemId = String(params.itemId ?? "");
      const delta = String(params.delta ?? "");
      if (!itemId || !delta) {
        return;
      }
      const stream =
        method === "item/agentMessage/delta"
          ? "agentMessage"
          : method === "item/commandExecution/outputDelta"
            ? "commandExecution"
            : method === "item/fileChange/outputDelta"
              ? "fileChange"
              : method === "item/plan/delta"
                ? "plan"
                : "reasoning";

      this.emit({
        type: "conversation.item.delta",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId,
        itemId,
        stream,
        delta
      });
      return;
    }

    if (method === "turn/completed") {
      const turn = (params.turn as Record<string, unknown>) ?? {};
      const rawStatus = String(turn.status ?? "failed");
      const status =
        rawStatus === "completed" ? "completed" : rawStatus === "interrupted" ? "interrupted" : "failed";
      const errorValue = turn.error as Record<string, unknown> | undefined;
      const errorMessage =
        typeof errorValue?.message === "string" ? errorValue.message : status === "failed" ? "turn_failed" : undefined;

      this.emit({
        type: "conversation.turn.completed",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId,
        status,
        error: errorMessage
      });
      this.pendingTurnByThread.delete(threadId);
      return;
    }
  }

  private bindTurn(threadId: string, codexTurnId: string, context: TurnContext): void {
    this.pendingTurnByThread.delete(threadId);
    this.turnByCodex.set(buildTurnKey(threadId, codexTurnId), context);
    this.codexByTurn.set(context.turnId, { threadId, codexTurnId });
  }

  private extractTurnId(method: string, params: Record<string, unknown>): string {
    if (method === "turn/started" || method === "turn/completed") {
      const turn = (params.turn as Record<string, unknown>) ?? {};
      return String(turn.id ?? "");
    }
    return String(params.turnId ?? "");
  }

  private extractUserPrompt(payload?: Record<string, unknown>): string {
    if (!payload) {
      return "";
    }
    const content = payload.content;
    if (!Array.isArray(content)) {
      return "";
    }
    const parts: string[] = [];
    for (const item of content) {
      if (!item || typeof item !== "object") {
        continue;
      }
      const entry = item as Record<string, unknown>;
      const text = entry.text;
      if (typeof text === "string" && text.trim().length > 0) {
        parts.push(text.trim());
      }
    }
    return parts.join("\n\n");
  }

  private isApprovalPolicy(value: unknown): value is CodexApprovalPolicy {
    return value === "untrusted" || value === "on-failure" || value === "on-request" || value === "never";
  }

  private isSandboxMode(value: unknown): value is CodexSandboxMode {
    return value === "read-only" || value === "workspace-write" || value === "danger-full-access";
  }

  private isReasoningEffort(value: unknown): value is CodexReasoningEffort {
    return value === "none" || value === "minimal" || value === "low" || value === "medium" || value === "high" || value === "xhigh";
  }

  private isThreadNotFoundError(error: unknown): boolean {
    if (!(error instanceof Error)) {
      return false;
    }
    return /thread[\s_-]*not[\s_-]*found/i.test(error.message);
  }
}
