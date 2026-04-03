import http from "node:http";
import path from "node:path";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { WebSocketServer, type WebSocket } from "ws";
import { z } from "zod";
import { sha256 } from "@nomade/shared";
import { loadConfig } from "./config.js";
import { createPool, ensureSchema } from "./db.js";
import { Repositories, type TunnelRecord } from "./repositories.js";
import { AuthService } from "./auth.js";
import { requireUserAuth } from "./http-auth.js";
import { WsHub } from "./ws-hub.js";
import { DevServiceManager } from "./service-manager.js";
import { previewOriginForSlug } from "./preview-origin.js";
import {
  buildTransportTunnelDiagnostic,
  classifyProxyResponseDiagnostic,
  type TunnelDiagnostic
} from "./tunnel-diagnostics.js";

const jsonLimit = "2mb";
const agentOnlineWindowMs = 30_000;
const proxyResponseSecurityHeaders = [
  "content-security-policy",
  "cross-origin-opener-policy",
  "cross-origin-resource-policy",
  "origin-agent-cluster",
  "referrer-policy",
  "strict-transport-security",
  "x-content-type-options",
  "x-dns-prefetch-control",
  "x-download-options",
  "x-frame-options",
  "x-permitted-cross-domain-policies",
  "x-xss-protection"
] as const;

const clearSecurityHeadersForProxiedResponse = (res: express.Response): void => {
  for (const header of proxyResponseSecurityHeaders) {
    res.removeHeader(header);
  }
};

const isValidWsCloseCode = (code: number): boolean => {
  if (code >= 3000 && code <= 4999) {
    return true;
  }
  if (code < 1000 || code > 1014) {
    return false;
  }
  return code !== 1004 && code !== 1005 && code !== 1006;
};

const normalizeWsCloseCode = (code: number | undefined): number => {
  if (typeof code === "number" && isValidWsCloseCode(code)) {
    return code;
  }
  return 1000;
};

const sanitizeWsCloseReason = (reason: string): string => {
  if (!reason) {
    return "";
  }
  const encoded = Buffer.from(reason, "utf8");
  if (encoded.length <= 123) {
    return reason;
  }
  return encoded.subarray(0, 123).toString("utf8");
};

const closeWebSocketSafely = (socket: WebSocket, code: number | undefined, reason: string | undefined): void => {
  if (socket.readyState === socket.CLOSED || socket.readyState === socket.CLOSING) {
    return;
  }
  try {
    if (socket.readyState === socket.CONNECTING) {
      socket.terminate();
      return;
    }
    const safeCode = normalizeWsCloseCode(code);
    const safeReason = sanitizeWsCloseReason(reason ?? "");
    if (safeReason.length > 0) {
      socket.close(safeCode, safeReason);
      return;
    }
    socket.close(safeCode);
  } catch {
    try {
      socket.terminate();
    } catch {
      // no-op
    }
  }
};

const isTruthyQuery = (value: unknown): boolean => {
  if (typeof value !== "string") {
    return false;
  }
  const normalized = value.trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes";
};

const hasLegacyWrappedItemPayload = (payload: unknown): boolean => {
  if (!payload || typeof payload !== "object") {
    return false;
  }
  const value = payload as Record<string, unknown>;
  return typeof value.itemType === "string" && value.payload !== undefined;
};

const turnsNeedRepair = (
  turns: Array<{ items?: Array<{ item_type?: unknown; payload?: unknown }> }>
): boolean => {
  for (const turn of turns) {
    const items = Array.isArray(turn.items) ? turn.items : [];
    for (const item of items) {
      const itemType = String(item.item_type ?? "");
      if (itemType === "unknown") {
        return true;
      }
      if (hasLegacyWrappedItemPayload(item.payload)) {
        return true;
      }
    }
  }
  return false;
};

const derivePromptFromInputItems = (inputItems: Array<Record<string, unknown>>): string => {
  const textParts: string[] = [];
  for (const item of inputItems) {
    if (item.type !== "text") {
      continue;
    }
    const text = typeof item.text === "string" ? item.text.trim() : "";
    if (text.length > 0) {
      textParts.push(text);
    }
  }
  if (textParts.length > 0) {
    return textParts.join("\n\n");
  }
  return "[non-text input]";
};

export const createServer = async (): Promise<http.Server> => {
  const config = loadConfig();
  const pool = createPool(config.databaseUrl);
  await ensureSchema(pool);

  const repositories = new Repositories(pool);
  const auth = new AuthService(config, repositories);

  const app = express();
  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: jsonLimit }));

  app.get("/health", (_req, res) => {
    res.json({ status: "ok", timestamp: new Date().toISOString() });
  });

  const server = http.createServer(app);
  const wsHub = new WsHub(auth, repositories, server);
  const devServiceManager = new DevServiceManager(
    repositories,
    wsHub,
    config.previewBaseDomain,
    config.previewBaseOrigin
  );
  const internalTunnelWsServer = new WebSocketServer({ noServer: true });

  const previewOriginFor = (slug: string): string =>
    previewOriginForSlug({
      slug,
      baseDomain: config.previewBaseDomain,
      baseOrigin: config.previewBaseOrigin
    });

  const renderPreviewUrl = (params: {
    slug: string;
    tokenRequired: boolean;
    token?: string;
  }): string => {
    const origin = previewOriginFor(params.slug);
    if (!params.tokenRequired) {
      return origin;
    }
    if (!params.token) {
      return origin;
    }
    return `${origin}?nomade_token=${encodeURIComponent(params.token)}`;
  };

  const tunnelDiagnostics = new Map<string, TunnelDiagnostic>();

  const tunnelStatusFromRecord = (
    tunnel: TunnelRecord
  ): "open" | "closed" | "error" | "healthy" | "unhealthy" => {
    if (tunnel.status === "closed") {
      return "closed";
    }
    if (tunnel.status !== "open") {
      return "error";
    }
    if (tunnel.last_probe_status === "ok") {
      return "healthy";
    }
    if (tunnel.last_probe_status === "error") {
      return "unhealthy";
    }
    return "open";
  };

  const getTunnelDiagnostic = (tunnelId: string): TunnelDiagnostic | null => {
    return tunnelDiagnostics.get(tunnelId) ?? null;
  };

  const sameDiagnostic = (
    left: TunnelDiagnostic | null | undefined,
    right: TunnelDiagnostic | null | undefined
  ): boolean => {
    if (!left && !right) {
      return true;
    }
    if (!left || !right) {
      return false;
    }
    return left.code === right.code && left.scope === right.scope && left.message === right.message;
  };

  const updateTunnelDiagnostic = (params: {
    tunnel: TunnelRecord;
    diagnostic: TunnelDiagnostic | null;
    detail?: string;
  }): void => {
    const existing = getTunnelDiagnostic(params.tunnel.id);
    if (sameDiagnostic(existing, params.diagnostic)) {
      return;
    }
    if (params.diagnostic) {
      tunnelDiagnostics.set(params.tunnel.id, params.diagnostic);
    } else {
      tunnelDiagnostics.delete(params.tunnel.id);
    }
    wsHub.publishTunnelStatus(params.tunnel.id, {
      status: tunnelStatusFromRecord(params.tunnel),
      detail: params.detail,
      diagnostic: params.diagnostic
    });
  };

  const tunnelAgentCandidates = (tunnel: TunnelRecord): string[] => {
    const online = wsHub.listOnlineAgentIdsForUser(tunnel.user_id);
    return [tunnel.agent_id, ...online.filter((agentId) => agentId !== tunnel.agent_id)];
  };

  const persistTunnelAgent = async (tunnel: TunnelRecord, agentId: string): Promise<void> => {
    if (tunnel.agent_id === agentId) {
      return;
    }
    try {
      await repositories.updateTunnelAgent(tunnel.id, agentId);
      tunnel.agent_id = agentId;
    } catch {
      // best effort only; request can still succeed
    }
  };

  const ensureTunnelOpenOnAgent = (tunnel: TunnelRecord, agentId: string): boolean => {
    return wsHub.sendToAgent(agentId, {
      type: "tunnel.open",
      tunnelId: tunnel.id,
      slug: tunnel.slug,
      targetPort: tunnel.target_port
    });
  };

  const proxyTunnelThroughAvailableAgent = async (params: {
    tunnel: TunnelRecord;
    method: string;
    path: string;
    query?: string;
    headers: Record<string, string>;
    bodyBase64?: string;
  }) => {
    for (const agentId of tunnelAgentCandidates(params.tunnel)) {
      if (!wsHub.isAgentOnline(agentId)) {
        continue;
      }
      if (!ensureTunnelOpenOnAgent(params.tunnel, agentId)) {
        continue;
      }
      try {
        const proxied = await wsHub.proxyHttpThroughAgent({
          agentId,
          tunnelId: params.tunnel.id,
          method: params.method,
          path: params.path,
          query: params.query,
          headers: params.headers,
          bodyBase64: params.bodyBase64
        });
        await persistTunnelAgent(params.tunnel, agentId);
        return proxied;
      } catch (error) {
        const message = error instanceof Error ? error.message : "proxy_failed";
        if (message === "agent_offline") {
          continue;
        }
        throw error;
      }
    }
    throw new Error("agent_offline");
  };

  const openTunnelWsThroughAvailableAgent = async (params: {
    tunnel: TunnelRecord;
    path: string;
    query?: string;
    headers?: Record<string, string>;
    bridge: {
      onFrame: (data: Buffer, isBinary: boolean) => void;
      onClosed: (code?: number, reason?: string) => void;
      onError: (error: string) => void;
    };
  }) => {
    for (const agentId of tunnelAgentCandidates(params.tunnel)) {
      if (!wsHub.isAgentOnline(agentId)) {
        continue;
      }
      if (!ensureTunnelOpenOnAgent(params.tunnel, agentId)) {
        continue;
      }
      try {
        const connectionId = await wsHub.openTunnelWsThroughAgent({
          agentId,
          tunnelId: params.tunnel.id,
          path: params.path,
          query: params.query,
          headers: params.headers,
          bridge: params.bridge
        });
        await persistTunnelAgent(params.tunnel, agentId);
        return connectionId;
      } catch (error) {
        const message = error instanceof Error ? error.message : "tunnel_ws_open_failed";
        if (message === "agent_offline") {
          continue;
        }
        throw error;
      }
    }
    throw new Error("agent_offline");
  };

  server.on("upgrade", (req, socket, head) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    const match = url.pathname.match(/^\/internal\/tunnels\/([^/]+)\/ws$/);
    if (!match) {
      return;
    }

    void (async () => {
      if (req.headers["x-gateway-secret"] !== config.gatewaySecret) {
        socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
        socket.destroy();
        return;
      }

      const slug = match[1] ?? "";
      const tunnel = await repositories.findTunnelBySlug(slug);
      if (!tunnel || tunnel.status !== "open") {
        socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
        socket.destroy();
        return;
      }

      if (tunnel.expires_at && tunnel.expires_at.getTime() <= Date.now()) {
        socket.write("HTTP/1.1 410 Gone\r\nConnection: close\r\n\r\n");
        socket.destroy();
        return;
      }

      const settings = await repositories.getWorkspaceDevSettings(tunnel.user_id, tunnel.workspace_id);
      const trustedDevMode = settings?.trusted_dev_mode === true;
      const token = (url.searchParams.get("nomade_token") ?? req.headers["x-nomade-token"] ?? "").toString();
      if (tunnel.token_required && !trustedDevMode) {
        if (!token || sha256(token) !== tunnel.access_token_hash) {
          socket.write("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
          socket.destroy();
          return;
        }
      }

      internalTunnelWsServer.handleUpgrade(req, socket, head, (ws) => {
        let connectionId: string | null = null;

        void openTunnelWsThroughAvailableAgent({
          tunnel,
          path: url.searchParams.get("path") ?? "/",
          query: url.searchParams.get("query") ?? undefined,
          headers: {
            origin: req.headers.origin?.toString() ?? ""
          },
          bridge: {
            onFrame: (data, isBinary) => {
              if (ws.readyState === ws.OPEN) {
                ws.send(data, { binary: isBinary });
              }
            },
            onClosed: (code, reason) => {
              closeWebSocketSafely(ws, code, reason);
            },
            onError: (error) => {
              if (ws.readyState === ws.OPEN || ws.readyState === ws.CONNECTING) {
                ws.close(1011, error.slice(0, 120));
              }
            }
          }
        })
          .then((openedConnectionId) => {
            connectionId = openedConnectionId;
          })
          .catch((error) => {
            if (ws.readyState === ws.OPEN || ws.readyState === ws.CONNECTING) {
              ws.close(1011, error instanceof Error ? error.message.slice(0, 120) : "tunnel_ws_open_failed");
            }
          });

        ws.on("message", (data, isBinary) => {
          if (!connectionId) {
            return;
          }
          const buffer = Buffer.isBuffer(data)
            ? data
            : Array.isArray(data)
              ? Buffer.concat(data.map((chunk) => Buffer.from(chunk)))
              : Buffer.from(data instanceof ArrayBuffer ? new Uint8Array(data) : data);
          wsHub.sendTunnelWsFrame({
            connectionId,
            data: buffer,
            isBinary
          });
        });

        ws.on("close", (code, reason) => {
          if (!connectionId) {
            return;
          }
          wsHub.closeTunnelWs({
            connectionId,
            code,
            reason: reason.toString()
          });
        });
      });
    })().catch(() => {
      socket.write("HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n");
      socket.destroy();
    });
  });

  const importThreadHistoryIntoConversation = async (params: {
    conversationId: string;
    agentId: string;
    threadId: string;
  }): Promise<void> => {
    const thread = await wsHub.readCodexThreadThroughAgent({
      agentId: params.agentId,
      threadId: params.threadId
    });

    await repositories.deleteConversationTurns(params.conversationId);
    for (const turn of thread.turns) {
      const userPrompt = turn.userPrompt.trim().length > 0 ? turn.userPrompt.trim() : "Imported turn";
      const createdTurn = await repositories.createConversationTurn({
        conversationId: params.conversationId,
        prompt: userPrompt
      });

      await repositories.markConversationTurnStarted({
        turnId: createdTurn.id,
        codexTurnId: turn.turnId
      });

      if (turn.status === "completed" || turn.status === "interrupted" || turn.status === "failed") {
        await repositories.completeConversationTurn({
          turnId: createdTurn.id,
          status: turn.status,
          error: turn.error
        });
      }

      for (const item of turn.items) {
        await repositories.addConversationItem({
          turnId: createdTurn.id,
          itemId: item.itemId,
          itemType: item.itemType,
          payload: item.payload
        });
      }
    }

    await repositories.updateConversationStatus(params.conversationId, "idle");
  };

  app.post("/auth/device/start", async (_req, res) => {
    const created = await auth.startDeviceCode();
    res.json({
      deviceCode: created.deviceCode,
      userCode: created.userCode,
      expiresAt: created.expiresAt.toISOString(),
      intervalSec: created.intervalSec
    });
  });

  app.post("/auth/device/approve", async (req, res) => {
    const schema = z.object({ userCode: z.string().min(4), email: z.string().email() });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const approved = await auth.approveDeviceCode(parsed.data);
    if (!approved) {
      res.status(404).json({ error: "invalid_or_expired_user_code" });
      return;
    }

    res.json({ approved: true });
  });

  app.post("/auth/device/poll", async (req, res) => {
    const schema = z.object({ deviceCode: z.string().min(10) });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const status = await auth.pollDeviceCode(parsed.data.deviceCode);
    if (status.status === "pending") {
      res.json({ status: "pending" });
      return;
    }
    if (status.status === "expired") {
      res.status(410).json({ status: "expired" });
      return;
    }

    res.json({
      status: "ok",
      accessToken: status.tokens.accessToken,
      refreshToken: status.tokens.refreshToken,
      expiresInSec: status.tokens.expiresInSec
    });
  });

  app.post("/auth/refresh", async (req, res) => {
    const schema = z.object({ refreshToken: z.string().min(8) });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const tokens = await auth.refresh(parsed.data.refreshToken);
    if (!tokens) {
      res.status(401).json({ error: "invalid_refresh_token" });
      return;
    }

    res.json(tokens);
  });

  app.post("/auth/logout", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({ refreshToken: z.string().min(8) });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    await repositories.revokeRefreshToken(parsed.data.refreshToken, req.userId!);
    res.json({ ok: true });
  });

  app.get("/me", requireUserAuth(auth), async (req, res) => {
    const me = await repositories.getUserById(req.userId!);
    if (!me) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    res.json(me);
  });

  app.post("/agents/pair", requireUserAuth(auth), async (req, res) => {
    const code = await repositories.createPairingCode(req.userId!, config.pairingCodeTtlSec);
    await repositories.writeAuditEvent({
      userId: req.userId!,
      actorType: "user",
      actorId: req.userId!,
      action: "agent.pairing_code.created",
      metadata: { ttlSec: config.pairingCodeTtlSec }
    });
    res.json({ pairingCode: code, expiresInSec: config.pairingCodeTtlSec });
  });

  app.post("/agents/register", async (req, res) => {
    const schema = z.object({ pairingCode: z.string().min(8), name: z.string().min(2).max(120) });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const consumed = await repositories.consumePairingCode(parsed.data.pairingCode);
    if (!consumed) {
      res.status(401).json({ error: "invalid_or_expired_pairing_code" });
      return;
    }

    const created = await repositories.createAgent(consumed.userId, parsed.data.name);
    await repositories.writeAuditEvent({
      userId: consumed.userId,
      actorType: "agent",
      actorId: created.agentId,
      action: "agent.registered",
      metadata: { name: parsed.data.name }
    });

    res.json(created);
  });

  app.get("/agents", requireUserAuth(auth), async (req, res) => {
    const now = Date.now();
    const rawAgents = await repositories.listAgents(req.userId!);
    const nameCounts = new Map<string, number>();
    for (const agent of rawAgents) {
      nameCounts.set(agent.name, (nameCounts.get(agent.name) ?? 0) + 1);
    }

    const agents = rawAgents
      .map((agent) => {
        const lastSeen = agent.last_seen_at;
        const isOnline = Boolean(lastSeen && now - lastSeen.getTime() <= agentOnlineWindowMs);
        const duplicate = (nameCounts.get(agent.name) ?? 0) > 1;
        const displayName = duplicate ? `${agent.name} (${agent.id.slice(0, 8)})` : agent.name;

        return {
          id: agent.id,
          name: agent.name,
          display_name: displayName,
          is_online: isOnline,
          last_seen_at: lastSeen ? lastSeen.toISOString() : null,
          created_at: agent.created_at.toISOString()
        };
      })
      .sort((a, b) => {
        if (a.is_online !== b.is_online) {
          return a.is_online ? -1 : 1;
        }
        const aLastSeen = a.last_seen_at ? Date.parse(a.last_seen_at) : 0;
        const bLastSeen = b.last_seen_at ? Date.parse(b.last_seen_at) : 0;
        if (aLastSeen !== bLastSeen) {
          return bLastSeen - aLastSeen;
        }
        return Date.parse(b.created_at) - Date.parse(a.created_at);
      });

    res.json({ items: agents });
  });

  app.post("/agents/:agentId/codex/import", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      limit: z.number().int().min(1).max(500).optional()
    });
    const parsed = schema.safeParse(req.body ?? {});
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const userId = req.userId!;
    const agentId = req.params.agentId;

    const agents = await repositories.listAgents(userId);
    if (!agents.some((agent) => agent.id === agentId)) {
      res.status(404).json({ error: "agent_not_found" });
      return;
    }

    let threads: Array<{
      threadId: string;
      title: string;
      preview: string;
      cwd: string;
      updatedAt: number;
    }> = [];

    try {
      threads = await wsHub.listCodexThreadsThroughAgent({
        agentId,
        limit: parsed.data.limit ?? 500
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "thread_list_failed";
      const status = message === "agent_offline" ? 409 : 502;
      res.status(status).json({ error: message });
      return;
    }

    const existingWorkspaces = await repositories.listWorkspaces(userId);
    const workspaceByPath = new Map<string, { id: string; name: string; path: string; agent_id: string }>();
    for (const workspace of existingWorkspaces) {
      if (workspace.agent_id === agentId) {
        workspaceByPath.set(workspace.path, workspace);
      }
    }

    const conversationByThreadId = new Map<string, string>();
    for (const workspace of workspaceByPath.values()) {
      const conversations = await repositories.listConversations(userId, workspace.id);
      for (const conversation of conversations) {
        if (conversation.codex_thread_id) {
          conversationByThreadId.set(conversation.codex_thread_id, conversation.id);
        }
      }
    }

    let importedWorkspaces = 0;
    let importedConversations = 0;
    let skippedConversations = 0;
    let hydratedOrRepaired = 0;

    for (const thread of threads) {
      const normalizedPath = thread.cwd.trim() || ".";
      let workspace = workspaceByPath.get(normalizedPath);

      if (!workspace) {
        const baseName = path.basename(normalizedPath) || "Workspace";
        workspace = await repositories.createWorkspace({
          userId,
          agentId,
          name: baseName.length > 120 ? `${baseName.substring(0, 120)}...` : baseName,
          path: normalizedPath
        });
        workspaceByPath.set(normalizedPath, workspace);
        importedWorkspaces += 1;
      }

      if (conversationByThreadId.has(thread.threadId)) {
        skippedConversations += 1;
        const existingConversationId = conversationByThreadId.get(thread.threadId);
        if (existingConversationId) {
          const existingTurns = await repositories.listConversationTurns(existingConversationId);
          const needsRepair = existingTurns.length === 0 || turnsNeedRepair(existingTurns);
          if (needsRepair) {
            try {
              await importThreadHistoryIntoConversation({
                conversationId: existingConversationId,
                agentId,
                threadId: thread.threadId
              });
              hydratedOrRepaired += 1;
            } catch (error) {
              const message = error instanceof Error ? error.message : "thread_hydration_failed";
              console.warn("[control-api] import repair skipped", existingConversationId, message);
            }
          }
        }
        continue;
      }

      const fallback = thread.preview
        .split("\n")
        .find((line) => line.trim().length > 0)
        ?.trim() ?? "Imported Codex thread";
      const rawTitle = thread.title.trim().length > 0 ? thread.title.trim() : fallback;
      const title = rawTitle.length > 240 ? `${rawTitle.substring(0, 240)}...` : rawTitle;

      const conversation = await repositories.createConversation({
        userId,
        workspaceId: workspace.id,
        agentId,
        title
      });
      await repositories.updateConversationThreadId(conversation.id, thread.threadId);
      await repositories.updateConversationStatus(conversation.id, "idle");
      wsHub.rememberConversationOwner(conversation.id, userId, agentId);

      conversationByThreadId.set(thread.threadId, conversation.id);
      importedConversations += 1;
    }

    res.json({
      threadsScanned: threads.length,
      importedWorkspaces,
      importedConversations,
      skippedConversations,
      hydratedOrRepaired,
      threads_scanned: threads.length,
      imported: importedConversations,
      skipped: skippedConversations,
      hydrated_or_repaired: hydratedOrRepaired
    });
  });

  app.get("/agents/:agentId/codex/options", requireUserAuth(auth), async (req, res) => {
    const userId = req.userId!;
    const agentId = req.params.agentId;
    const cwd = typeof req.query.cwd === "string" ? req.query.cwd.trim() : "";

    const agents = await repositories.listAgents(userId);
    if (!agents.some((agent) => agent.id === agentId)) {
      res.status(404).json({ error: "agent_not_found" });
      return;
    }

    try {
      const options = await wsHub.getCodexOptionsThroughAgent({
        agentId,
        cwd: cwd || undefined
      });
      res.json(options);
    } catch (error) {
      const message = error instanceof Error ? error.message : "codex_options_failed";
      const status = message === "agent_offline" ? 409 : 502;
      res.status(status).json({ error: message });
    }
  });

  app.post("/workspaces", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      agentId: z.string().uuid().or(z.string().min(10)),
      name: z.string().min(1).max(120),
      path: z.string().min(1)
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const workspace = await repositories.createWorkspace({
      userId: req.userId!,
      agentId: parsed.data.agentId,
      name: parsed.data.name,
      path: parsed.data.path
    });

    res.status(201).json(workspace);
  });

  app.get("/workspaces", requireUserAuth(auth), async (req, res) => {
    const agentId = typeof req.query.agentId === "string" ? req.query.agentId.trim() : "";
    const workspaces = await repositories.listWorkspaces(req.userId!, agentId || undefined);
    res.json({ items: workspaces });
  });

  app.get("/workspaces/:workspaceId/dev-settings", requireUserAuth(auth), async (req, res) => {
    const settings = await repositories.getWorkspaceDevSettings(req.userId!, req.params.workspaceId);
    if (!settings) {
      res.status(404).json({ error: "workspace_not_found" });
      return;
    }
    res.json({
      workspaceId: settings.workspace_id,
      trustedDevMode: settings.trusted_dev_mode,
      updatedAt: settings.updated_at.toISOString()
    });
  });

  app.patch("/workspaces/:workspaceId/dev-settings", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      trustedDevMode: z.boolean()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }
    const updated = await repositories.setWorkspaceDevSettings({
      userId: req.userId!,
      workspaceId: req.params.workspaceId,
      trustedDevMode: parsed.data.trustedDevMode
    });
    if (!updated) {
      res.status(404).json({ error: "workspace_not_found" });
      return;
    }
    res.json({
      workspaceId: updated.workspace_id,
      trustedDevMode: updated.trusted_dev_mode,
      updatedAt: updated.updated_at.toISOString()
    });
  });

  app.get("/workspaces/:workspaceId/services", requireUserAuth(auth), async (req, res) => {
    const items = await devServiceManager.listWorkspaceServices(req.userId!, req.params.workspaceId);
    if (!items) {
      res.status(404).json({ error: "workspace_not_found" });
      return;
    }
    res.json({ items });
  });

  app.post("/workspaces/:workspaceId/services", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      name: z.string().min(1).max(120),
      role: z.string().min(1).max(120).default("service"),
      command: z.string().min(1),
      cwd: z.string().optional(),
      port: z.number().int().min(1).max(65535),
      healthPath: z.string().optional(),
      envTemplate: z.record(z.string()).optional(),
      dependsOn: z.array(z.string()).optional(),
      autoTunnel: z.boolean().optional()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const workspace = await repositories.findWorkspaceById(req.userId!, req.params.workspaceId);
    if (!workspace) {
      res.status(404).json({ error: "workspace_not_found" });
      return;
    }

    try {
      const created = await repositories.createDevService({
        userId: req.userId!,
        workspaceId: workspace.id,
        agentId: workspace.agent_id,
        name: parsed.data.name,
        role: parsed.data.role,
        command: parsed.data.command,
        cwd: parsed.data.cwd,
        port: parsed.data.port,
        healthPath: parsed.data.healthPath,
        envTemplate: parsed.data.envTemplate,
        dependsOn: parsed.data.dependsOn,
        autoTunnel: parsed.data.autoTunnel
      });
      const state = await devServiceManager.getServiceState(req.userId!, created.id);
      res.status(201).json(state ?? created);
    } catch (error) {
      const message = error instanceof Error ? error.message : "service_create_failed";
      if (message.includes("duplicate key value")) {
        res.status(409).json({ error: "service_name_conflict" });
        return;
      }
      res.status(502).json({ error: message });
    }
  });

  app.patch("/services/:serviceId", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      name: z.string().min(1).max(120).optional(),
      role: z.string().min(1).max(120).optional(),
      command: z.string().min(1).optional(),
      cwd: z.string().nullable().optional(),
      port: z.number().int().min(1).max(65535).optional(),
      healthPath: z.string().optional(),
      envTemplate: z.record(z.string()).optional(),
      dependsOn: z.array(z.string()).optional(),
      autoTunnel: z.boolean().optional()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }
    const updated = await repositories.updateDevService({
      userId: req.userId!,
      serviceId: req.params.serviceId,
      name: parsed.data.name,
      role: parsed.data.role,
      command: parsed.data.command,
      cwd: parsed.data.cwd,
      port: parsed.data.port,
      healthPath: parsed.data.healthPath,
      envTemplate: parsed.data.envTemplate,
      dependsOn: parsed.data.dependsOn,
      autoTunnel: parsed.data.autoTunnel
    });
    if (!updated) {
      res.status(404).json({ error: "service_not_found" });
      return;
    }
    const state = await devServiceManager.getServiceState(req.userId!, updated.id);
    res.json(state ?? updated);
  });

  app.post("/services/:serviceId/start", requireUserAuth(auth), async (req, res) => {
    try {
      const state = await devServiceManager.startService(req.userId!, req.params.serviceId);
      if (!state) {
        res.status(404).json({ error: "service_not_found" });
        return;
      }
      res.json(state);
    } catch (error) {
      const message = error instanceof Error ? error.message : "service_start_failed";
      const status = message === "agent_offline" ? 503 : 502;
      res.status(status).json({ error: message });
    }
  });

  app.post("/services/:serviceId/stop", requireUserAuth(auth), async (req, res) => {
    const state = await devServiceManager.stopService(req.userId!, req.params.serviceId);
    if (!state) {
      res.status(404).json({ error: "service_not_found" });
      return;
    }
    res.json(state);
  });

  app.get("/services/:serviceId/state", requireUserAuth(auth), async (req, res) => {
    const state = await devServiceManager.getServiceState(req.userId!, req.params.serviceId);
    if (!state) {
      res.status(404).json({ error: "service_not_found" });
      return;
    }
    res.json(state);
  });

  app.post("/conversations", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      workspaceId: z.string().min(6),
      agentId: z.string().min(6).optional(),
      title: z.string().min(1).max(240).optional()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const workspace = await repositories.findWorkspaceById(req.userId!, parsed.data.workspaceId);
    if (!workspace) {
      res.status(404).json({ error: "workspace_not_found" });
      return;
    }

    const agentId = parsed.data.agentId ?? workspace.agent_id;
    const conversation = await repositories.createConversation({
      userId: req.userId!,
      workspaceId: parsed.data.workspaceId,
      agentId,
      title: parsed.data.title ?? "New conversation"
    });
    wsHub.rememberConversationOwner(conversation.id, req.userId!, agentId);

    res.status(201).json(conversation);
  });

  app.get("/conversations", requireUserAuth(auth), async (req, res) => {
    const workspaceId = String(req.query.workspaceId ?? "");
    if (!workspaceId) {
      res.status(400).json({ error: "workspace_id_required" });
      return;
    }

    const conversations = await repositories.listConversations(req.userId!, workspaceId);
    for (const conversation of conversations) {
      wsHub.rememberConversationOwner(conversation.id, req.userId!, conversation.agent_id);
    }
    res.json({ items: conversations });
  });

  app.get("/conversations/:conversationId/turns", requireUserAuth(auth), async (req, res) => {
    const conversation = await repositories.findConversation(req.userId!, req.params.conversationId);
    if (!conversation) {
      res.status(404).json({ error: "conversation_not_found" });
      return;
    }

    wsHub.rememberConversationOwner(conversation.id, req.userId!, conversation.agent_id);
    let turns = await repositories.listConversationTurns(conversation.id);
    const forceHydrate = isTruthyQuery(req.query.forceHydrate);
    const needsRepair = turnsNeedRepair(turns);
    const shouldHydrate = Boolean(
      conversation.codex_thread_id && (forceHydrate || turns.length === 0 || needsRepair)
    );
    const hydration = {
      attempted: false,
      repaired: false,
      deferred: false,
      reason: null as string | null
    };

    if (shouldHydrate && conversation.codex_thread_id) {
      hydration.attempted = true;
      try {
        await importThreadHistoryIntoConversation({
          conversationId: conversation.id,
          agentId: conversation.agent_id,
          threadId: conversation.codex_thread_id
        });
        turns = await repositories.listConversationTurns(conversation.id);
        hydration.repaired = true;
      } catch (error) {
        const message = error instanceof Error ? error.message : "thread_hydration_failed";
        hydration.deferred = true;
        hydration.reason = message;
        console.warn("[control-api] failed to hydrate thread history", conversation.id, message);
      }
    }

    for (const turn of turns) {
      wsHub.rememberConversationTurn(turn.id, conversation.id);
    }

    res.json({
      conversation,
      items: turns,
      hydration
    });
  });

  app.post("/conversations/:conversationId/turns", requireUserAuth(auth), async (req, res) => {
    const approvalPolicySchema = z.enum(["untrusted", "on-failure", "on-request", "never"]);
    const sandboxModeSchema = z.enum(["read-only", "workspace-write", "danger-full-access"]);
    const reasoningEffortSchema = z.enum(["none", "minimal", "low", "medium", "high", "xhigh"]);
    const inputItemSchema = z.discriminatedUnion("type", [
      z.object({
        type: z.literal("text"),
        text: z.string().min(1)
      }),
      z.object({
        type: z.literal("image"),
        imageUrl: z.string().min(1),
        detail: z.string().min(1).optional()
      }),
      z.object({
        type: z.literal("local_image"),
        path: z.string().min(1)
      }),
      z.object({
        type: z.literal("skill"),
        path: z.string().min(1),
        name: z.string().min(1).optional()
      }),
      z.object({
        type: z.literal("mention"),
        path: z.string().min(1),
        name: z.string().min(1).optional()
      })
    ]);

    const schema = z.object({
      prompt: z.string().min(1).optional(),
      inputItems: z.array(inputItemSchema).min(1).optional(),
      collaborationMode: z.record(z.unknown()).optional(),
      model: z.string().min(1).max(120).optional(),
      cwd: z.string().min(1).optional(),
      approvalPolicy: approvalPolicySchema.optional(),
      sandboxMode: sandboxModeSchema.optional(),
      effort: reasoningEffortSchema.optional()
    }).refine((body) => Boolean(body.prompt || body.inputItems), {
      message: "Either prompt or inputItems is required",
      path: ["prompt"]
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const conversation = await repositories.findConversation(req.userId!, req.params.conversationId);
    if (!conversation) {
      res.status(404).json({ error: "conversation_not_found" });
      return;
    }

    const workspace = await repositories.findWorkspaceById(req.userId!, conversation.workspace_id);
    const prompt = parsed.data.prompt?.trim();
    const inputItems = parsed.data.inputItems as Array<Record<string, unknown>> | undefined;
    const userPrompt = prompt && prompt.length > 0 ? prompt : derivePromptFromInputItems(inputItems ?? []);
    const turn = await repositories.createConversationTurn({
      conversationId: conversation.id,
      prompt: userPrompt
    });

    wsHub.rememberConversationOwner(conversation.id, req.userId!, conversation.agent_id);
    wsHub.rememberConversationTurn(turn.id, conversation.id);

    const delivered = wsHub.sendToAgent(conversation.agent_id, {
      type: "conversation.turn.start",
      conversationId: conversation.id,
      turnId: turn.id,
      threadId: conversation.codex_thread_id ?? undefined,
      prompt: prompt,
      inputItems,
      collaborationMode: parsed.data.collaborationMode,
      model: parsed.data.model,
      cwd: parsed.data.cwd ?? workspace?.path,
      approvalPolicy: parsed.data.approvalPolicy,
      sandboxMode: parsed.data.sandboxMode,
      effort: parsed.data.effort
    });

    if (!delivered) {
      await repositories.completeConversationTurn({
        turnId: turn.id,
        status: "failed",
        error: "agent_offline"
      });
      await repositories.updateConversationStatus(conversation.id, "failed");
      res.status(503).json({ error: "agent_offline" });
      return;
    }

    await repositories.updateConversationStatus(conversation.id, "running");
    res.status(201).json(turn);
  });

  app.post("/conversations/:conversationId/turns/:turnId/interrupt", requireUserAuth(auth), async (req, res) => {
    const conversation = await repositories.findConversation(req.userId!, req.params.conversationId);
    if (!conversation) {
      res.status(404).json({ error: "conversation_not_found" });
      return;
    }

    const turn = await repositories.findConversationTurn(req.params.turnId);
    if (!turn || turn.conversation_id !== conversation.id) {
      res.status(404).json({ error: "turn_not_found" });
      return;
    }

    wsHub.rememberConversationOwner(conversation.id, req.userId!, conversation.agent_id);
    wsHub.rememberConversationTurn(turn.id, conversation.id);

    const delivered = wsHub.sendToAgent(conversation.agent_id, {
      type: "conversation.turn.interrupt",
      conversationId: conversation.id,
      turnId: turn.id,
      threadId: conversation.codex_thread_id ?? undefined
    });
    if (!delivered) {
      res.status(503).json({ error: "agent_offline" });
      return;
    }

    res.json({ accepted: true });
  });

  app.post("/sessions", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      workspaceId: z.string().min(6),
      agentId: z.string().min(6),
      name: z.string().min(1).max(120),
      command: z.string().min(1),
      cwd: z.string().optional(),
      env: z.record(z.string()).optional()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const session = await repositories.createSession({
      userId: req.userId!,
      workspaceId: parsed.data.workspaceId,
      agentId: parsed.data.agentId,
      name: parsed.data.name
    });

    wsHub.rememberSessionOwner(session.id, req.userId!, parsed.data.agentId);
    const delivered = wsHub.sendToAgent(parsed.data.agentId, {
      type: "session.create",
      sessionId: session.id,
      workspaceId: parsed.data.workspaceId,
      agentId: parsed.data.agentId,
      command: parsed.data.command,
      cwd: parsed.data.cwd,
      env: parsed.data.env
    });

    if (!delivered) {
      await repositories.updateSessionStatus(session.id, "failed");
      res.status(503).json({ error: "agent_offline" });
      return;
    }

    res.status(201).json(session);
  });

  app.get("/sessions", requireUserAuth(auth), async (req, res) => {
    const workspaceId = String(req.query.workspaceId ?? "");
    if (!workspaceId) {
      res.status(400).json({ error: "workspace_id_required" });
      return;
    }
    const sessions = await repositories.listSessions(req.userId!, workspaceId);
    for (const session of sessions) {
      wsHub.rememberSessionOwner(session.id, req.userId!, session.agent_id);
    }
    res.json({ items: sessions });
  });

  app.post("/tunnels", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      workspaceId: z.string().min(6),
      agentId: z.string().min(6),
      targetPort: z.number().int().min(1).max(65535),
      serviceId: z.string().min(6).optional(),
      ttlSec: z.number().int().min(60).max(60 * 60 * 24).optional()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const workspace = await repositories.findWorkspaceById(req.userId!, parsed.data.workspaceId);
    if (!workspace) {
      res.status(404).json({ error: "workspace_not_found" });
      return;
    }

    const settings = await repositories.getWorkspaceDevSettings(req.userId!, parsed.data.workspaceId);
    const tokenRequired = !(settings?.trusted_dev_mode ?? false);

    const created = await repositories.createTunnel({
      userId: req.userId!,
      workspaceId: parsed.data.workspaceId,
      agentId: parsed.data.agentId,
      serviceId: parsed.data.serviceId ?? null,
      targetPort: parsed.data.targetPort,
      tokenRequired,
      ttlSec: parsed.data.ttlSec
    });

    wsHub.rememberTunnelOwner(created.tunnel.id, req.userId!);

    const delivered = wsHub.sendToAgent(parsed.data.agentId, {
      type: "tunnel.open",
      tunnelId: created.tunnel.id,
      slug: created.tunnel.slug,
      targetPort: created.tunnel.target_port
    });

    if (!delivered) {
      await repositories.deleteTunnel(created.tunnel.id, req.userId!);
      res.status(503).json({ error: "agent_offline" });
      return;
    }

    res.status(201).json({
      id: created.tunnel.id,
      slug: created.tunnel.slug,
      serviceId: created.tunnel.service_id,
      targetPort: created.tunnel.target_port,
      tokenRequired: created.tunnel.token_required,
      previewUrl: renderPreviewUrl({
        slug: created.tunnel.slug,
        tokenRequired: created.tunnel.token_required,
        token: created.accessToken
      }),
      accessToken: created.accessToken,
      isReachable: false,
      lastProbeAt: null,
      lastProbeStatus: null,
      lastError: null,
      diagnostic: getTunnelDiagnostic(created.tunnel.id)
    });
  });

  app.get("/tunnels", requireUserAuth(auth), async (req, res) => {
    const workspaceId = String(req.query.workspaceId ?? "");
    if (!workspaceId) {
      res.status(400).json({ error: "workspace_id_required" });
      return;
    }

    const tunnels = await repositories.listTunnels(req.userId!, workspaceId);
    res.json({
      items: tunnels.map((tunnel) => ({
        id: tunnel.id,
        serviceId: tunnel.service_id,
        slug: tunnel.slug,
        targetPort: tunnel.target_port,
        status: tunnel.status,
        tokenRequired: tunnel.token_required,
        previewUrl: previewOriginFor(tunnel.slug),
        isReachable: tunnel.last_probe_status === "ok",
        lastProbeAt: tunnel.last_probe_at ? tunnel.last_probe_at.toISOString() : null,
        lastProbeStatus: tunnel.last_probe_status ?? null,
        lastError: tunnel.last_probe_error ?? null,
        lastProbeCode: tunnel.last_probe_code ?? null,
        diagnostic: getTunnelDiagnostic(tunnel.id)
      }))
    });
  });

  app.post("/tunnels/:tunnelId/issue-token", requireUserAuth(auth), async (req, res) => {
    const issued = await devServiceManager.issueTunnelToken(req.userId!, req.params.tunnelId);
    if (!issued) {
      res.status(404).json({ error: "tunnel_not_found" });
      return;
    }
    res.json({
      accessToken: issued.token,
      previewUrl: issued.previewUrl
    });
  });

  app.post("/tunnels/:tunnelId/rotate-token", requireUserAuth(auth), async (req, res) => {
    const issued = await devServiceManager.rotateTunnelToken(req.userId!, req.params.tunnelId);
    if (!issued) {
      res.status(404).json({ error: "tunnel_not_found" });
      return;
    }
    res.json({
      accessToken: issued.token,
      previewUrl: issued.previewUrl
    });
  });

  app.delete("/tunnels/:tunnelId", requireUserAuth(auth), async (req, res) => {
    const deleted = await devServiceManager.closeTunnel(req.userId!, req.params.tunnelId);
    if (!deleted) {
      res.status(404).json({ error: "tunnel_not_found" });
      return;
    }
    res.json({ ok: true });
  });

  app.post("/internal/tunnels/:slug/proxy", async (req, res) => {
    if (req.header("x-gateway-secret") !== config.gatewaySecret) {
      res.status(401).json({ error: "unauthorized_gateway" });
      return;
    }

    const schema = z.object({
      method: z.string().min(1),
      path: z.string().min(1),
      query: z.string().optional(),
      headers: z.record(z.string()),
      bodyBase64: z.string().optional(),
      token: z.string().optional()
    });

    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const tunnel = await repositories.findTunnelBySlug(req.params.slug);
    if (!tunnel || tunnel.status !== "open") {
      res.status(404).json({ error: "tunnel_not_found" });
      return;
    }

    if (tunnel.expires_at && tunnel.expires_at.getTime() <= Date.now()) {
      res.status(410).json({ error: "tunnel_expired" });
      return;
    }

    const settings = await repositories.getWorkspaceDevSettings(tunnel.user_id, tunnel.workspace_id);
    const trustedDevMode = settings?.trusted_dev_mode === true;
    if (tunnel.token_required && !trustedDevMode) {
      const token = (parsed.data.token ?? "").trim();
      if (!token || sha256(token) !== tunnel.access_token_hash) {
        res.status(403).json({ error: "invalid_tunnel_token" });
        return;
      }
    }

    try {
      const proxied = await proxyTunnelThroughAvailableAgent({
        tunnel,
        method: parsed.data.method,
        path: parsed.data.path,
        query: parsed.data.query,
        headers: parsed.data.headers,
        bodyBase64: parsed.data.bodyBase64
      });

      const upstreamAppDiagnostic = classifyProxyResponseDiagnostic({
        request: {
          path: parsed.data.path,
          query: parsed.data.query
        },
        response: {
          headers: proxied.headers
        }
      });
      if (upstreamAppDiagnostic) {
        updateTunnelDiagnostic({
          tunnel,
          diagnostic: upstreamAppDiagnostic,
          detail: upstreamAppDiagnostic.message
        });
      } else {
        const existing = getTunnelDiagnostic(tunnel.id);
        if (existing?.scope === "transport" || existing?.code === "vite_svg_react_not_transformed") {
          updateTunnelDiagnostic({
            tunnel,
            diagnostic: null,
            detail: "Tunnel diagnostic cleared after successful proxy response"
          });
        }
      }

      // This endpoint relays the local app response; drop control-api helmet headers
      // so they do not override frontend dev-server CSP/HMR behavior.
      clearSecurityHeadersForProxiedResponse(res);
      res.status(proxied.status);
      for (const [key, value] of Object.entries(proxied.headers)) {
        if (key.toLowerCase() === "transfer-encoding") {
          continue;
        }
        res.setHeader(key, value);
      }
      const body = Buffer.from(proxied.bodyBase64 ?? "", "base64");
      res.send(body);
    } catch (error) {
      const message = error instanceof Error ? error.message : "proxy_failed";
      const transportDiagnostic = buildTransportTunnelDiagnostic({ rawError: message });
      updateTunnelDiagnostic({
        tunnel,
        diagnostic: transportDiagnostic,
        detail: transportDiagnostic.message
      });
      res.status(502).json({ error: message });
    }
  });

  return server;
};
