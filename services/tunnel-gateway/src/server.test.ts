import http, { type IncomingHttpHeaders } from "node:http";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createServer } from "./server.js";

const request = (params: {
  port: number;
  path: string;
  host: string;
  headers?: Record<string, string>;
}): Promise<{ status: number; headers: IncomingHttpHeaders; body: string }> => {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: params.port,
        path: params.path,
        method: "GET",
        headers: {
          host: params.host,
          ...(params.headers ?? {})
        }
      },
      (res) => {
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          body += chunk;
        });
        res.on("end", () => {
          resolve({
            status: res.statusCode ?? 0,
            headers: res.headers,
            body
          });
        });
      }
    );
    req.on("error", reject);
    req.end();
  });
};

describe("tunnel gateway server", () => {
  const originalEnv = { ...process.env };
  const originalFetch = global.fetch;

  beforeEach(() => {
    process.env.CONTROL_API_URL = "http://control-api.internal";
    process.env.INTERNAL_GATEWAY_SECRET = "test-gateway-secret";
    process.env.PREVIEW_BASE_DOMAIN = "preview.localhost";
  });

  afterEach(() => {
    process.env = { ...originalEnv };
    global.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("forwards request context and keeps upstream redirect headers", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response("redirecting", {
        status: 302,
        headers: {
          location: "/auth/login",
          "cache-control": "no-store",
          "content-type": "text/plain"
        }
      })
    );
    global.fetch = fetchMock as typeof global.fetch;

    const server = createServer();
    await new Promise<void>((resolve) => server.listen(0, resolve));

    try {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      const response = await request({
        port,
        path: "/dashboard?nomade_token=secret-token&keep=1",
        host: "frontend.preview.localhost",
        headers: {
          cookie: "sid=abc",
          authorization: "Bearer test"
        }
      });

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe("/auth/login");
      expect(response.headers["cache-control"]).toBe("no-store");
      expect(response.body).toBe("redirecting");

      expect(fetchMock).toHaveBeenCalledTimes(1);
      const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      expect(url).toBe("http://control-api.internal/internal/tunnels/frontend/proxy");

      const body = JSON.parse(String(init.body));
      expect(body.query).toBe("keep=1");
      expect(body.token).toBe("secret-token");
      expect(body.headers.cookie).toBe("sid=abc");
      expect(body.headers.authorization).toBe("Bearer test");
      expect(body.headers.host).toBe("frontend.preview.localhost");
      expect(body.headers["x-forwarded-host"]).toBe("frontend.preview.localhost");
      const setCookie = response.headers["set-cookie"];
      expect(setCookie).toBeDefined();
      const cookies = Array.isArray(setCookie) ? setCookie : [String(setCookie)];
      expect(cookies.some((cookie) => cookie.includes("nomade_tunnel_token=secret-token"))).toBe(true);
    } finally {
      await new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    }
  });

  it("reuses tunnel token from auth cookie and does not forward it to local app", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response("ok", {
        status: 200,
        headers: {
          "content-type": "text/plain"
        }
      })
    );
    global.fetch = fetchMock as typeof global.fetch;

    const server = createServer();
    await new Promise<void>((resolve) => server.listen(0, resolve));

    try {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      const response = await request({
        port,
        path: "/assets/app.js",
        host: "frontend.preview.localhost",
        headers: {
          cookie: "nomade_tunnel_token=secret-cookie-token; sid=abc"
        }
      });

      expect(response.status).toBe(200);
      expect(response.body).toBe("ok");

      expect(fetchMock).toHaveBeenCalledTimes(1);
      const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      expect(url).toBe("http://control-api.internal/internal/tunnels/frontend/proxy");

      const body = JSON.parse(String(init.body));
      expect(body.token).toBe("secret-cookie-token");
      expect(body.headers.cookie).toBe("sid=abc");
    } finally {
      await new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    }
  });

  it("falls back to token from referer when cookie is not available yet", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response("ok", {
        status: 200,
        headers: {
          "content-type": "text/plain"
        }
      })
    );
    global.fetch = fetchMock as typeof global.fetch;

    const server = createServer();
    await new Promise<void>((resolve) => server.listen(0, resolve));

    try {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      const response = await request({
        port,
        path: "/src/main.tsx?t=1",
        host: "frontend.preview.localhost",
        headers: {
          referer: "http://frontend.preview.localhost/?nomade_token=referer-token"
        }
      });

      expect(response.status).toBe(200);
      expect(response.body).toBe("ok");
      expect(fetchMock).toHaveBeenCalledTimes(1);

      const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      const body = JSON.parse(String(init.body));
      expect(body.token).toBe("referer-token");
    } finally {
      await new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    }
  });

  it("rejects hosts outside preview domain", async () => {
    const server = createServer();
    await new Promise<void>((resolve) => server.listen(0, resolve));
    try {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      const response = await request({
        port,
        path: "/",
        host: "example.com"
      });
      expect(response.status).toBe(404);
      expect(response.body).toContain("invalid_preview_host");
    } finally {
      await new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    }
  });
});
