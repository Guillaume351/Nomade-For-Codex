import http from "node:http";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { z } from "zod";
import { sha256 } from "@nomade/shared";
import { loadConfig } from "./config.js";
import { createPool, ensureSchema } from "./db.js";
import { Repositories } from "./repositories.js";
import { AuthService } from "./auth.js";
import { requireUserAuth } from "./http-auth.js";
import { WsHub } from "./ws-hub.js";

const jsonLimit = "2mb";

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
    const agents = await repositories.listAgents(req.userId!);
    res.json({ items: agents });
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
    const workspaces = await repositories.listWorkspaces(req.userId!);
    res.json({ items: workspaces });
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
    const turns = await repositories.listConversationTurns(conversation.id);
    for (const turn of turns) {
      wsHub.rememberConversationTurn(turn.id, conversation.id);
    }

    res.json({
      conversation,
      items: turns
    });
  });

  app.post("/conversations/:conversationId/turns", requireUserAuth(auth), async (req, res) => {
    const schema = z.object({
      prompt: z.string().min(1),
      model: z.string().min(1).max(120).optional(),
      cwd: z.string().min(1).optional()
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
    const turn = await repositories.createConversationTurn({
      conversationId: conversation.id,
      prompt: parsed.data.prompt
    });

    wsHub.rememberConversationOwner(conversation.id, req.userId!, conversation.agent_id);
    wsHub.rememberConversationTurn(turn.id, conversation.id);

    const delivered = wsHub.sendToAgent(conversation.agent_id, {
      type: "conversation.turn.start",
      conversationId: conversation.id,
      turnId: turn.id,
      threadId: conversation.codex_thread_id ?? undefined,
      prompt: parsed.data.prompt,
      model: parsed.data.model,
      cwd: parsed.data.cwd ?? workspace?.path
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
      cwd: z.string().optional()
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
      cwd: parsed.data.cwd
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
      ttlSec: z.number().int().min(60).max(60 * 60 * 24).optional()
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
      return;
    }

    const created = await repositories.createTunnel({
      userId: req.userId!,
      workspaceId: parsed.data.workspaceId,
      agentId: parsed.data.agentId,
      targetPort: parsed.data.targetPort,
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
      res.status(503).json({ error: "agent_offline" });
      return;
    }

    res.status(201).json({
      id: created.tunnel.id,
      slug: created.tunnel.slug,
      targetPort: created.tunnel.target_port,
      previewUrl: `https://${created.tunnel.slug}.${config.previewBaseDomain}`,
      accessToken: created.accessToken
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
        slug: tunnel.slug,
        targetPort: tunnel.target_port,
        status: tunnel.status,
        previewUrl: `https://${tunnel.slug}.${config.previewBaseDomain}`
      }))
    });
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
      token: z.string().min(8)
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

    if (sha256(parsed.data.token) !== tunnel.access_token_hash) {
      res.status(403).json({ error: "invalid_tunnel_token" });
      return;
    }

    try {
      const proxied = await wsHub.proxyHttpThroughAgent({
        agentId: tunnel.agent_id,
        tunnelId: tunnel.id,
        method: parsed.data.method,
        path: parsed.data.path,
        query: parsed.data.query,
        headers: parsed.data.headers,
        bodyBase64: parsed.data.bodyBase64
      });

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
      res.status(502).json({ error: message });
    }
  });

  return server;
};
