import WebSocket from "ws";
import { randomToken } from "@nomade/shared";
import { defaultConfigPath, readConfig } from "./config.js";
import { SessionManager } from "./session-manager.js";
import { TunnelManager } from "./tunnel-manager.js";
import { ConversationManager } from "./conversation-manager.js";

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
  const tunnelManager = new TunnelManager();

  const wsUrl = `${config.controlWsUrl}?agent_token=${encodeURIComponent(config.agentToken)}`;
  const ws = new WebSocket(wsUrl);
  const sendToControl = (payload: Record<string, unknown>): void => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify(payload));
    }
  };
  const conversationManager = new ConversationManager((payload) => {
    sendToControl(payload);
  });

  const sessionManager = new SessionManager({
    onOutput: (sessionId, stream, data, cursor) => {
      ws.send(
        JSON.stringify({
          type: "session.output",
          sessionId,
          stream,
          data,
          cursor
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
        sessionManager.createSession({
          sessionId: String(msg.sessionId),
          command: String(msg.command),
          cwd: msg.cwd ? String(msg.cwd) : undefined,
          env
        });
        return;
      }

      if (type === "session.input") {
        sessionManager.input(String(msg.sessionId), String(msg.data ?? ""));
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
        await conversationManager.startTurn({
          conversationId: String(msg.conversationId ?? ""),
          turnId: String(msg.turnId ?? ""),
          threadId: msg.threadId ? String(msg.threadId) : undefined,
          prompt: msg.prompt ? String(msg.prompt) : undefined,
          inputItems: Array.isArray(msg.inputItems)
              ? msg.inputItems
                  .filter((item): item is Record<string, unknown> => Boolean(item && typeof item === "object"))
              : undefined,
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
        const error = typeof msg.error === "string" ? msg.error : undefined;
        const result = msg.result;
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

  ws.on("close", () => {
    conversationManager.close();
    console.error("[agent] connection closed");
    process.exit(1);
  });

  ws.on("error", (error) => {
    conversationManager.close();
    console.error("[agent] websocket error", error);
    process.exit(1);
  });
};
