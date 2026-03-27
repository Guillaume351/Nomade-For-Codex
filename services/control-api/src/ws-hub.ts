import { randomToken } from "@nomade/shared";
import { WebSocketServer, type WebSocket } from "ws";
import type { IncomingMessage } from "http";
import type { AuthService } from "./auth.js";
import type { Repositories } from "./repositories.js";

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

  private handleUpgrade(req: IncomingMessage, socket: import("stream").Duplex, head: Buffer): void {
    const url = new URL(req.url ?? "/", "http://localhost");
    if (url.pathname !== "/ws") {
      socket.destroy();
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
        const claims = this.auth.verifyAccessToken(accessToken);
        if (!claims) {
          ws.close();
          return;
        }
        this.bindUserSocket(claims.sub, ws);
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

    if (type === "agent.heartbeat") {
      void this.repositories.touchAgentLastSeen(agentId);
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
      const conversationId = String(msg.conversationId ?? "");
      const turnId = String(msg.turnId ?? "");
      const diff = String(msg.diff ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      if (turnId) {
        void this.repositories.updateConversationTurnDiff(turnId, diff);
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.item.completed") {
      const conversationId = String(msg.conversationId ?? "");
      const turnId = String(msg.turnId ?? "");
      const itemId = String(msg.itemId ?? "");
      const itemType = String(msg.itemType ?? "unknown");
      const item = (msg.item as Record<string, unknown>) ?? {};
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;

      if (turnId && itemId) {
        void this.repositories.addConversationItem({
          turnId,
          itemId,
          itemType,
          payload: item
        });
      }
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.item.delta") {
      const conversationId = String(msg.conversationId ?? "");
      const userId = this.conversationOwner.get(conversationId) ?? defaultUserId;
      this.broadcastToUser(userId, msg);
      return;
    }

    if (type === "conversation.turn.completed") {
      const conversationId = String(msg.conversationId ?? "");
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
