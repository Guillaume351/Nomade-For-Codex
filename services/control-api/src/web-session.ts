import type express from "express";
import jwt from "jsonwebtoken";

export interface WebSessionClaims {
  sub: string;
  email: string;
  kind: "web";
}

export const parseCookieHeader = (raw: string | undefined): Record<string, string> => {
  if (!raw) {
    return {};
  }
  const pairs = raw.split(";");
  const out: Record<string, string> = {};
  for (const pair of pairs) {
    const [keyRaw, ...rest] = pair.trim().split("=");
    const key = keyRaw?.trim();
    if (!key) {
      continue;
    }
    out[key] = decodeURIComponent(rest.join("="));
  }
  return out;
};

export const readWebSession = (params: {
  req: express.Request;
  cookieName: string;
  jwtSecret: string;
}): WebSessionClaims | null => {
  const cookies = parseCookieHeader(params.req.header("cookie"));
  const token = cookies[params.cookieName];
  if (!token) {
    return null;
  }
  try {
    const claims = jwt.verify(token, params.jwtSecret) as WebSessionClaims;
    if (claims.kind !== "web" || !claims.sub || !claims.email) {
      return null;
    }
    return claims;
  } catch {
    return null;
  }
};

export const createWebSessionToken = (params: {
  userId: string;
  email: string;
  jwtSecret: string;
  ttlSec: number;
}): string => {
  return jwt.sign(
    {
      sub: params.userId,
      email: params.email,
      kind: "web"
    } as WebSessionClaims,
    params.jwtSecret,
    {
      expiresIn: params.ttlSec,
      issuer: "nomade-control-api"
    }
  );
};

export const setSessionCookie = (params: {
  res: express.Response;
  cookieName: string;
  value: string;
  ttlSec: number;
  secure: boolean;
}): void => {
  const parts = [
    `${params.cookieName}=${encodeURIComponent(params.value)}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    `Max-Age=${Math.max(0, params.ttlSec)}`
  ];
  if (params.secure) {
    parts.push("Secure");
  }
  params.res.setHeader("Set-Cookie", parts.join("; "));
};

export const clearSessionCookie = (params: {
  res: express.Response;
  cookieName: string;
  secure: boolean;
}): void => {
  const parts = [`${params.cookieName}=`, "Path=/", "HttpOnly", "SameSite=Lax", "Max-Age=0"];
  if (params.secure) {
    parts.push("Secure");
  }
  params.res.setHeader("Set-Cookie", parts.join("; "));
};

export const htmlPage = (params: { title: string; body: string }): string => {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>${params.title}</title>
    <style>
      body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif; background: #f6f7fb; color: #111827; }
      .wrap { max-width: 720px; margin: 40px auto; padding: 24px; }
      .card { background: #fff; border-radius: 12px; border: 1px solid #e5e7eb; padding: 20px; box-shadow: 0 6px 20px rgba(17,24,39,0.06); }
      h1 { margin: 0 0 12px; font-size: 24px; }
      p { line-height: 1.5; color: #374151; }
      code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; background: #f3f4f6; border-radius: 6px; padding: 2px 6px; }
      input, button { font-size: 16px; padding: 10px 12px; border-radius: 8px; border: 1px solid #d1d5db; }
      button { cursor: pointer; background: #111827; color: #fff; border-color: #111827; }
      .row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-top: 12px; }
      a { color: #1d4ed8; text-decoration: none; }
      .muted { color: #6b7280; font-size: 14px; }
      ul { padding-left: 18px; }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="card">
        ${params.body}
      </div>
    </div>
  </body>
</html>`;
};

export const encodeHtml = (value: string): string =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
