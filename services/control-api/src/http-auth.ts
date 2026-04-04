import type { Request, Response, NextFunction } from "express";
import type { AuthService } from "./auth.js";

declare module "express-serve-static-core" {
  interface Request {
    userId?: string;
    userEmail?: string;
    authMode?: "bearer" | "session";
  }
}

interface SessionUser {
  userId: string;
  email: string;
}

interface RequireUserAuthOptions {
  resolveSessionUser?: (req: Request) => Promise<SessionUser | null>;
  csrf?: {
    appBaseUrl: string;
    enabled?: boolean;
  };
  debugLogs?: boolean;
  logPrefix?: string;
}

const MUTATING_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

const safeOriginFromUrl = (value: string): string | null => {
  try {
    return new URL(value).origin;
  } catch {
    return null;
  }
};

const resolveRequestOrigin = (req: Request): string | null => {
  const originHeader = req.header("origin");
  if (originHeader && originHeader.trim().length > 0) {
    return safeOriginFromUrl(originHeader.trim());
  }
  const refererHeader = req.header("referer");
  if (refererHeader && refererHeader.trim().length > 0) {
    return safeOriginFromUrl(refererHeader.trim());
  }
  return null;
};

export const requireUserAuth = (auth: AuthService, options: RequireUserAuthOptions = {}) => {
  const logPrefix = options.logPrefix ?? "authz";
  const allowedOrigin = options.csrf?.appBaseUrl ? safeOriginFromUrl(options.csrf.appBaseUrl) : null;
  const csrfEnabled = options.csrf?.enabled !== false;

  const log = (event: string, payload: Record<string, unknown>) => {
    if (!options.debugLogs) {
      return;
    }
    console.log(`[${logPrefix}] ${event}`, payload);
  };

  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const requestId = String((req as Request & { requestId?: string }).requestId ?? "");
    const raw = req.header("authorization");
    if (raw && raw.startsWith("Bearer ")) {
      const token = raw.slice("Bearer ".length);
      const claims = await auth.verifyAccessTokenWithUser(token);
      if (!claims) {
        log("deny_invalid_bearer", { requestId, method: req.method, path: req.path });
        res.status(401).json({ error: "invalid_token" });
        return;
      }

      req.userId = claims.sub;
      req.userEmail = claims.email;
      req.authMode = "bearer";
      log("allow_bearer", { requestId, method: req.method, path: req.path, userId: claims.sub });
      next();
      return;
    }

    if (!options.resolveSessionUser) {
      log("deny_missing_authorization", { requestId, method: req.method, path: req.path });
      res.status(401).json({ error: "missing_authorization" });
      return;
    }

    const sessionUser = await options.resolveSessionUser(req);
    if (!sessionUser) {
      log("deny_missing_authorization", { requestId, method: req.method, path: req.path });
      res.status(401).json({ error: "missing_authorization" });
      return;
    }

    if (csrfEnabled && MUTATING_METHODS.has(req.method.toUpperCase())) {
      const requestOrigin = resolveRequestOrigin(req);
      if (!requestOrigin || (allowedOrigin && requestOrigin !== allowedOrigin)) {
        log("deny_csrf_origin", {
          requestId,
          method: req.method,
          path: req.path,
          requestOrigin: requestOrigin ?? "",
          allowedOrigin: allowedOrigin ?? ""
        });
        res.status(403).json({ error: "csrf_origin_mismatch" });
        return;
      }
    }

    req.userId = sessionUser.userId;
    req.userEmail = sessionUser.email;
    req.authMode = "session";
    log("allow_session", { requestId, method: req.method, path: req.path, userId: sessionUser.userId });
    next();
  };
};
