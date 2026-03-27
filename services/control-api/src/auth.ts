import jwt from "jsonwebtoken";
import { randomToken } from "@nomade/shared";
import type { UserClaims } from "@nomade/shared";
import { type Config } from "./config.js";
import { Repositories, type User } from "./repositories.js";

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresInSec: number;
}

export class AuthService {
  constructor(
    private readonly config: Config,
    private readonly repositories: Repositories
  ) {}

  async startDeviceCode(): Promise<{ deviceCode: string; userCode: string; expiresAt: Date; intervalSec: number }> {
    const created = await this.repositories.createDeviceCode(this.config.deviceCodeTtlSec);
    return {
      ...created,
      intervalSec: 2
    };
  }

  async approveDeviceCode(params: { userCode: string; email: string }): Promise<boolean> {
    const user = await this.repositories.findOrCreateUserByEmail(params.email);
    return this.repositories.approveDeviceCode(params.userCode, user.id);
  }

  async pollDeviceCode(deviceCode: string): Promise<{ status: "pending" } | { status: "expired" } | { status: "ok"; tokens: TokenPair }> {
    const consumed = await this.repositories.consumeApprovedDeviceCode(deviceCode);
    if (!consumed || "pending" in consumed || "expired" in consumed) {
      if (consumed && "pending" in consumed) {
        return { status: "pending" };
      }
      if (consumed && "expired" in consumed) {
        return { status: "expired" };
      }
      return { status: "pending" };
    }

    const user = await this.repositories.getUserById(consumed.userId);
    if (!user) {
      return { status: "pending" };
    }

    return {
      status: "ok",
      tokens: await this.issueUserTokens(user)
    };
  }

  async refresh(refreshToken: string): Promise<TokenPair | null> {
    const used = await this.repositories.useRefreshToken(refreshToken);
    if (!used) {
      return null;
    }
    const user = await this.repositories.getUserById(used.userId);
    if (!user) {
      return null;
    }
    return this.issueUserTokens(user);
  }

  verifyAccessToken(token: string): UserClaims | null {
    try {
      const claims = jwt.verify(token, this.config.jwtSecret) as UserClaims;
      if (claims.role !== "user") {
        return null;
      }
      return claims;
    } catch {
      return null;
    }
  }

  private async issueUserTokens(user: User): Promise<TokenPair> {
    const claims: UserClaims = {
      sub: user.id,
      role: "user",
      email: user.email
    };

    const accessToken = jwt.sign(claims, this.config.jwtSecret, {
      expiresIn: this.config.accessTtlSec,
      issuer: "nomade-control-api"
    });

    const refreshToken = randomToken("rt");
    await this.repositories.createRefreshToken(user.id, refreshToken, this.config.refreshTtlSec);

    return {
      accessToken,
      refreshToken,
      expiresInSec: this.config.accessTtlSec
    };
  }
}
