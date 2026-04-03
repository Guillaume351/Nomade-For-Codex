import http from "node:http";
import { Readable } from "node:stream";
import express from "express";
import { WebSocket, WebSocketServer } from "ws";
import { loadConfig } from "./config.js";
import { extractTunnelSlug } from "./slug.js";

const tunnelAuthCookieName = "nomade_tunnel_token";

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

const closeWebSocketSafely = (
  socket: WebSocket,
  code: number | undefined,
  reason: string | undefined
): void => {
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
    if (safeReason) {
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

const parseCookieHeader = (cookieHeader: string | undefined): Record<string, string> => {
  if (!cookieHeader || cookieHeader.trim().length === 0) {
    return {};
  }
  const out: Record<string, string> = {};
  const segments = cookieHeader.split(";");
  for (const segment of segments) {
    const part = segment.trim();
    if (!part) {
      continue;
    }
    const eqIndex = part.indexOf("=");
    if (eqIndex <= 0) {
      continue;
    }
    const key = part.slice(0, eqIndex).trim();
    const valueRaw = part.slice(eqIndex + 1).trim();
    if (!key) {
      continue;
    }
    try {
      out[key] = decodeURIComponent(valueRaw);
    } catch {
      out[key] = valueRaw;
    }
  }
  return out;
};

const getCookie = (cookieHeader: string | undefined, name: string): string | undefined => {
  const parsed = parseCookieHeader(cookieHeader);
  const value = parsed[name];
  if (!value) {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const stripCookie = (cookieHeader: string | undefined, name: string): string | undefined => {
  if (!cookieHeader || cookieHeader.trim().length === 0) {
    return undefined;
  }
  const parts = cookieHeader
    .split(";")
    .map((part) => part.trim())
    .filter((part) => part.length > 0 && !part.toLowerCase().startsWith(`${name.toLowerCase()}=`));
  if (parts.length === 0) {
    return undefined;
  }
  return parts.join("; ");
};

const serializeHttpOnlyCookie = (name: string, value: string): string => {
  return `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; SameSite=Lax`;
};

const appendSetCookieHeader = (res: express.Response, cookieValue: string): void => {
  const current = res.getHeader("set-cookie");
  if (!current) {
    res.setHeader("set-cookie", [cookieValue]);
    return;
  }
  if (Array.isArray(current)) {
    res.setHeader(
      "set-cookie",
      current.map((value) => String(value)).concat(cookieValue)
    );
    return;
  }
  res.setHeader("set-cookie", [String(current), cookieValue]);
};

const firstNonEmptyToken = (...values: Array<unknown>): string | undefined => {
  for (const value of values) {
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed.length > 0) {
        return trimmed;
      }
      continue;
    }
    if (Array.isArray(value)) {
      for (const entry of value) {
        if (typeof entry === "string" && entry.trim().length > 0) {
          return entry.trim();
        }
      }
    }
  }
  return undefined;
};

const tokenFromRefererHeader = (referer: string | undefined): string | undefined => {
  if (!referer) {
    return undefined;
  }
  try {
    const parsed = new URL(referer);
    const token = parsed.searchParams.get("nomade_token");
    if (!token) {
      return undefined;
    }
    const trimmed = token.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  } catch {
    return undefined;
  }
};

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

    if (lower === "cookie") {
      const merged = Array.isArray(value) ? value.join("; ") : value;
      const filtered = stripCookie(merged, tunnelAuthCookieName);
      if (filtered) {
        headers[lower] = filtered;
      }
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

    const cookieHeader = req.header("cookie");
    const tokenFromQuery = firstNonEmptyToken(req.query.nomade_token);
    const tokenFromHeader = firstNonEmptyToken(req.header("x-nomade-token"));
    const tokenFromCookie = getCookie(cookieHeader, tunnelAuthCookieName);
    const tokenFromReferer = tokenFromRefererHeader(req.header("referer"));
    const tunnelToken = tokenFromQuery ?? tokenFromHeader ?? tokenFromCookie ?? tokenFromReferer;
    const cookieToPersist = tokenFromQuery ?? tokenFromHeader;
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
          for (const cookie of cookies) {
            appendSetCookieHeader(res, cookie);
          }
        }
      }

      if (cookieToPersist) {
        appendSetCookieHeader(res, serializeHttpOnlyCookie(tunnelAuthCookieName, cookieToPersist));
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

      const cookieHeader = Array.isArray(req.headers.cookie) ? req.headers.cookie.join("; ") : req.headers.cookie;
      const tunnelToken =
        firstNonEmptyToken(reqUrl.searchParams.get("nomade_token")) ??
        firstNonEmptyToken(req.headers["x-nomade-token"]) ??
        getCookie(cookieHeader, tunnelAuthCookieName) ??
        tokenFromRefererHeader(Array.isArray(req.headers.referer) ? req.headers.referer[0] : req.headers.referer);
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
        closeWebSocketSafely(upstream, code, reason.toString());
      });

      upstream.on("close", (code, reason) => {
        closeWebSocketSafely(downstream, code, reason.toString());
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
