import {
  CodexAppServerClient,
  type AppServerNotification,
  type AppServerServerRequest,
  type AppServerServerRequestResolution,
  type CodexApprovalPolicy,
  type CodexCollaborationModeSummary,
  type CodexModelSummary,
  type CodexReasoningEffort,
  type CodexSandboxMode,
  type CodexSkillSummary
} from "./codex-app-server.js";

interface ConversationTurnStartParams {
  conversationId: string;
  turnId: string;
  threadId?: string;
  prompt?: string;
  inputItems?: Array<Record<string, unknown>>;
  collaborationMode?: Record<string, unknown>;
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

interface PendingServerRequest {
  resolve: (value: AppServerServerRequestResolution) => void;
  reject: (error: Error) => void;
  context: TurnContext;
  threadId: string;
  codexTurnId: string;
}

interface ConversationThreadBinding {
  conversationId: string;
  threadId: string;
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
  collaborationModes: CodexCollaborationModeSummary[];
  skills: CodexSkillSummary[];
  rateLimits?: Record<string, unknown>;
  rateLimitsByLimitId?: Record<string, Record<string, unknown>> | null;
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
  private readonly pendingServerRequests = new Map<string, PendingServerRequest>();

  constructor(private readonly emit: (payload: Record<string, unknown>) => void) {
    this.codexClient = new CodexAppServerClient(
      (notification) => this.onNotification(notification),
      (request) => this.onServerRequest(request)
    );
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
            inputItems: params.inputItems,
            collaborationMode: params.collaborationMode,
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

  resolveServerRequest(params: {
    requestId: string;
    result?: unknown;
    error?: string;
  }): boolean {
    const pending = this.pendingServerRequests.get(params.requestId);
    if (!pending) {
      return false;
    }
    this.pendingServerRequests.delete(params.requestId);
    const resultRecord =
      params.result && typeof params.result === "object"
        ? (params.result as Record<string, unknown>)
        : undefined;
    const rawStatus = String(resultRecord?.status ?? resultRecord?.decision ?? "completed").toLowerCase();
    const status = params.error
      ? "failed"
      : rawStatus === "declined"
        ? "declined"
        : rawStatus === "failed"
          ? "failed"
          : "completed";
    this.emit({
      type: "conversation.server.request.resolved",
      conversationId: pending.context.conversationId,
      turnId: pending.context.turnId,
      threadId: pending.threadId,
      codexTurnId: pending.codexTurnId,
      requestId: params.requestId,
      resolvedAt: new Date().toISOString(),
      status,
      result: params.result,
      error: params.error
    });
    if (params.error && params.error.trim().length > 0) {
      pending.resolve({ error: params.error });
      return true;
    }
    pending.resolve({ result: params.result ?? {} });
    return true;
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

    const [modelPage, config, collaborationModes, skills, rateLimitSnapshot] = await Promise.all([
      this.codexClient.modelList({
        limit: 200,
        includeHidden: false
      }),
      this.codexClient.configRead({ cwd: params?.cwd ?? null }),
      this.codexClient.collaborationModeList({ cwd: params?.cwd ?? null }).catch(() => []),
      params?.cwd ? this.codexClient.skillsList({ cwd: params.cwd }).catch(() => []) : Promise.resolve([]),
      this.codexClient.accountRateLimitsRead().catch(() => null)
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
      collaborationModes,
      skills,
      rateLimits: rateLimitSnapshot?.rateLimits,
      rateLimitsByLimitId: rateLimitSnapshot?.rateLimitsByLimitId ?? null,
      defaults
    };
  }

  async syncThreads(params: { bindings: ConversationThreadBinding[] }): Promise<void> {
    await this.codexClient.start();

    const normalizedBindings: ConversationThreadBinding[] = [];
    const desiredThreadIds = new Set<string>();
    const desiredConversationIds = new Set<string>();

    for (const binding of params.bindings) {
      const conversationId = binding.conversationId.trim();
      const threadId = binding.threadId.trim();
      if (!conversationId || !threadId) {
        continue;
      }
      if (desiredThreadIds.has(threadId) || desiredConversationIds.has(conversationId)) {
        continue;
      }
      desiredThreadIds.add(threadId);
      desiredConversationIds.add(conversationId);
      normalizedBindings.push({ conversationId, threadId });
    }

    const staleConversationIds: string[] = [];
    for (const conversationId of this.threadByConversation.keys()) {
      if (!desiredConversationIds.has(conversationId)) {
        staleConversationIds.push(conversationId);
      }
    }
    for (const conversationId of staleConversationIds) {
      this.threadByConversation.delete(conversationId);
    }
    for (const binding of normalizedBindings) {
      this.threadByConversation.set(binding.conversationId, binding.threadId);
    }

    const loadedThreadIds = new Set<string>();
    let cursor: string | null = null;
    do {
      const page = await this.codexClient.threadLoadedList({
        limit: 200,
        cursor
      });
      for (const threadId of page.data) {
        loadedThreadIds.add(threadId);
      }
      cursor = page.nextCursor;
    } while (cursor);

    const unsubscribeOps: Promise<unknown>[] = [];
    for (const loadedThreadId of loadedThreadIds) {
      if (desiredThreadIds.has(loadedThreadId)) {
        continue;
      }
      unsubscribeOps.push(
        this.codexClient.threadUnsubscribe({ threadId: loadedThreadId }).catch(() => undefined)
      );
    }
    if (unsubscribeOps.length > 0) {
      await Promise.all(unsubscribeOps);
    }

    for (const binding of normalizedBindings) {
      try {
        await this.codexClient.threadResume({ threadId: binding.threadId });
      } catch {
        // Keep the binding in memory; the server remains source of truth and can refresh it on the next sync cycle.
      }
    }
  }

  close(): void {
    for (const [requestId, pending] of this.pendingServerRequests.entries()) {
      pending.reject(new Error(`server_request_cancelled:${requestId}`));
    }
    this.pendingServerRequests.clear();
    this.codexClient.close();
  }

  private onServerRequest(request: AppServerServerRequest): Promise<AppServerServerRequestResolution> {
    const threadId = typeof request.params.threadId === "string" ? request.params.threadId : "";
    const requestTurnId = typeof request.params.turnId === "string" ? request.params.turnId : "";
    let inferredThreadId = "";

    let context: TurnContext | undefined;
    if (threadId && requestTurnId) {
      context = this.turnByCodex.get(buildTurnKey(threadId, requestTurnId));
    }
    if (!context && threadId) {
      context = this.pendingTurnByThread.get(threadId);
    }
    if (!context && requestTurnId) {
      for (const [key, turnContext] of this.turnByCodex.entries()) {
        const separator = key.indexOf(":");
        if (separator <= 0) {
          continue;
        }
        const candidateThreadId = key.substring(0, separator);
        const candidateTurnId = key.substring(separator + 1);
        if (candidateTurnId === requestTurnId) {
          context = turnContext;
          inferredThreadId = candidateThreadId;
          break;
        }
      }
    }

    if (!context || context.conversationId.length === 0) {
      return Promise.resolve({ error: "server_request_missing_turn_context" });
    }

    const mapping = this.codexByTurn.get(context.turnId);
    const resolvedThreadId = threadId || mapping?.threadId || inferredThreadId;
    const resolvedCodexTurnId = requestTurnId || mapping?.codexTurnId || "";
    if (!resolvedThreadId || !resolvedCodexTurnId) {
      return Promise.resolve({ error: "server_request_missing_runtime_context" });
    }

    const existing = this.pendingServerRequests.get(request.requestId);
    if (existing) {
      existing.reject(new Error(`server_request_replaced:${request.requestId}`));
      this.pendingServerRequests.delete(request.requestId);
    }

    this.emit({
      type: "conversation.server.request",
      conversationId: context.conversationId,
      turnId: context.turnId,
      threadId: resolvedThreadId,
      codexTurnId: resolvedCodexTurnId,
      requestId: request.requestId,
      method: request.method,
      params: request.params
    });

    return new Promise<AppServerServerRequestResolution>((resolve, reject) => {
      this.pendingServerRequests.set(request.requestId, {
        resolve,
        reject,
        context,
        threadId: resolvedThreadId,
        codexTurnId: resolvedCodexTurnId
      });
    });
  }

  private onNotification(notification: AppServerNotification): void {
    const method = notification.method;
    const params = notification.params;

    if (method === "account/rateLimits/updated") {
      const rateLimits =
        params.rateLimits && typeof params.rateLimits === "object"
          ? (params.rateLimits as Record<string, unknown>)
          : {};
      this.emit({
        type: "account.rate_limits.updated",
        rateLimits
      });
      return;
    }

    const threadId = typeof params.threadId === "string" ? params.threadId : "";
    const codexTurnId = this.extractTurnId(method, params);
    let context = threadId && codexTurnId ? this.turnByCodex.get(buildTurnKey(threadId, codexTurnId)) : undefined;
    if (!context && threadId) {
      context = this.pendingTurnByThread.get(threadId);
    }
    const mappedCodex = context ? this.codexByTurn.get(context.turnId) : undefined;
    const effectiveCodexTurnId = codexTurnId || mappedCodex?.codexTurnId || "";

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

    const fallbackConversationId = threadId ? this.findConversationIdByThread(threadId) : "";
    const eventConversationId = context?.conversationId ?? fallbackConversationId;
    const eventTurnId = context?.turnId ?? "";

    if (method === "thread/status/changed") {
      if (!threadId || !eventConversationId) {
        return;
      }
      const thread = (params.thread as Record<string, unknown>) ?? {};
      const status = String(params.status ?? thread.status ?? "unknown");
      this.emit({
        type: "conversation.thread.status.changed",
        conversationId: eventConversationId,
        turnId: eventTurnId,
        threadId,
        codexTurnId: effectiveCodexTurnId,
        status,
        thread
      });
      return;
    }

    if (method === "thread/tokenUsage/updated") {
      if (!threadId || !eventConversationId) {
        return;
      }
      const tokenUsage = (params.tokenUsage as Record<string, unknown>) ?? {};
      this.emit({
        type: "conversation.thread.token_usage.updated",
        conversationId: eventConversationId,
        turnId: eventTurnId,
        threadId,
        codexTurnId: effectiveCodexTurnId,
        tokenUsage
      });
      return;
    }

    if (!context || !threadId || !effectiveCodexTurnId) {
      return;
    }

    if (method === "turn/diff/updated") {
      this.emit({
        type: "conversation.turn.diff.updated",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId: effectiveCodexTurnId,
        diff: String(params.diff ?? "")
      });
      return;
    }

    if (method === "turn/plan/updated") {
      const explanation =
        typeof params.explanation === "string" ? params.explanation : null;
      const rawPlan = Array.isArray(params.plan) ? params.plan : [];
      const normalizedPlan: Record<string, unknown> = {
        plan: rawPlan
      };
      if (explanation !== null) {
        normalizedPlan.explanation = explanation;
      }
      this.emit({
        type: "conversation.turn.plan.updated",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId: effectiveCodexTurnId,
        plan: normalizedPlan
      });
      return;
    }

    if (method === "item/started") {
      const item = (params.item as Record<string, unknown>) ?? {};
      const itemId = String(item.id ?? params.itemId ?? "");
      const itemType = String(item.type ?? "unknown");
      if (!itemId) {
        return;
      }
      this.emit({
        type: "conversation.item.started",
        conversationId: context.conversationId,
        turnId: context.turnId,
        threadId,
        codexTurnId: effectiveCodexTurnId,
        itemId,
        itemType,
        item
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
        codexTurnId: effectiveCodexTurnId,
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
      method === "item/reasoning/summaryPartAdded" ||
      method === "item/plan/delta"
    ) {
      const itemId = String(params.itemId ?? "");
      const summaryPart = (params.part as Record<string, unknown> | undefined) ?? {};
      const summaryPartText = typeof summaryPart.text === "string" ? summaryPart.text : "";
      const delta = String(params.delta ?? summaryPartText);
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
        codexTurnId: effectiveCodexTurnId,
        itemId,
        stream,
        delta
      });
      return;
    }

    if (method === "serverRequest/resolved") {
      const request = (params.request as Record<string, unknown>) ?? {};
      const requestId = String(params.requestId ?? request.id ?? "");
      const result = params.result;
      const error = typeof params.error === "string" ? params.error : undefined;
      const resolvedViaPending = requestId.length > 0 && this.resolveServerRequest({ requestId, result, error });
      if (!resolvedViaPending) {
        this.emit({
          type: "conversation.server.request.resolved",
          conversationId: context.conversationId,
          turnId: context.turnId,
          threadId,
          codexTurnId: effectiveCodexTurnId,
          requestId,
          resolvedAt: new Date().toISOString(),
          status: error ? "failed" : "completed",
          result,
          error
        });
      }
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
        codexTurnId: effectiveCodexTurnId,
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

  private findConversationIdByThread(threadId: string): string {
    for (const [conversationId, mappedThreadId] of this.threadByConversation.entries()) {
      if (mappedThreadId === threadId) {
        return conversationId;
      }
    }
    return "";
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
