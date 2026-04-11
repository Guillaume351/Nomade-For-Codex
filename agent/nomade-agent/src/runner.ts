import WebSocket from "ws";
import { createHash } from "node:crypto";
import { randomToken } from "@nomade/shared";
import {
  defaultConfigPath,
  defaultSessionPath,
  readConfig,
  readUserSession,
  writeUserSession,
  type UserSessionConfig
} from "./config.js";
import { SessionManager } from "./session-manager.js";
import { TunnelManager } from "./tunnel-manager.js";
import { ConversationManager } from "./conversation-manager.js";
import { createE2ERuntime } from "./e2e-runtime.js";

interface RunArgs {
  configPath?: string;
}

const loopbackHosts = ["127.0.0.1", "localhost", "[::1]"] as const;
const loopbackConnectivityCodes = new Set([
  "ECONNREFUSED",
  "ECONNRESET",
  "EHOSTUNREACH",
  "ENETUNREACH",
  "ENOTFOUND"
]);

const extractNetworkCodeFromError = (error: unknown): string | undefined => {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  const errorRecord = error as Record<string, unknown>;
  if (typeof errorRecord.code === "string" && errorRecord.code.trim().length > 0) {
    return errorRecord.code.trim().toUpperCase();
  }
  const cause = errorRecord.cause;
  if (cause && typeof cause === "object") {
    const causeCode = (cause as Record<string, unknown>).code;
    if (typeof causeCode === "string" && causeCode.trim().length > 0) {
      return causeCode.trim().toUpperCase();
    }
  }
  return undefined;
};

const hasLoopbackConnectivityPattern = (input: string): boolean => {
  return /\b(ECONNREFUSED|ECONNRESET|EHOSTUNREACH|ENETUNREACH|ENOTFOUND)\b/i.test(input);
};

export const normalizeTunnelHttpProxyError = (entries: Array<{ message: string; code?: string }>): string => {
  for (const entry of entries) {
    const normalizedCode = entry.code?.toUpperCase();
    if (normalizedCode && loopbackConnectivityCodes.has(normalizedCode)) {
      return "local_service_unreachable";
    }
    if (hasLoopbackConnectivityPattern(entry.message)) {
      return "local_service_unreachable";
    }
  }
  return "local_fetch_failed";
};

export const normalizeTunnelWsOpenError = (entries: Array<{ message: string; code?: string }>): string => {
  for (const entry of entries) {
    const match = /\btunnel_ws_unexpected_response_(\d{3})\b/i.exec(entry.message);
    if (match && match[1]) {
      return `tunnel_ws_unexpected_response_${match[1]}`;
    }
  }
  for (const entry of entries) {
    if (/\btunnel_ws_open_timeout\b/i.test(entry.message)) {
      return "tunnel_ws_open_timeout";
    }
  }
  for (const entry of entries) {
    if (/\btunnel_ws_closed_before_open\b/i.test(entry.message)) {
      return "tunnel_ws_closed_before_open";
    }
  }
  for (const entry of entries) {
    const normalizedCode = entry.code?.toUpperCase();
    if (normalizedCode && loopbackConnectivityCodes.has(normalizedCode)) {
      return "local_service_unreachable";
    }
    if (hasLoopbackConnectivityPattern(entry.message)) {
      return "local_service_unreachable";
    }
  }
  return "tunnel_ws_open_failed";
};

const buildLocalHttpUrl = (host: string, targetPort: number, path: string, query?: string): string => {
  const q = query ? `?${query}` : "";
  return `http://${host}:${targetPort}${path}${q}`;
};

const buildLocalWsUrl = (host: string, targetPort: number, path: string, query?: string): string => {
  const q = query ? `?${query}` : "";
  return `ws://${host}:${targetPort}${path}${q}`;
};

const parseEnvelope = (value: unknown):
  | {
      v: 1;
      alg: "xchacha20poly1305";
      epoch: number;
      senderDeviceId: string;
      seq: number;
      nonce: string;
      aad: string;
      ciphertext: string;
      sig: string;
    }
  | null => {
  if (!value || typeof value !== "object") {
    return null;
  }
  const raw = value as Record<string, unknown>;
  if (
    raw.v !== 1 ||
    raw.alg !== "xchacha20poly1305" ||
    typeof raw.epoch !== "number" ||
    typeof raw.senderDeviceId !== "string" ||
    typeof raw.seq !== "number" ||
    typeof raw.nonce !== "string" ||
    typeof raw.aad !== "string" ||
    typeof raw.ciphertext !== "string" ||
    typeof raw.sig !== "string"
  ) {
    return null;
  }
  return {
    v: 1,
    alg: "xchacha20poly1305",
    epoch: raw.epoch,
    senderDeviceId: raw.senderDeviceId,
    seq: raw.seq,
    nonce: raw.nonce,
    aad: raw.aad,
    ciphertext: raw.ciphertext,
    sig: raw.sig
  };
};

const hashFingerprint = (value: string): string => {
  return createHash("sha256").update(value).digest("hex").slice(0, 12);
};

export const normalizeE2EDecryptErrorCode = (error: unknown): string => {
  const message = error instanceof Error ? error.message : String(error ?? "e2e_decrypt_failed");
  const lowered = message.toLowerCase();
  if (lowered.includes("invalid tag")) {
    return "e2e_key_mismatch_or_corrupted_payload";
  }
  if (lowered.includes("e2e_replay_detected")) {
    return "e2e_replay_detected";
  }
  if (lowered.includes("e2e_unknown_sender_device")) {
    return "e2e_unknown_sender_device";
  }
  if (lowered.includes("e2e_invalid_signature")) {
    return "e2e_invalid_signature";
  }
  if (lowered.includes("e2e_")) {
    return lowered.replace(/[^a-z0-9_.:-]/g, "_").slice(0, 96);
  }
  return "e2e_decrypt_failed";
};

const enrichConversationEventWithE2E = (
  payload: Record<string, unknown>,
  e2eRuntime: ReturnType<typeof createE2ERuntime>
): Record<string, unknown> => {
  if (!e2eRuntime) {
    return payload;
  }
  const type = typeof payload.type === "string" ? payload.type : "";
  if (!type.startsWith("conversation.")) {
    return payload;
  }
  const conversationId = typeof payload.conversationId === "string" ? payload.conversationId : "";
  if (!conversationId) {
    return payload;
  }
  const scope = `conversation:${conversationId}`;

  if (type === "conversation.turn.diff.updated" && typeof payload.diff === "string" && payload.diff.length > 0) {
    return {
      ...payload,
      e2eEnvelope: e2eRuntime.encrypt(scope, JSON.stringify({ diff: payload.diff }))
    };
  }

  if ((type === "conversation.item.started" || type === "conversation.item.completed") && payload.item) {
    return {
      ...payload,
      e2eEnvelope: e2eRuntime.encrypt(scope, JSON.stringify({ item: payload.item }))
    };
  }

  if (type === "conversation.item.delta" && typeof payload.delta === "string") {
    return {
      ...payload,
      e2eEnvelope: e2eRuntime.encrypt(
        scope,
        JSON.stringify({ delta: payload.delta, stream: typeof payload.stream === "string" ? payload.stream : undefined })
      )
    };
  }

  if (type === "conversation.turn.plan.updated" && payload.plan) {
    return {
      ...payload,
      e2eEnvelope: e2eRuntime.encrypt(scope, JSON.stringify({ plan: payload.plan }))
    };
  }

  if (type === "conversation.server.request" && payload.params) {
    return {
      ...payload,
      e2eEnvelope: e2eRuntime.encrypt(scope, JSON.stringify({ params: payload.params }))
    };
  }

  if (type === "conversation.server.request.resolved") {
    return {
      ...payload,
      e2eEnvelope: e2eRuntime.encrypt(
        scope,
        JSON.stringify({
          status: payload.status,
          result: payload.result,
          error: payload.error
        })
      )
    };
  }

  return payload;
};

const proxyLocalHttpWithFallback = async (params: {
  targetPort: number;
  method: string;
  path: string;
  query?: string;
  headers: Record<string, string>;
  body?: Buffer;
}): Promise<Response> => {
  const errors: Array<{ message: string; code?: string }> = [];
  for (const host of loopbackHosts) {
    const localUrl = buildLocalHttpUrl(host, params.targetPort, params.path, params.query);
    try {
      return await fetch(localUrl, {
        method: params.method,
        headers: params.headers,
        body: params.body && params.body.length ? new Uint8Array(params.body) : undefined
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "local_fetch_failed";
      const code = extractNetworkCodeFromError(error);
      errors.push({ message: `${host}:${message}`, code });
    }
  }
  throw new Error(normalizeTunnelHttpProxyError(errors));
};

const connectLocalWebSocket = (url: string, headers: Record<string, string>): Promise<WebSocket> => {
  return new Promise<WebSocket>((resolve, reject) => {
    const socket = new WebSocket(url, { headers });
    // Keep at least one error listener to avoid unhandled ws errors during races.
    socket.on("error", () => {
      // no-op
    });
    let settled = false;
    let timeout: NodeJS.Timeout | null = null;

    const cleanup = (): void => {
      if (timeout) {
        clearTimeout(timeout);
        timeout = null;
      }
      socket.off("open", onOpen);
      socket.off("error", onError);
      socket.off("close", onClose);
      socket.off("unexpected-response", onUnexpectedResponse);
    };

    const settle = (fn: () => void): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      fn();
    };

    const onOpen = (): void => {
      settle(() => resolve(socket));
    };

    const onError = (error: Error): void => {
      settle(() => reject(error));
    };

    const onClose = (): void => {
      settle(() => reject(new Error("tunnel_ws_closed_before_open")));
    };

    const onUnexpectedResponse = (_request: unknown, response: import("http").IncomingMessage): void => {
      const status = response.statusCode ?? 0;
      settle(() => reject(new Error(`tunnel_ws_unexpected_response_${status}`)));
    };

    socket.on("open", onOpen);
    socket.on("error", onError);
    socket.on("close", onClose);
    socket.on("unexpected-response", onUnexpectedResponse);
    timeout = setTimeout(() => {
      settle(() => reject(new Error("tunnel_ws_open_timeout")));
    }, 3_000);
  });
};

const openLocalWsWithFallback = async (params: {
  targetPort: number;
  path: string;
  query?: string;
  headers: Record<string, string>;
}): Promise<WebSocket> => {
  const errors: Array<{ message: string; code?: string }> = [];
  for (const host of loopbackHosts) {
    const localWsUrl = buildLocalWsUrl(host, params.targetPort, params.path, params.query);
    try {
      return await connectLocalWebSocket(localWsUrl, params.headers);
    } catch (error) {
      const message = error instanceof Error ? error.message : "tunnel_ws_open_failed";
      const code = extractNetworkCodeFromError(error);
      errors.push({ message: `${host}:${message}`, code });
    }
  }
  throw new Error(normalizeTunnelWsOpenError(errors));
};

export const runAgent = async (args: RunArgs): Promise<void> => {
  const config = await readConfig(args.configPath ?? defaultConfigPath());
  const sessionPath = defaultSessionPath();
  const tunnelManager = new TunnelManager();
  let e2eRuntime: ReturnType<typeof createE2ERuntime> = null;
  let sessionForPersistence: UserSessionConfig | null = null;
  let e2eDebug:
    | {
        epoch: number;
        selfDeviceId: string;
        peers: number;
        rootKeyFp: string;
      }
    | null = null;
  try {
    const session = await readUserSession(sessionPath);
    if (session.controlHttpUrl.replace(/\/$/, "") === config.controlHttpUrl.replace(/\/$/, "")) {
      e2eRuntime = createE2ERuntime(session.e2e);
      if (session.e2e && e2eRuntime) {
        sessionForPersistence = session;
      }
      if (session.e2e) {
        e2eDebug = {
          epoch: Math.max(1, Number(session.e2e.epoch ?? 1)),
          selfDeviceId: session.e2e.device.deviceId,
          peers: Object.keys(session.e2e.peers ?? {}).length,
          rootKeyFp: hashFingerprint(session.e2e.rootKey)
        };
      }
    }
  } catch {
    // no-op
  }

  const wsUrl = `${config.controlWsUrl}?agent_token=${encodeURIComponent(config.agentToken)}`;
  const ws = new WebSocket(wsUrl);
  const sendToControl = (payload: Record<string, unknown>): void => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify(payload));
    }
  };
  const sameSeqByScope = (
    left: Record<string, number> | undefined,
    right: Record<string, number>
  ): boolean => {
    const leftEntries = Object.entries(left ?? {});
    const rightEntries = Object.entries(right);
    if (leftEntries.length !== rightEntries.length) {
      return false;
    }
    for (const [scope, seq] of rightEntries) {
      if ((left ?? {})[scope] !== seq) {
        return false;
      }
    }
    return true;
  };
  let persistSeqTimer: NodeJS.Timeout | null = null;
  let persistSeqInFlight = false;
  let persistSeqQueued = false;
  const flushPersistedSeqByScope = async (): Promise<void> => {
    if (!e2eRuntime || !sessionForPersistence?.e2e) {
      return;
    }
    if (persistSeqInFlight) {
      persistSeqQueued = true;
      return;
    }
    persistSeqInFlight = true;
    try {
      const nextSeqByScope = e2eRuntime.exportSeqByScope();
      if (sameSeqByScope(sessionForPersistence.e2e.seqByScope, nextSeqByScope)) {
        return;
      }
      sessionForPersistence = {
        ...sessionForPersistence,
        e2e: {
          ...sessionForPersistence.e2e,
          seqByScope: nextSeqByScope
        }
      };
      await writeUserSession(sessionPath, sessionForPersistence);
    } catch (error) {
      console.error("[agent] failed to persist e2e seq state", error);
    } finally {
      persistSeqInFlight = false;
      if (persistSeqQueued) {
        persistSeqQueued = false;
        schedulePersistSeqByScope();
      }
    }
  };
  const schedulePersistSeqByScope = (): void => {
    if (!e2eRuntime || !sessionForPersistence?.e2e) {
      return;
    }
    if (persistSeqTimer) {
      return;
    }
    persistSeqTimer = setTimeout(() => {
      persistSeqTimer = null;
      void flushPersistedSeqByScope();
    }, 300);
  };
  const reportE2EDecryptFailure = (params: {
    context: string;
    error: unknown;
    envelope: ReturnType<typeof parseEnvelope> | null;
    conversationId?: string;
    turnId?: string;
    requestId?: string;
    failTurn?: boolean;
  }): void => {
    const code = normalizeE2EDecryptErrorCode(params.error);
    const details = {
      context: params.context,
      code,
      conversationId: params.conversationId ?? "",
      turnId: params.turnId ?? "",
      requestId: params.requestId ?? "",
      envelopeSender: params.envelope?.senderDeviceId ?? "",
      envelopeEpoch: params.envelope?.epoch ?? "",
      envelopeSeq: params.envelope?.seq ?? "",
      e2e: e2eDebug
    };
    console.error("[agent] e2e decrypt failed", details, params.error);
    sendToControl({
      type: "error",
      code,
      message: `${params.context}: ${code}. Re-login with secure scan on mobile and agent.`
    });
    if (params.failTurn && params.conversationId && params.turnId) {
      sendToControl({
        type: "conversation.turn.completed",
        conversationId: params.conversationId,
        turnId: params.turnId,
        threadId: "",
        codexTurnId: "",
        status: "failed",
        error: code
      });
    }
  };
  const conversationManager = new ConversationManager((payload) => {
    const enriched = enrichConversationEventWithE2E(payload, e2eRuntime);
    sendToControl(enriched);
    if (enriched !== payload) {
      schedulePersistSeqByScope();
    }
  });

  const sessionManager = new SessionManager({
    onOutput: (sessionId, stream, data, cursor) => {
      const e2eEnvelope =
        e2eRuntime && data.length > 0 ? e2eRuntime.encrypt(`session:${sessionId}`, data) : undefined;
      if (e2eEnvelope) {
        schedulePersistSeqByScope();
      }
      ws.send(
        JSON.stringify({
          type: "session.output",
          sessionId,
          stream,
          data,
          cursor,
          e2eEnvelope
        })
      );
    },
    onStatus: (sessionId, status, exitCode) => {
      ws.send(
        JSON.stringify({
          type: "session.status",
          sessionId,
          status,
          exitCode
        })
      );
    }
  });

  ws.on("open", () => {
    console.log("[agent] connected");
    if (e2eRuntime) {
      console.log("[agent] e2e runtime enabled");
      if (e2eDebug) {
        console.log(
          `[agent] e2e session epoch=${e2eDebug.epoch} self=${e2eDebug.selfDeviceId} peers=${e2eDebug.peers} rootKeyFp=${e2eDebug.rootKeyFp}`
        );
      }
    }
    ws.send(JSON.stringify({ type: "agent.hello", agentId: config.agentId, name: config.name }));

    setInterval(() => {
      if (ws.readyState === ws.OPEN) {
        ws.send(JSON.stringify({ type: "agent.heartbeat", agentId: config.agentId }));
      }
    }, 10_000);
  });

  ws.on("message", async (raw) => {
    try {
      const msg = JSON.parse(raw.toString()) as Record<string, unknown>;
      const type = String(msg.type ?? "");
      if (type === "session.create") {
        const envRaw = msg.env;
        const env =
          envRaw && typeof envRaw === "object"
            ? Object.fromEntries(
                Object.entries(envRaw as Record<string, unknown>).map(([key, value]) => [key, String(value ?? "")])
              )
            : undefined;
        const sessionId = String(msg.sessionId ?? "");
        let command = String(msg.command ?? "");
        const e2eCommandEnvelope = parseEnvelope(msg.e2eCommandEnvelope);
        if (e2eCommandEnvelope && e2eRuntime) {
          try {
            command = e2eRuntime.decrypt(`session:${sessionId}`, e2eCommandEnvelope);
          } catch (error) {
            reportE2EDecryptFailure({
              context: "session.create",
              error,
              envelope: e2eCommandEnvelope
            });
            return;
          }
        }
        sessionManager.createSession({
          sessionId,
          command,
          cwd: msg.cwd ? String(msg.cwd) : undefined,
          env
        });
        return;
      }

      if (type === "session.input") {
        const sessionId = String(msg.sessionId);
        let data = String(msg.data ?? "");
        const e2eEnvelope = parseEnvelope(msg.e2eEnvelope);
        if (e2eEnvelope && e2eRuntime) {
          try {
            data = e2eRuntime.decrypt(`session:${sessionId}`, e2eEnvelope);
          } catch (error) {
            reportE2EDecryptFailure({
              context: "session.input",
              error,
              envelope: e2eEnvelope
            });
            return;
          }
        }
        sessionManager.input(sessionId, data);
        return;
      }

      if (type === "session.terminate") {
        sessionManager.terminate(String(msg.sessionId));
        return;
      }

      if (type === "tunnel.open") {
        tunnelManager.openTunnel(String(msg.tunnelId), Number(msg.targetPort));
        ws.send(
          JSON.stringify({
            type: "tunnel.status",
            tunnelId: String(msg.tunnelId),
            status: "open"
          })
        );
        return;
      }

      if (type === "conversation.turn.start") {
        const conversationId = String(msg.conversationId ?? "");
        const turnId = String(msg.turnId ?? "");
        let prompt = msg.prompt ? String(msg.prompt) : undefined;
        let inputItems = Array.isArray(msg.inputItems)
          ? msg.inputItems.filter((item): item is Record<string, unknown> => Boolean(item && typeof item === "object"))
          : undefined;
        const e2ePromptEnvelope = parseEnvelope(msg.e2ePromptEnvelope);
        if (e2ePromptEnvelope && e2eRuntime && conversationId) {
          let decrypted = "";
          try {
            decrypted = e2eRuntime.decrypt(`conversation:${conversationId}`, e2ePromptEnvelope);
          } catch (error) {
            reportE2EDecryptFailure({
              context: "conversation.turn.start",
              error,
              envelope: e2ePromptEnvelope,
              conversationId,
              turnId,
              failTurn: true
            });
            return;
          }
          try {
            const parsed = JSON.parse(decrypted) as Record<string, unknown>;
            if (typeof parsed.prompt === "string" && parsed.prompt.trim().length > 0) {
              prompt = parsed.prompt;
            }
            if (Array.isArray(parsed.inputItems)) {
              inputItems = parsed.inputItems
                .filter((item): item is Record<string, unknown> => Boolean(item && typeof item === "object"));
            }
          } catch {
            if (decrypted.trim().length > 0) {
              prompt = decrypted;
            }
          }
        }
        await conversationManager.startTurn({
          conversationId,
          turnId,
          threadId: msg.threadId ? String(msg.threadId) : undefined,
          prompt,
          inputItems,
          collaborationMode:
            msg.collaborationMode && typeof msg.collaborationMode === "object"
              ? (msg.collaborationMode as Record<string, unknown>)
              : undefined,
          model: msg.model ? String(msg.model) : undefined,
          cwd: msg.cwd ? String(msg.cwd) : undefined,
          approvalPolicy: msg.approvalPolicy ? String(msg.approvalPolicy) as "untrusted" | "on-failure" | "on-request" | "never" : undefined,
          sandboxMode:
            msg.sandboxMode ? (String(msg.sandboxMode) as "read-only" | "workspace-write" | "danger-full-access") : undefined,
          effort:
            msg.effort ? (String(msg.effort) as "none" | "minimal" | "low" | "medium" | "high" | "xhigh") : undefined
        });
        return;
      }

      if (type === "conversation.server.response") {
        const requestId = String(msg.requestId ?? "");
        if (!requestId) {
          return;
        }
        const conversationId = String(msg.conversationId ?? "");
        let error = typeof msg.error === "string" ? msg.error : undefined;
        let result = msg.result;
        const e2eEnvelope = parseEnvelope(msg.e2eEnvelope);
        if (e2eEnvelope && e2eRuntime && conversationId) {
          let decrypted = "";
          try {
            decrypted = e2eRuntime.decrypt(`conversation:${conversationId}`, e2eEnvelope);
          } catch (decryptError) {
            reportE2EDecryptFailure({
              context: "conversation.server.response",
              error: decryptError,
              envelope: e2eEnvelope,
              conversationId,
              turnId: typeof msg.turnId === "string" ? msg.turnId : undefined,
              requestId
            });
            conversationManager.resolveServerRequest({
              requestId,
              error: normalizeE2EDecryptErrorCode(decryptError)
            });
            return;
          }
          try {
            const parsed = JSON.parse(decrypted) as Record<string, unknown>;
            error = typeof parsed.error === "string" ? parsed.error : undefined;
            result = parsed.result;
          } catch {
            error = "invalid_e2e_server_response";
            result = undefined;
          }
        }
        conversationManager.resolveServerRequest({
          requestId,
          error,
          result
        });
        return;
      }

      if (type === "conversation.turn.interrupt") {
        await conversationManager.interruptTurn({
          conversationId: String(msg.conversationId ?? ""),
          turnId: String(msg.turnId ?? "")
        });
        return;
      }

      if (type === "codex.thread.list") {
        const requestId = String(msg.requestId ?? randomToken("ctl"));
        try {
          const threads = await conversationManager.listThreads({
            limit: Number(msg.limit ?? 100)
          });
          ws.send(
            JSON.stringify({
              type: "codex.thread.list.result",
              requestId,
              status: "ok",
              items: threads
            })
          );
        } catch (error) {
          ws.send(
            JSON.stringify({
              type: "codex.thread.list.result",
              requestId,
              status: "error",
              error: error instanceof Error ? error.message : "thread_list_failed"
            })
          );
        }
        return;
      }

      if (type === "codex.thread.read") {
        const requestId = String(msg.requestId ?? randomToken("cth"));
        const threadId = String(msg.threadId ?? "");
        if (!threadId) {
          ws.send(
            JSON.stringify({
              type: "codex.thread.read.result",
              requestId,
              status: "error",
              error: "thread_id_required"
            })
          );
          return;
        }

        try {
          const thread = await conversationManager.readThread({ threadId });
          ws.send(
            JSON.stringify({
              type: "codex.thread.read.result",
              requestId,
              status: "ok",
              thread
            })
          );
        } catch (error) {
          ws.send(
            JSON.stringify({
              type: "codex.thread.read.result",
              requestId,
              status: "error",
              error: error instanceof Error ? error.message : "thread_read_failed"
            })
          );
        }
        return;
      }

      if (type === "codex.options.get") {
        const requestId = String(msg.requestId ?? randomToken("copt"));
        try {
          const options = await conversationManager.getRuntimeOptions({
            cwd: msg.cwd ? String(msg.cwd) : undefined
          });
          ws.send(
            JSON.stringify({
              type: "codex.options.result",
              requestId,
              status: "ok",
              options
            })
          );
        } catch (error) {
          ws.send(
            JSON.stringify({
              type: "codex.options.result",
              requestId,
              status: "error",
              error: error instanceof Error ? error.message : "codex_options_failed"
            })
          );
        }
        return;
      }

      if (type === "tunnel.http.request") {
        const tunnelId = String(msg.tunnelId);
        const requestId = String(msg.requestId ?? randomToken("tr"));
        const targetPort = tunnelManager.getPort(tunnelId);
        if (!targetPort) {
          ws.send(
            JSON.stringify({
              type: "tunnel.http.response",
              requestId,
              status: 404,
              headers: { "content-type": "application/json" },
              bodyBase64: Buffer.from(JSON.stringify({ error: "unknown_tunnel" })).toString("base64")
            })
          );
          return;
        }

        const method = String(msg.method ?? "GET");
        const requestHeaders = (msg.headers as Record<string, string>) ?? {};
        delete requestHeaders.host;
        delete requestHeaders["content-length"];
        const path = String(msg.path ?? "/");
        const query = msg.query ? String(msg.query) : undefined;

        const body = msg.bodyBase64 ? Buffer.from(String(msg.bodyBase64), "base64") : undefined;

        try {
          const response = await proxyLocalHttpWithFallback({
            targetPort,
            method,
            path,
            query,
            headers: requestHeaders,
            body
          });
          const responseHeaders: Record<string, string> = {};
          response.headers.forEach((value, key) => {
            responseHeaders[key] = value;
          });
          const respBuffer = Buffer.from(await response.arrayBuffer());

          ws.send(
            JSON.stringify({
              type: "tunnel.http.response",
              requestId,
              status: response.status,
              headers: responseHeaders,
              bodyBase64: respBuffer.toString("base64")
            })
          );
        } catch (error) {
          ws.send(
            JSON.stringify({
              type: "tunnel.http.response",
              requestId,
              status: 502,
              headers: { "content-type": "application/json" },
              bodyBase64: Buffer.from(
                JSON.stringify({
                  error: error instanceof Error ? error.message : "local_fetch_failed"
                })
              ).toString("base64")
            })
          );
        }
        return;
      }

      if (type === "tunnel.ws.open") {
        const requestId = String(msg.requestId ?? randomToken("tws"));
        const connectionId = String(msg.connectionId ?? randomToken("twc"));
        const tunnelId = String(msg.tunnelId ?? "");
        const targetPort = tunnelManager.getPort(tunnelId);
        if (!targetPort) {
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.error",
              requestId,
              connectionId,
              error: "unknown_tunnel"
            })
          );
          return;
        }

        const path = String(msg.path ?? "/");
        const query = msg.query ? String(msg.query) : undefined;
        const requestHeaders = (msg.headers as Record<string, string> | undefined) ?? {};
        delete requestHeaders.host;
        delete requestHeaders.Host;
        delete requestHeaders["content-length"];
        delete requestHeaders["Content-Length"];
        delete requestHeaders.origin;
        delete requestHeaders.Origin;
        delete requestHeaders.connection;
        delete requestHeaders.Connection;
        delete requestHeaders.upgrade;
        delete requestHeaders.Upgrade;
        delete requestHeaders["sec-websocket-key"];
        delete requestHeaders["Sec-WebSocket-Key"];
        delete requestHeaders["sec-websocket-version"];
        delete requestHeaders["Sec-WebSocket-Version"];
        delete requestHeaders["sec-websocket-extensions"];
        delete requestHeaders["Sec-WebSocket-Extensions"];
        delete requestHeaders["sec-websocket-protocol"];
        delete requestHeaders["Sec-WebSocket-Protocol"];

        let socket: WebSocket;
        try {
          socket = await openLocalWsWithFallback({
            targetPort,
            path,
            query,
            headers: requestHeaders
          });
        } catch (error) {
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.error",
              requestId,
              connectionId,
              error: error instanceof Error ? error.message : "tunnel_ws_open_failed"
            })
          );
          return;
        }

        tunnelManager.bindSocket(connectionId, socket);

        ws.send(
          JSON.stringify({
            type: "tunnel.ws.opened",
            requestId,
            connectionId
          })
        );

        socket.on("message", (data, isBinary) => {
          const payload = Buffer.isBuffer(data)
            ? data
            : Array.isArray(data)
              ? Buffer.concat(data.map((chunk) => Buffer.from(chunk)))
              : Buffer.from(data instanceof ArrayBuffer ? new Uint8Array(data) : data);
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.frame",
              connectionId,
              dataBase64: payload.toString("base64"),
              isBinary
            })
          );
        });

        socket.on("close", (code, reason) => {
          tunnelManager.unbindSocket(connectionId);
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.closed",
              connectionId,
              code,
              reason: reason.toString()
            })
          );
        });

        socket.on("error", (error) => {
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.error",
              requestId,
              connectionId,
              error: error instanceof Error ? error.message : "tunnel_ws_open_failed"
            })
          );
        });

        return;
      }

      if (type === "tunnel.ws.frame") {
        const connectionId = String(msg.connectionId ?? "");
        const socket = tunnelManager.getSocket(connectionId);
        if (!socket) {
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.error",
              connectionId,
              error: "unknown_connection"
            })
          );
          return;
        }
        const encoded = String(msg.dataBase64 ?? "");
        const isBinary = msg.isBinary === true;
        socket.send(Buffer.from(encoded, "base64"), { binary: isBinary });
        return;
      }

      if (type === "tunnel.ws.close") {
        const connectionId = String(msg.connectionId ?? "");
        const code = typeof msg.code === "number" ? Number(msg.code) : undefined;
        const reason = typeof msg.reason === "string" ? msg.reason : undefined;
        tunnelManager.closeSocket(connectionId, code, reason);
        return;
      }
    } catch (error) {
      console.error("[agent] failed to process message", error);
    }
  });

  const shutdown = (message: string, error?: unknown): void => {
    conversationManager.close();
    if (persistSeqTimer) {
      clearTimeout(persistSeqTimer);
      persistSeqTimer = null;
    }
    void flushPersistedSeqByScope().finally(() => {
      if (error) {
        console.error(message, error);
      } else {
        console.error(message);
      }
      process.exit(1);
    });
  };

  ws.on("close", () => {
    shutdown("[agent] connection closed");
  });

  ws.on("error", (error) => {
    shutdown("[agent] websocket error", error);
  });
};
