import http from "node:http";
import express from "express";
import { loadConfig } from "./config.js";
import { extractTunnelSlug } from "./slug.js";

const forwardedHeaders = new Set([
  "accept",
  "accept-encoding",
  "accept-language",
  "cache-control",
  "content-type",
  "if-none-match",
  "origin",
  "pragma",
  "referer",
  "user-agent"
]);

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

    const tunnelToken = (req.query.nomade_token as string | undefined) ?? req.header("x-nomade-token");
    if (!tunnelToken) {
      res.status(401).json({ error: "missing_tunnel_token" });
      return;
    }

    const originalSearch = req.originalUrl.includes("?") ? req.originalUrl.split("?")[1] : "";
    const queryParams = new URLSearchParams(originalSearch);
    queryParams.delete("nomade_token");
    const filteredQuery = queryParams.toString() || undefined;

    const headers: Record<string, string> = {};
    for (const [key, value] of Object.entries(req.headers)) {
      if (!value) {
        continue;
      }
      const lower = key.toLowerCase();
      if (!forwardedHeaders.has(lower)) {
        continue;
      }
      if (Array.isArray(value)) {
        headers[lower] = value.join(", ");
      } else {
        headers[lower] = value;
      }
    }

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

      const contentType = upstream.headers.get("content-type") ?? "application/octet-stream";
      const arrayBuffer = await upstream.arrayBuffer();
      const responseBuffer = Buffer.from(arrayBuffer);
      res.status(upstream.status);
      res.setHeader("content-type", contentType);
      res.send(responseBuffer);
    } catch (error) {
      const message = error instanceof Error ? error.message : "gateway_proxy_failed";
      res.status(502).json({ error: message });
    }
  });

  const server = http.createServer(app);
  server.on("upgrade", (req, socket) => {
    socket.write("HTTP/1.1 501 Not Implemented\r\nConnection: close\r\n\r\n");
    socket.destroy();
    console.warn(`[tunnel-gateway] websocket upgrade not implemented for ${req.url ?? "/"}`);
  });

  return server;
};
