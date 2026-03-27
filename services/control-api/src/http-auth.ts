import type { Request, Response, NextFunction } from "express";
import type { AuthService } from "./auth.js";

declare module "express-serve-static-core" {
  interface Request {
    userId?: string;
    userEmail?: string;
  }
}

export const requireUserAuth = (auth: AuthService) => {
  return (req: Request, res: Response, next: NextFunction): void => {
    const raw = req.header("authorization");
    if (!raw || !raw.startsWith("Bearer ")) {
      res.status(401).json({ error: "missing_authorization" });
      return;
    }

    const token = raw.slice("Bearer ".length);
    const claims = auth.verifyAccessToken(token);
    if (!claims) {
      res.status(401).json({ error: "invalid_token" });
      return;
    }

    req.userId = claims.sub;
    req.userEmail = claims.email;
    next();
  };
};
