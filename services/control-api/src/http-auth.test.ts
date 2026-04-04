import { describe, expect, it, vi } from "vitest";
import type { NextFunction, Request, Response } from "express";
import { requireUserAuth } from "./http-auth.js";

const createMockReq = (params: {
  method?: string;
  path?: string;
  headers?: Record<string, string>;
}): Request =>
  ({
    method: params.method ?? "GET",
    path: params.path ?? "/me",
    header: (name: string) => params.headers?.[name.toLowerCase()] ?? params.headers?.[name] ?? undefined
  }) as unknown as Request;

const createMockRes = () => {
  const state = {
    statusCode: 200,
    body: null as unknown
  };
  const res = {
    status(code: number) {
      state.statusCode = code;
      return this;
    },
    json(payload: unknown) {
      state.body = payload;
      return this;
    }
  } as unknown as Response;
  return { res, state };
};

describe("requireUserAuth hybrid mode", () => {
  it("accepts valid bearer token", async () => {
    const auth = {
      verifyAccessTokenWithUser: vi.fn().mockResolvedValue({ sub: "u_1", email: "a@example.com" })
    } as unknown as Parameters<typeof requireUserAuth>[0];

    const middleware = requireUserAuth(auth);
    const req = createMockReq({ headers: { authorization: "Bearer token" } });
    const { res, state } = createMockRes();
    const next = vi.fn() as unknown as NextFunction;

    await middleware(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.userId).toBe("u_1");
    expect(req.authMode).toBe("bearer");
    expect(state.statusCode).toBe(200);
  });

  it("accepts session fallback on safe methods", async () => {
    const auth = {
      verifyAccessTokenWithUser: vi.fn()
    } as unknown as Parameters<typeof requireUserAuth>[0];

    const middleware = requireUserAuth(auth, {
      resolveSessionUser: vi.fn().mockResolvedValue({ userId: "u_2", email: "b@example.com" }),
      csrf: { appBaseUrl: "https://nomade.example.com", enabled: true }
    });
    const req = createMockReq({ method: "GET" });
    const { res, state } = createMockRes();
    const next = vi.fn() as unknown as NextFunction;

    await middleware(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.userId).toBe("u_2");
    expect(req.authMode).toBe("session");
    expect(state.statusCode).toBe(200);
  });

  it("rejects session-based mutating request without same origin", async () => {
    const auth = {
      verifyAccessTokenWithUser: vi.fn()
    } as unknown as Parameters<typeof requireUserAuth>[0];

    const middleware = requireUserAuth(auth, {
      resolveSessionUser: vi.fn().mockResolvedValue({ userId: "u_3", email: "c@example.com" }),
      csrf: { appBaseUrl: "https://nomade.example.com", enabled: true }
    });
    const req = createMockReq({ method: "POST" });
    const { res, state } = createMockRes();
    const next = vi.fn() as unknown as NextFunction;

    await middleware(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(state.statusCode).toBe(403);
    expect(state.body).toEqual({ error: "csrf_origin_mismatch" });
  });

  it("accepts session-based mutating request with matching origin", async () => {
    const auth = {
      verifyAccessTokenWithUser: vi.fn()
    } as unknown as Parameters<typeof requireUserAuth>[0];

    const middleware = requireUserAuth(auth, {
      resolveSessionUser: vi.fn().mockResolvedValue({ userId: "u_4", email: "d@example.com" }),
      csrf: { appBaseUrl: "https://nomade.example.com", enabled: true }
    });
    const req = createMockReq({
      method: "PATCH",
      headers: { origin: "https://nomade.example.com" }
    });
    const { res, state } = createMockRes();
    const next = vi.fn() as unknown as NextFunction;

    await middleware(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.authMode).toBe("session");
    expect(state.statusCode).toBe(200);
  });
});
