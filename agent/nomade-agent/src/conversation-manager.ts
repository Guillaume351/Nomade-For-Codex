import { CodexAppServerClient, type AppServerNotification } from "./codex-app-server.js";

interface ConversationTurnStartParams {
  conversationId: string;
  turnId: string;
  threadId?: string;
  prompt: string;
  model?: string;
  cwd?: string;
}

interface ConversationTurnInterruptParams {
  conversationId: string;
  turnId: string;
}

interface TurnContext {
  conversationId: string;
  turnId: string;
}

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
    try {
      await this.codexClient.start();

      let threadId = params.threadId ?? this.threadByConversation.get(params.conversationId);
      if (!threadId) {
        threadId = await this.codexClient.ensureThread({
          conversationId: params.conversationId,
          cwd: params.cwd,
          model: params.model
        });
        this.threadByConversation.set(params.conversationId, threadId);
        this.emit({
          type: "conversation.thread.started",
          conversationId: params.conversationId,
          threadId
        });
      }

      this.pendingTurnByThread.set(threadId, {
        conversationId: params.conversationId,
        turnId: params.turnId
      });

      const codexTurnId = await this.codexClient.turnStart({
        threadId,
        prompt: params.prompt,
        cwd: params.cwd,
        model: params.model
      });
      this.bindTurn(threadId, codexTurnId, {
        conversationId: params.conversationId,
        turnId: params.turnId
      });

      this.emit({
        type: "conversation.turn.started",
        conversationId: params.conversationId,
        turnId: params.turnId,
        threadId,
        codexTurnId
      });
    } catch (error) {
      this.emit({
        type: "conversation.turn.completed",
        conversationId: params.conversationId,
        turnId: params.turnId,
        threadId: params.threadId ?? "",
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
}
