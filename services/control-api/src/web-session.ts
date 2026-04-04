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
      :root {
        --bg: #f5f7fb;
        --surface: #ffffff;
        --text: #101828;
        --muted: #475467;
        --border: #d0d5dd;
        --primary: #0b5fff;
        --danger: #b42318;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: "Sora", "Avenir Next", "Segoe UI", sans-serif;
        background: radial-gradient(circle at top right, #dce7ff 0%, #f5f7fb 45%, #f5f7fb 100%);
        color: var(--text);
      }
      .wrap {
        width: min(960px, calc(100% - 2rem));
        margin: 2rem auto;
      }
      .card {
        background: color-mix(in srgb, var(--surface) 95%, transparent);
        border: 1px solid var(--border);
        border-radius: 18px;
        box-shadow: 0 16px 48px rgba(16, 24, 40, 0.08);
        padding: 1.25rem;
      }
      h1 {
        margin: 0 0 0.75rem;
        letter-spacing: -0.02em;
      }
      p {
        line-height: 1.5;
        color: var(--muted);
        margin: 0 0 0.75rem;
      }
      code, pre {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        background: #eef2ff;
        border-radius: 6px;
        padding: 0.15rem 0.35rem;
      }
      input, button {
        font: inherit;
        font-size: 16px;
        padding: 0.6rem 0.75rem;
        border-radius: 10px;
        border: 1px solid var(--border);
        background: #fff;
      }
      input { flex: 1 1 220px; min-width: 220px; }
      button {
        cursor: pointer;
        background: var(--primary);
        border-color: var(--primary);
        color: #fff;
      }
      button:disabled {
        cursor: not-allowed;
        opacity: 0.6;
      }
      .row {
        display: flex;
        gap: 0.6rem;
        align-items: center;
        flex-wrap: wrap;
        margin-top: 0.75rem;
      }
      a {
        color: var(--primary);
        text-decoration: none;
      }
      a:hover { text-decoration: underline; }
      .muted { color: var(--muted); font-size: 14px; }
      ul { padding-left: 1.1rem; }
      table { width: 100%; border-collapse: collapse; }
      th, td {
        text-align: left;
        padding: 0.5rem 0;
        border-bottom: 1px solid var(--border);
      }
      #auth-notice[style*="b91c1c"], #signup-notice[style*="b91c1c"] { color: var(--danger) !important; }
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
