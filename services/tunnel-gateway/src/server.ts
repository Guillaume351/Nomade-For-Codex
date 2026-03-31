import http from "node:http";
import { Readable } from "node:stream";
import express from "express";
import { WebSocket, WebSocketServer } from "ws";
import { loadConfig } from "./config.js";
import { extractTunnelSlug } from "./slug.js";

const hopByHopHeaders = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade"
]);

const sanitizeHeaders = (req: express.Request): Record<string, string> => {
  const headers: Record<string, string> = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (!value) {
      continue;
    }

    const lower = key.toLowerCase();
    if (hopByHopHeaders.has(lower)) {
      continue;
    }
    if (lower === "content-length" || lower === "x-nomade-token") {
      continue;
    }

    headers[lower] = Array.isArray(value) ? value.join(", ") : value;
  }

  const forwardedFor = req.header("x-forwarded-for");
  if (forwardedFor) {
    headers["x-forwarded-for"] = `${forwardedFor}, ${req.ip}`;
  } else if (req.ip) {
    headers["x-forwarded-for"] = req.ip;
  }
  headers["x-forwarded-host"] = req.header("host") ?? "";
  headers["x-forwarded-proto"] = req.header("x-forwarded-proto") ?? (req.secure ? "https" : "http");
  headers.host = req.header("host") ?? "";

  return headers;
};

const parseOriginalQuery = (originalUrl: string): string | undefined => {
  const raw = originalUrl.includes("?") ? originalUrl.split("?")[1] ?? "" : "";
  if (!raw) {
    return undefined;
  }
  const params = new URLSearchParams(raw);
  params.delete("nomade_token");
  const filtered = params.toString();
  return filtered || undefined;
};

export const createServer = (): http.Server => {
  const config = loadConfig();
  const app = express();

  app.use(express.raw({ type: "*/*", limit: "10mb" }));

  app.all("*", async (req, res) => {
    const slug = extractTunnelSlug(req.header("host"), config.previewBaseDomain);
    if (!slug) {
      res.status(404).json({ error: "invalid_preview_host" });
      return;
    }

    const tunnelToken = (req.query.nomade_token as string | undefined) ?? req.header("x-nomade-token") ?? undefined;
    const filteredQuery = parseOriginalQuery(req.originalUrl);
    const headers = sanitizeHeaders(req);
    const bodyBuffer = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);

    try {
      const upstream = await fetch(`${config.controlApiUrl}/internal/tunnels/${slug}/proxy`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-gateway-secret": config.gatewaySecret
        },
        body: JSON.stringify({
          method: req.method,
          path: req.path,
          query: filteredQuery,
          headers,
          bodyBase64: bodyBuffer.length ? bodyBuffer.toString("base64") : undefined,
          token: tunnelToken
        })
      });

      res.status(upstream.status);
      upstream.headers.forEach((value, key) => {
        if (hopByHopHeaders.has(key.toLowerCase())) {
          return;
        }
        if (key.toLowerCase() === "set-cookie") {
          return;
        }
        res.setHeader(key, value);
      });

      const getSetCookie = (upstream.headers as unknown as { getSetCookie?: () => string[] }).getSetCookie;
      if (typeof getSetCookie === "function") {
        const cookies = getSetCookie.call(upstream.headers);
        if (Array.isArray(cookies) && cookies.length > 0) {
          res.setHeader("set-cookie", cookies);
        }
      }

      if (!upstream.body) {
        res.end();
        return;
      }

      Readable.fromWeb(upstream.body as any).pipe(res);
    } catch (error) {
      const message = error instanceof Error ? error.message : "gateway_proxy_failed";
      res.status(502).json({ error: message });
    }
  });

  const server = http.createServer(app);
  const downstreamWss = new WebSocketServer({ noServer: true });

  server.on("upgrade", (req, socket, head) => {
    const slug = extractTunnelSlug(req.headers.host, config.previewBaseDomain);
    if (!slug) {
      socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }

    downstreamWss.handleUpgrade(req, socket, head, (downstream) => {
      const reqUrl = new URL(req.url ?? "/", "http://localhost");
      const filteredQuery = parseOriginalQuery(req.url ?? "/");
      const controlWsBase = config.controlApiUrl.replace(/^http/i, "ws");
      const upstreamUrl = new URL(`${controlWsBase}/internal/tunnels/${slug}/ws`);
      upstreamUrl.searchParams.set("path", reqUrl.pathname || "/");
      if (filteredQuery) {
        upstreamUrl.searchParams.set("query", filteredQuery);
      }

      const tunnelToken = reqUrl.searchParams.get("nomade_token") ?? req.headers["x-nomade-token"]?.toString();
      if (tunnelToken) {
        upstreamUrl.searchParams.set("nomade_token", tunnelToken);
      }

      const upstream = new WebSocket(upstreamUrl.toString(), {
        headers: {
          "x-gateway-secret": config.gatewaySecret,
          ...(req.headers.origin ? { origin: req.headers.origin.toString() } : {})
        }
      });

      downstream.on("message", (data, isBinary) => {
        if (upstream.readyState === upstream.OPEN) {
          upstream.send(data, { binary: isBinary });
        }
      });

      upstream.on("message", (data, isBinary) => {
        if (downstream.readyState === downstream.OPEN) {
          downstream.send(data, { binary: isBinary });
        }
      });

      downstream.on("close", (code, reason) => {
        if (upstream.readyState === upstream.OPEN || upstream.readyState === upstream.CONNECTING) {
          upstream.close(code, reason.toString());
        }
      });

      upstream.on("close", (code, reason) => {
        if (downstream.readyState === downstream.OPEN || downstream.readyState === downstream.CONNECTING) {
          downstream.close(code, reason.toString());
        }
      });

      upstream.on("error", (error) => {
        if (downstream.readyState === downstream.OPEN || downstream.readyState === downstream.CONNECTING) {
          downstream.close(1011, error instanceof Error ? error.message.slice(0, 120) : "upstream_ws_error");
        }
      });

      downstream.on("error", () => {
        if (upstream.readyState === upstream.OPEN || upstream.readyState === upstream.CONNECTING) {
          upstream.close(1011, "downstream_ws_error");
        }
      });
    });
  });

  return server;
};
