import WebSocket from "ws";
import { randomToken } from "@nomade/shared";
import { defaultConfigPath, readConfig } from "./config.js";
import { SessionManager } from "./session-manager.js";
import { TunnelManager } from "./tunnel-manager.js";
import { ConversationManager } from "./conversation-manager.js";

interface RunArgs {
  configPath?: string;
}

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
          prompt: String(msg.prompt ?? ""),
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

        const query = msg.query ? `?${String(msg.query)}` : "";
        const localUrl = `http://127.0.0.1:${targetPort}${String(msg.path)}${query}`;
        const method = String(msg.method ?? "GET");
        const requestHeaders = (msg.headers as Record<string, string>) ?? {};
        delete requestHeaders.host;
        delete requestHeaders["content-length"];

        const body = msg.bodyBase64 ? Buffer.from(String(msg.bodyBase64), "base64") : undefined;

        try {
          const response = await fetch(localUrl, {
            method,
            headers: requestHeaders,
            body: body && body.length ? body : undefined
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

        const query = msg.query ? `?${String(msg.query)}` : "";
        const localWsUrl = `ws://127.0.0.1:${targetPort}${String(msg.path ?? "/")}${query}`;
        const requestHeaders = (msg.headers as Record<string, string> | undefined) ?? {};
        const socket = new WebSocket(localWsUrl, {
          headers: requestHeaders
        });
        tunnelManager.bindSocket(connectionId, socket);

        socket.on("open", () => {
          ws.send(
            JSON.stringify({
              type: "tunnel.ws.opened",
              requestId,
              connectionId
            })
          );
        });

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
