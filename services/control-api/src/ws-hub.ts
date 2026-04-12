import { randomToken } from "@nomade/shared";
import { WebSocketServer, type WebSocket } from "ws";
import type { IncomingMessage } from "http";
import type { AuthService } from "./auth.js";
import type { Repositories } from "./repositories.js";
import type { TunnelDiagnostic } from "./tunnel-diagnostics.js";

interface AgentConnection {
  ws: WebSocket;
  userId: string;
}

interface ProxyResult {
  status: number;
  headers: Record<string, string>;
  bodyBase64: string;
}

interface PendingProxy {
  resolve: (value: ProxyResult) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

interface TunnelWsBridge {
  onFrame: (data: Buffer, isBinary: boolean) => void;
  onClosed: (code?: number, reason?: string) => void;
  onError: (error: string) => void;
}

interface PendingTunnelWsOpen {
  resolve: (connectionId: string) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
  agentId: string;
  connectionId: string;
  bridge: TunnelWsBridge;
}

export interface CodexThreadSummary {
  threadId: string;
  title: string;
  preview: string;
  cwd: string;
  updatedAt: number;
}

interface PendingThreadList {
  resolve: (value: CodexThreadSummary[]) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

export interface CodexThreadReadItem {
  itemId: string;
  itemType: string;
  payload: Record<string, unknown>;
}

export interface CodexThreadReadTurn {
  turnId: string;
  status: "running" | "completed" | "interrupted" | "failed";
  error?: string;
  userPrompt: string;
  items: CodexThreadReadItem[];
}

export interface CodexThreadReadSummary {
  threadId: string;
  title: string;
  preview: string;
  cwd: string;
  updatedAt: number;
  turns: CodexThreadReadTurn[];
}

interface PendingThreadRead {
  resolve: (value: CodexThreadReadSummary) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

export interface CodexModelOption {
  id: string;
  model: string;
  displayName: string;
  description: string;
  isDefault: boolean;
  hidden: boolean;
  defaultReasoningEffort: string;
  supportedReasoningEfforts: Array<{
    reasoningEffort: string;
    description: string;
  }>;
}

export interface CodexRuntimeOptions {
  models: CodexModelOption[];
  approvalPolicies: string[];
  sandboxModes: string[];
  reasoningEfforts: string[];
  collaborationModes: Array<Record<string, unknown>>;
  skills: Array<{ name: string; path: string }>;
  rateLimits?: Record<string, unknown>;
  rateLimitsByLimitId?: Record<string, Record<string, unknown>> | null;
  defaults: {
    model?: string;
    approvalPolicy?: string;
    sandboxMode?: string;
    effort?: string;
  };
}

interface PendingCodexOptions {
  resolve: (value: CodexRuntimeOptions) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

const normalizeCodexThreadReadItem = (rawItem: Record<string, unknown>, itemIndex: number): CodexThreadReadItem => {
  const wrappedPayload = rawItem.payload;
  if (wrappedPayload && typeof wrappedPayload === "object") {
    const payload = wrappedPayload as Record<string, unknown>;
    return {
      itemId: String(rawItem.itemId ?? payload.id ?? `item-${itemIndex + 1}`),
      itemType: String(rawItem.itemType ?? payload.type ?? "unknown"),
      payload
    };
  }

  return {
    itemId: String(rawItem.id ?? `item-${itemIndex + 1}`),
    itemType: String(rawItem.type ?? "unknown"),
    payload: rawItem
  };
};

const normalizeCodexThreadReadError = (value: unknown): string | undefined => {
  if (typeof value === "string" && value.trim().length > 0) {
    return value;
  }
  if (value && typeof value === "object") {
    const message = (value as Record<string, unknown>).message;
    if (typeof message === "string" && message.trim().length > 0) {
      return message;
    }
  }
  return undefined;
};

export const parseCodexThreadReadSummary = (rawThread: Record<string, unknown>): CodexThreadReadSummary => {
  const rawTurns = Array.isArray(rawThread.turns) ? rawThread.turns : [];
  const turns: CodexThreadReadTurn[] = rawTurns
    .filter((entry) => typeof entry === "object" && entry !== null)
    .map((entry, index) => {
      const turn = entry as Record<string, unknown>;
      const rawStatus = String(turn.status ?? "failed");
      const status =
        rawStatus === "completed" || rawStatus === "interrupted" || rawStatus === "failed" ? rawStatus : "running";
      const rawItems = Array.isArray(turn.items) ? turn.items : [];
      const items = rawItems
        .filter((item) => typeof item === "object" && item !== null)
        .map((item, itemIndex) => normalizeCodexThreadReadItem(item as Record<string, unknown>, itemIndex));

      return {
        turnId: String(turn.turnId ?? turn.id ?? `turn-${index + 1}`),
        status,
        error: normalizeCodexThreadReadError(turn.error),
        userPrompt: String(turn.userPrompt ?? ""),
        items
      };
    });

  return {
    threadId: String(rawThread.threadId ?? rawThread.id ?? ""),
    title: String(rawThread.title ?? "Codex thread"),
    preview: String(rawThread.preview ?? ""),
    cwd: String(rawThread.cwd ?? "."),
    updatedAt: Number(rawThread.updatedAt ?? 0),
    turns
  };
};

export class WsHub {
  private readonly wss: WebSocketServer;
  private readonly userSockets = new Map<string, Set<WebSocket>>();
  private readonly agentSockets = new Map<string, AgentConnection>();
  private readonly sessionOwner = new Map<string, string>();
  private readonly sessionAgent = new Map<string, string>();
  private readonly tunnelOwner = new Map<string, string>();
  private readonly conversationOwner = new Map<string, string>();
  private readonly conversationAgent = new Map<string, string>();
  private readonly turnConversation = new Map<string, string>();
  private readonly pendingProxy = new Map<string, PendingProxy>();
  private readonly pendingTunnelWsOpen = new Map<string, PendingTunnelWsOpen>();
  private readonly tunnelWsRoute = new Map<string, { agentId: string; bridge: TunnelWsBridge }>();
  private readonly pendingThreadList = new Map<string, PendingThreadList>();
  private readonly pendingThreadRead = new Map<string, PendingThreadRead>();
  private readonly pendingCodexOptions = new Map<string, PendingCodexOptions>();

  constructor(
    private readonly auth: AuthService,
    private readonly repositories: Repositories,
    private readonly server: import("http").Server
  ) {
    this.wss = new WebSocketServer({ noServer: true });
    this.server.on("upgrade", (req, socket, head) => this.handleUpgrade(req, socket, head));
  }

  rememberSessionOwner(sessionId: string, userId: string, agentId?: string): void {
    this.sessionOwner.set(sessionId, userId);
    if (agentId) {
      this.sessionAgent.set(sessionId, agentId);
    }
  }

  rememberTunnelOwner(tunnelId: string, userId: string): void {
    this.tunnelOwner.set(tunnelId, userId);
  }

  publishTunnelStatus(
    tunnelId: string,
    payload: {
      status: "open" | "closed" | "error" | "starting" | "healthy" | "unhealthy" | "stopped";
      detail?: string;
      probeStatus?: "ok" | "error" | "unknown";
      probeCode?: number;
      diagnostic?: TunnelDiagnostic | null;
    }
  ): void {
    const userId = this.tunnelOwner.get(tunnelId);
    if (!userId) {
      return;
    }
    const message: Record<string, unknown> = {
      type: "tunnel.status",
      tunnelId,
      status: payload.status,
      detail: payload.detail,
      probeStatus: payload.probeStatus,
      probeCode: payload.probeCode,
      probeAt: new Date().toISOString()
    };
    if ("diagnostic" in payload) {
      message.diagnostic = payload.diagnostic ?? null;
    }
    this.broadcastToUser(userId, message);
  }

  rememberConversationOwner(conversationId: string, userId: string, agentId?: string): void {
    this.conversationOwner.set(conversationId, userId);
    if (agentId) {
      this.conversationAgent.set(conversationId, agentId);
    }
  }

  rememberConversationTurn(turnId: string, conversationId: string): void {
    this.turnConversation.set(turnId, conversationId);
  }

  sendToAgent(agentId: string, message: unknown): boolean {
    const conn = this.agentSockets.get(agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      return false;
    }
    conn.ws.send(JSON.stringify(message));
    return true;
  }

  isAgentOnline(agentId: string): boolean {
    const conn = this.agentSockets.get(agentId);
    return Boolean(conn && conn.ws.readyState === conn.ws.OPEN);
  }

  listOnlineAgentIdsForUser(userId: string): string[] {
    const ids: string[] = [];
    for (const [agentId, conn] of this.agentSockets.entries()) {
      if (conn.userId === userId && conn.ws.readyState === conn.ws.OPEN) {
        ids.push(agentId);
      }
    }
    return ids;
  }

  async openTunnelWsThroughAgent(params: {
    agentId: string;
    tunnelId: string;
    path: string;
    query?: string;
    headers?: Record<string, string>;
    bridge: TunnelWsBridge;
  }): Promise<string> {
    const requestId = randomToken("two");
    const connectionId = randomToken("twc");
    const conn = this.agentSockets.get(params.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      throw new Error("agent_offline");
    }

    const payload = {
      type: "tunnel.ws.open",
      requestId,
      connectionId,
      tunnelId: params.tunnelId,
      path: params.path,
      query: params.query,
      headers: params.headers ?? {}
    };

    return new Promise<string>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingTunnelWsOpen.delete(requestId);
        reject(new Error("tunnel_ws_open_timeout"));
      }, 15_000);

      this.pendingTunnelWsOpen.set(requestId, {
        resolve,
        reject,
        timeout,
        agentId: params.agentId,
        connectionId,
        bridge: params.bridge
      });

      conn.ws.send(JSON.stringify(payload));
    });
  }

  sendTunnelWsFrame(params: { connectionId: string; data: Buffer; isBinary: boolean }): void {
    const route = this.tunnelWsRoute.get(params.connectionId);
    if (!route) {
      return;
    }
    const conn = this.agentSockets.get(route.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      route.bridge.onError("agent_offline");
      this.tunnelWsRoute.delete(params.connectionId);
      return;
    }

    conn.ws.send(
      JSON.stringify({
        type: "tunnel.ws.frame",
        connectionId: params.connectionId,
        dataBase64: params.data.toString("base64"),
        isBinary: params.isBinary
      })
    );
  }

  closeTunnelWs(params: { connectionId: string; code?: number; reason?: string }): void {
    const route = this.tunnelWsRoute.get(params.connectionId);
    if (!route) {
      return;
    }
    const conn = this.agentSockets.get(route.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      this.tunnelWsRoute.delete(params.connectionId);
      return;
    }

    conn.ws.send(
      JSON.stringify({
        type: "tunnel.ws.close",
        connectionId: params.connectionId,
        code: params.code,
        reason: params.reason
      })
    );
  }

  async proxyHttpThroughAgent(params: {
    agentId: string;
    tunnelId: string;
    method: string;
    path: string;
    query?: string;
    headers: Record<string, string>;
    bodyBase64?: string;
  }): Promise<ProxyResult> {
    const requestId = randomToken("tr");
    const conn = this.agentSockets.get(params.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      throw new Error("agent_offline");
    }

    const payload = {
      type: "tunnel.http.request",
      requestId,
      tunnelId: params.tunnelId,
      method: params.method,
      path: params.path,
      query: params.query,
      headers: params.headers,
      bodyBase64: params.bodyBase64
    };

    return new Promise<ProxyResult>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingProxy.delete(requestId);
        reject(new Error("proxy_timeout"));
      }, 15_000);

      this.pendingProxy.set(requestId, { resolve, reject, timeout });
      conn.ws.send(JSON.stringify(payload));
    });
  }

  async listCodexThreadsThroughAgent(params: {
    agentId: string;
    limit?: number;
  }): Promise<CodexThreadSummary[]> {
    const requestId = randomToken("cl");
    const conn = this.agentSockets.get(params.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      throw new Error("agent_offline");
    }

    const payload = {
      type: "codex.thread.list",
      requestId,
      limit: params.limit ?? 100
    };

    return new Promise<CodexThreadSummary[]>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingThreadList.delete(requestId);
        reject(new Error("thread_list_timeout"));
      }, 20_000);

      this.pendingThreadList.set(requestId, { resolve, reject, timeout });
      conn.ws.send(JSON.stringify(payload));
    });
  }

  async readCodexThreadThroughAgent(params: {
    agentId: string;
    threadId: string;
    conversationId?: string;
  }): Promise<CodexThreadReadSummary> {
    const requestId = randomToken("cr");
    const conn = this.agentSockets.get(params.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      throw new Error("agent_offline");
    }

    const payload = {
      type: "codex.thread.read",
      requestId,
      threadId: params.threadId,
      conversationId: params.conversationId
    };

    return new Promise<CodexThreadReadSummary>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingThreadRead.delete(requestId);
        reject(new Error("thread_read_timeout"));
      }, 20_000);

      this.pendingThreadRead.set(requestId, { resolve, reject, timeout });
      conn.ws.send(JSON.stringify(payload));
    });
  }

  async getCodexOptionsThroughAgent(params: {
    agentId: string;
    cwd?: string;
  }): Promise<CodexRuntimeOptions> {
    const requestId = randomToken("co");
    const conn = this.agentSockets.get(params.agentId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) {
      throw new Error("agent_offline");
    }

    const payload = {
      type: "codex.options.get",
      requestId,
      cwd: params.cwd
    };

    return new Promise<CodexRuntimeOptions>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingCodexOptions.delete(requestId);
        reject(new Error("codex_options_timeout"));
      }, 20_000);

      this.pendingCodexOptions.set(requestId, { resolve, reject, timeout });
      conn.ws.send(JSON.stringify(payload));
    });
  }

  private handleUpgrade(req: IncomingMessage, socket: import("stream").Duplex, head: Buffer): void {
    const url = new URL(req.url ?? "/", "http://localhost");
    if (url.pathname !== "/ws") {
      return;
    }

    const accessToken = url.searchParams.get("access_token");
    const agentToken = url.searchParams.get("agent_token");

    if (!accessToken && !agentToken) {
      socket.destroy();
      return;
    }

    this.wss.handleUpgrade(req, socket, head, (ws) => {
      if (accessToken) {
        void this.auth.verifyAccessTokenWithUser(accessToken).then((claims) => {
          if (!claims) {
            ws.close();
            return;
          }
          this.bindUserSocket(claims.sub, ws);
        });
        return;
      }

      void this.bindAgentSocket(agentToken!, ws);
    });
  }

  private bindUserSocket(userId: string, ws: WebSocket): void {
    const set = this.userSockets.get(userId) ?? new Set<WebSocket>();
    set.add(ws);
    this.userSockets.set(userId, set);

    ws.on("message", (raw) => {
      try {
        const msg = JSON.parse(raw.toString()) as Record<string, unknown>;
        if (msg.type === "conversation.server.response") {
          const conversationId = String(msg.conversationId ?? "");
          const turnId = String(msg.turnId ?? "");
          const explicitAgentId = typeof msg.agentId === "string" ? msg.agentId : undefined;
          const agentId = explicitAgentId ?? this.conversationAgent.get(conversationId);
          if (!agentId) {
            ws.send(
              JSON.stringify({
                type: "error",
                code: "conversation_unknown",
                message: "Unknown conversation routing"
              })
            );
            return;
          }
          if (turnId && conversationId) {
            this.turnConversation.set(turnId, conversationId);
          }
          this.sendToAgent(agentId, {
            ...msg,
            agentId
          });
          return;
        }

        if (msg.type === "session.create") {
          const agentId = String(msg.agentId ?? "");
          const sessionId = String(msg.sessionId ?? "");
          if (!agentId || !sessionId) {
            return;
          }
          this.sessionAgent.set(sessionId, agentId);
          this.sendToAgent(agentId, msg);
          return;
        }

        if (msg.type === "session.input" || msg.type === "session.terminate") {
          const sessionId = String(msg.sessionId ?? "");
          const explicitAgentId = msg.agentId ? String(msg.agentId) : undefined;
          const agentId = explicitAgentId ?? this.sessionAgent.get(sessionId);
          if (!agentId) {
            ws.send(JSON.stringify({ type: "error", code: "session_unknown", message: "Unknown session routing" }));
            return;
          }
          this.sendToAgent(agentId, {
            ...msg,
            agentId
          });
        }
      } catch {
        ws.send(JSON.stringify({ type: "error", code: "bad_message", message: "Invalid JSON payload" }));
      }
    });

    ws.on("close", () => {
      const current = this.userSockets.get(userId);
      if (!current) {
        return;
      }
      current.delete(ws);
      if (!current.size) {
        this.userSockets.delete(userId);
      }
    });
  }

  private async bindAgentSocket(agentToken: string, ws: WebSocket): Promise<void> {
    const agent = await this.repositories.findAgentByToken(agentToken);
    if (!agent) {
      ws.close();
      return;
    }

    this.agentSockets.set(agent.agentId, { ws, userId: agent.userId });
    await this.repositories.touchAgentLastSeen(agent.agentId);

    ws.on("message", (raw) => {
      try {
        const msg = JSON.parse(raw.toString()) as Record<string, unknown>;
        this.handleAgentMessage(agent.agentId, agent.userId, msg);
      } catch {
        ws.send(JSON.stringify({ type: "error", code: "bad_message", message: "Invalid JSON payload" }));
      }
    });

    ws.on("close", () => {
      const existing = this.agentSockets.get(agent.agentId);
      if (existing?.ws === ws) {
        this.agentSockets.delete(agent.agentId);
      }

      for (const [requestId, pending] of this.pendingTunnelWsOpen.entries()) {
        if (pending.agentId !== agent.agentId) {
          continue;
        }
        clearTimeout(pending.timeout);
        this.pendingTunnelWsOpen.delete(requestId);
        pending.reject(new Error("agent_offline"));
      }

      for (const [connectionId, route] of this.tunnelWsRoute.entries()) {
        if (route.agentId !== agent.agentId) {
          continue;
        }
        this.tunnelWsRoute.delete(connectionId);
        route.bridge.onError("agent_offline");
      }
    });
  }

  private handleAgentMessage(agentId: string, defaultUserId: string, msg: Record<string, unknown>): void {
    const type = String(msg.type ?? "");
    if (type === "session.output") {
      const sessionId = String(msg.sessionId ?? "");
      const cursor = Number(msg.cursor ?? 0);
      const userId = this.sessionOwner.get(sessionId) ?? defaultUserId;
      if (sessionId) {
        void this.repositories.updateSessionCursor(sessionId, cursor);
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "session.status") {
      const sessionId = String(msg.sessionId ?? "");
      const status = String(msg.status ?? "failed");
      const userId = this.sessionOwner.get(sessionId) ?? defaultUserId;
      if (sessionId) {
        void this.repositories.updateSessionStatus(sessionId, status);
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "tunnel.status") {
      const tunnelId = String(msg.tunnelId ?? "");
      const userId = this.tunnelOwner.get(tunnelId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "tunnel.http.response") {
      const requestId = String(msg.requestId ?? "");
      const pending = this.pendingProxy.get(requestId);
      if (!pending) {
        return;
      }
      this.pendingProxy.delete(requestId);
      clearTimeout(pending.timeout);
      pending.resolve({
        status: Number(msg.status ?? 502),
        headers: (msg.headers as Record<string, string>) ?? {},
        bodyBase64: String(msg.bodyBase64 ?? "")
      });
      return;
    }

    if (type === "tunnel.ws.opened") {
      const requestId = String(msg.requestId ?? "");
      const pending = this.pendingTunnelWsOpen.get(requestId);
      if (!pending) {
        return;
      }
      this.pendingTunnelWsOpen.delete(requestId);
      clearTimeout(pending.timeout);
      this.tunnelWsRoute.set(pending.connectionId, {
        agentId: pending.agentId,
        bridge: pending.bridge
      });
      pending.resolve(pending.connectionId);
      return;
    }

    if (type === "tunnel.ws.frame") {
      const connectionId = String(msg.connectionId ?? "");
      const route = this.tunnelWsRoute.get(connectionId);
      if (!route) {
        return;
      }
      const encoded = String(msg.dataBase64 ?? "");
      const isBinary = msg.isBinary === true;
      route.bridge.onFrame(Buffer.from(encoded, "base64"), isBinary);
      return;
    }

    if (type === "tunnel.ws.closed") {
      const connectionId = String(msg.connectionId ?? "");
      const route = this.tunnelWsRoute.get(connectionId);
      if (!route) {
        return;
      }
      this.tunnelWsRoute.delete(connectionId);
      route.bridge.onClosed(
        typeof msg.code === "number" ? Number(msg.code) : undefined,
        typeof msg.reason === "string" ? msg.reason : undefined
      );
      return;
    }

    if (type === "tunnel.ws.error") {
      const requestId = String(msg.requestId ?? "");
      if (requestId) {
        const pending = this.pendingTunnelWsOpen.get(requestId);
        if (pending) {
          this.pendingTunnelWsOpen.delete(requestId);
          clearTimeout(pending.timeout);
          pending.reject(new Error(String(msg.error ?? "tunnel_ws_open_failed")));
          return;
        }
      }

      const connectionId = String(msg.connectionId ?? "");
      if (!connectionId) {
        return;
      }
      const route = this.tunnelWsRoute.get(connectionId);
      if (!route) {
        return;
      }
      this.tunnelWsRoute.delete(connectionId);
      route.bridge.onError(String(msg.error ?? "tunnel_ws_error"));
      return;
    }

    if (type === "codex.thread.list.result") {
      const requestId = String(msg.requestId ?? "");
      const pending = this.pendingThreadList.get(requestId);
      if (!pending) {
        return;
      }
      this.pendingThreadList.delete(requestId);
      clearTimeout(pending.timeout);

      const status = String(msg.status ?? "error");
      if (status !== "ok") {
        pending.reject(new Error(String(msg.error ?? "thread_list_failed")));
        return;
      }

      const rawItems = Array.isArray(msg.items) ? msg.items : [];
      const items = rawItems
        .filter((item) => typeof item === "object" && item !== null)
        .map((item) => {
          const entry = item as Record<string, unknown>;
          return {
            threadId: String(entry.threadId ?? ""),
            title: String(entry.title ?? "Codex thread"),
            preview: String(entry.preview ?? ""),
            cwd: String(entry.cwd ?? "."),
            updatedAt: Number(entry.updatedAt ?? 0)
          };
        })
        .filter((item) => item.threadId.length > 0);

      pending.resolve(items);
      return;
    }

    if (type === "codex.thread.read.result") {
      const requestId = String(msg.requestId ?? "");
      const pending = this.pendingThreadRead.get(requestId);
      if (!pending) {
        return;
      }
      this.pendingThreadRead.delete(requestId);
      clearTimeout(pending.timeout);

      const status = String(msg.status ?? "error");
      if (status !== "ok") {
        pending.reject(new Error(String(msg.error ?? "thread_read_failed")));
        return;
      }

      const rawThread = msg.thread;
      if (!rawThread || typeof rawThread !== "object") {
        pending.reject(new Error("thread_read_missing_thread"));
        return;
      }

      pending.resolve(parseCodexThreadReadSummary(rawThread as Record<string, unknown>));
      return;
    }

    if (type === "codex.options.result") {
      const requestId = String(msg.requestId ?? "");
      const pending = this.pendingCodexOptions.get(requestId);
      if (!pending) {
        return;
      }
      this.pendingCodexOptions.delete(requestId);
      clearTimeout(pending.timeout);

      const status = String(msg.status ?? "error");
      if (status !== "ok") {
        pending.reject(new Error(String(msg.error ?? "codex_options_failed")));
        return;
      }

      const optionsRaw = msg.options;
      if (!optionsRaw || typeof optionsRaw !== "object") {
        pending.reject(new Error("codex_options_missing_payload"));
        return;
      }

      const options = optionsRaw as Record<string, unknown>;
      const modelsRaw = Array.isArray(options.models) ? options.models : [];
      const models: CodexModelOption[] = modelsRaw
        .filter((entry) => typeof entry === "object" && entry !== null)
        .map((entry) => {
          const model = entry as Record<string, unknown>;
          const effortsRaw = Array.isArray(model.supportedReasoningEfforts) ? model.supportedReasoningEfforts : [];
          const supportedReasoningEfforts = effortsRaw
            .filter((effort) => typeof effort === "object" && effort !== null)
            .map((effort) => {
              const value = effort as Record<string, unknown>;
              return {
                reasoningEffort: String(value.reasoningEffort ?? ""),
                description: String(value.description ?? "")
              };
            })
            .filter((effort) => effort.reasoningEffort.length > 0);

          return {
            id: String(model.id ?? ""),
            model: String(model.model ?? ""),
            displayName: String(model.displayName ?? model.model ?? ""),
            description: String(model.description ?? ""),
            isDefault: model.isDefault === true,
            hidden: model.hidden === true,
            defaultReasoningEffort: String(model.defaultReasoningEffort ?? "medium"),
            supportedReasoningEfforts
          };
        })
        .filter((model) => model.model.length > 0);

      const toStringList = (value: unknown): string[] =>
        Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];

      const collaborationModesRaw = Array.isArray(options.collaborationModes) ? options.collaborationModes : [];
      const collaborationModes = collaborationModesRaw
        .filter((entry) => typeof entry === "object" && entry !== null)
        .map((entry) => entry as Record<string, unknown>);

      const skillsRaw = Array.isArray(options.skills) ? options.skills : [];
      const skills = skillsRaw
        .filter((entry) => typeof entry === "object" && entry !== null)
        .map((entry) => {
          const value = entry as Record<string, unknown>;
          return {
            name: String(value.name ?? ""),
            path: String(value.path ?? "")
          };
        })
        .filter((entry) => entry.path.length > 0);

      const defaultsRaw = (options.defaults as Record<string, unknown> | undefined) ?? {};
      const rateLimitsRaw =
        options.rateLimits && typeof options.rateLimits === "object"
          ? (options.rateLimits as Record<string, unknown>)
          : undefined;
      const rateLimitsByLimitIdRaw = options.rateLimitsByLimitId;
      let rateLimitsByLimitId: Record<string, Record<string, unknown>> | null =
        null;
      if (rateLimitsByLimitIdRaw && typeof rateLimitsByLimitIdRaw === "object") {
        const normalized: Record<string, Record<string, unknown>> = {};
        for (const [limitId, value] of Object.entries(
          rateLimitsByLimitIdRaw as Record<string, unknown>
        )) {
          if (!value || typeof value !== "object") {
            continue;
          }
          normalized[limitId] = value as Record<string, unknown>;
        }
        rateLimitsByLimitId =
          Object.keys(normalized).length > 0 ? normalized : null;
      }
      pending.resolve({
        models,
        approvalPolicies: toStringList(options.approvalPolicies),
        sandboxModes: toStringList(options.sandboxModes),
        reasoningEfforts: toStringList(options.reasoningEfforts),
        collaborationModes,
        skills,
        rateLimits: rateLimitsRaw,
        rateLimitsByLimitId,
        defaults: {
          model: typeof defaultsRaw.model === "string" ? defaultsRaw.model : undefined,
          approvalPolicy: typeof defaultsRaw.approvalPolicy === "string" ? defaultsRaw.approvalPolicy : undefined,
          sandboxMode: typeof defaultsRaw.sandboxMode === "string" ? defaultsRaw.sandboxMode : undefined,
          effort: typeof defaultsRaw.effort === "string" ? defaultsRaw.effort : undefined
        }
      });
      return;
    }

    if (type === "agent.hello") {
      void this.repositories.touchAgentLastSeen(agentId);
      return;
    }

    if (type === "agent.heartbeat") {
      void this.repositories.touchAgentLastSeen(agentId);
      return;
    }

    if (type === "account.rate_limits.updated") {
      this.broadcastToUser(defaultUserId, msg);
      return;
    }

    if (type === "conversation.thread.started") {
      const conversationId = String(msg.conversationId ?? "");
      const threadId = String(msg.threadId ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;

      if (conversationId && threadId) {
        void this.repositories.updateConversationThreadId(conversationId, threadId);
        void this.repositories.updateConversationStatus(conversationId, "running");
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.turn.started") {
      const conversationId = String(msg.conversationId ?? "");
      const turnId = String(msg.turnId ?? "");
      const codexTurnId = String(msg.codexTurnId ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;

      if (conversationId) {
        void this.repositories.updateConversationStatus(conversationId, "running");
      }
      if (turnId && conversationId) {
        this.turnConversation.set(turnId, conversationId);
      }
      if (turnId && codexTurnId) {
        void this.repositories.markConversationTurnStarted({ turnId, codexTurnId });
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.turn.diff.updated") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const turnId = String(msg.turnId ?? "");
      const e2eEnvelope = msg.e2eEnvelope && typeof msg.e2eEnvelope === "object"
        ? (msg.e2eEnvelope as Record<string, unknown>)
        : null;
      const diff = e2eEnvelope ? JSON.stringify({ e2eEnvelope }) : String(msg.diff ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      if (turnId) {
        void this.repositories.updateConversationTurnDiff(turnId, diff);
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.item.started") {
      const turnId = String(msg.turnId ?? "");
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(turnId) ?? "");
      const itemId = String(msg.itemId ?? "");
      const itemType = String(msg.itemType ?? "unknown");
      const item = (msg.item as Record<string, unknown>) ?? {};
      const payload =
        msg.e2eEnvelope && typeof msg.e2eEnvelope === "object"
          ? { e2eEnvelope: msg.e2eEnvelope as Record<string, unknown> }
          : item;
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;

      if (turnId && itemId) {
        void this.repositories.upsertConversationItem({
          turnId,
          itemId,
          itemType,
          payload
        });
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.item.completed") {
      const turnId = String(msg.turnId ?? "");
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(turnId) ?? "");
      const itemId = String(msg.itemId ?? "");
      const itemType = String(msg.itemType ?? "unknown");
      const item = (msg.item as Record<string, unknown>) ?? {};
      const payload =
        msg.e2eEnvelope && typeof msg.e2eEnvelope === "object"
          ? { e2eEnvelope: msg.e2eEnvelope as Record<string, unknown> }
          : item;
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;

      if (turnId && itemId) {
        void this.repositories.upsertConversationItem({
          turnId,
          itemId,
          itemType,
          payload
        });
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.item.delta") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.turn.plan.updated") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.thread.status.changed") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.thread.token_usage.updated") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.server.request" || type === "conversation.server.request.resolved") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.turn.completed") {
      const conversationId = String(msg.conversationId ?? this.turnConversation.get(String(msg.turnId ?? "")) ?? "");
      const turnId = String(msg.turnId ?? "");
      const statusRaw = String(msg.status ?? "failed");
      const error = msg.error ? String(msg.error) : undefined;
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      const status =
        statusRaw === "completed" || statusRaw === "interrupted" ? statusRaw : ("failed" as const);

      if (turnId) {
        void this.repositories.completeConversationTurn({
          turnId,
          status,
          error
        });
      }
      if (conversationId) {
        void this.repositories.updateConversationStatus(
          conversationId,
          status === "completed" ? "idle" : status === "interrupted" ? "interrupted" : "failed"
        );
      }
      this.broadcastToUser(userId, msg);
    }
  }

  private broadcastToUser(userId: string, payload: unknown): void {
    const set = this.userSockets.get(userId);
    if (!set) {
      return;
    }
    const encoded = JSON.stringify(payload);
    for (const ws of set) {
      if (ws.readyState === ws.OPEN) {
        ws.send(encoded);
      }
    }
  }
}
