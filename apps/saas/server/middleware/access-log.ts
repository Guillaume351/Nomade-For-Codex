import { randomUUID } from "node:crypto";
import { defineEventHandler, getRequestHeader, getRequestURL, setResponseHeader } from "h3";

const maskEmail = (value: string): string => {
  const at = value.indexOf("@");
  if (at <= 1) return "***";
  return `${value.slice(0, 1)}***${value.slice(at)}`;
};

const SENSITIVE_QUERY_KEYS = new Set([
  "email",
  "token",
  "access_token",
  "refresh_token",
  "code",
  "password",
  "user_code",
  "device_code"
]);

const sanitizePathForLog = (url: URL): string => {
  if (!url.search) {
    return url.pathname;
  }
  const sanitized = new URLSearchParams();
  for (const [key, value] of url.searchParams.entries()) {
    const normalized = key.toLowerCase();
    if (normalized === "email") {
      sanitized.set(key, maskEmail(value));
      continue;
    }
    if (SENSITIVE_QUERY_KEYS.has(normalized)) {
      sanitized.set(key, "[redacted]");
      continue;
    }
    sanitized.set(key, value);
  }
  const query = sanitized.toString();
  return query.length > 0 ? `${url.pathname}?${query}` : url.pathname;
};

export default defineEventHandler((event) => {
  const config = useRuntimeConfig(event);
  if (!config.httpAccessLogs) {
    return;
  }
  const requestId = String(getRequestHeader(event, "x-request-id") || randomUUID());
  setResponseHeader(event, "x-request-id", requestId);
  const startedAt = Date.now();
  const req = event.node.req;
  const res = event.node.res;
  const url = getRequestURL(event);

  if (url.pathname === "/login" && typeof url.searchParams.get("email") === "string") {
    const email = url.searchParams.get("email") ?? "";
    if (email.trim().length > 0) {
      console.log("[saas-auth] login_query_prefill", {
        requestId,
        email: maskEmail(email)
      });
    }
  }

  res.once("finish", () => {
    if (url.pathname.startsWith("/_nuxt/")) {
      return;
    }
    const durationMs = Date.now() - startedAt;
    console.log("[saas-http]", {
      requestId,
      method: req.method,
      path: sanitizePathForLog(url),
      status: res.statusCode,
      durationMs,
      ip: event.node.req.headers["x-forwarded-for"] ?? event.node.req.socket.remoteAddress ?? ""
    });

    if (url.pathname.startsWith("/api/auth/")) {
      console.log("[saas-auth-http]", {
        requestId,
        method: req.method,
        path: url.pathname,
        status: res.statusCode,
        durationMs
      });
    }

    if (url.pathname.startsWith("/billing/")) {
      console.log("[saas-billing-http]", {
        requestId,
        method: req.method,
        path: url.pathname,
        status: res.statusCode,
        durationMs
      });
    }
  });
});
