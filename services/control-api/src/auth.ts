import jwt from "jsonwebtoken";
import { randomToken } from "@nomade/shared";
import type { UserClaims } from "@nomade/shared";
import { type Config } from "./config.js";
import {
  Repositories,
  type User,
  type DeviceCodeStartMode,
  type ScanStartHostDevice
} from "./repositories.js";

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

  async startDeviceCode(params?: {
    mode?: DeviceCodeStartMode;
    hostDevice?: ScanStartHostDevice;
  }): Promise<{
    deviceCode: string;
    userCode: string;
    expiresAt: Date;
    intervalSec: number;
    verificationUri: string;
    verificationUriComplete: string;
    mode: DeviceCodeStartMode;
    scanPayload?: string;
    scanShortCode?: string;
  }> {
    const mode = params?.mode ?? "legacy";
    const created = await this.repositories.createDeviceCode({
      ttlSec: this.config.deviceCodeTtlSec,
      mode,
      hostDevice: params?.hostDevice
    });
    const base = this.config.appBaseUrl.replace(/\/$/, "");
    const verificationUri = `${base}/web/activate`;
    const verificationUriComplete = `${verificationUri}?user_code=${encodeURIComponent(created.userCode)}`;
    let scanPayload: string | undefined;
    if (created.mode === "scan_secure" && created.scanId) {
      scanPayload = jwt.sign(
        {
          kind: "scan_secure",
          scanId: created.scanId,
          deviceCode: created.deviceCode,
          userCode: created.userCode
        },
        this.config.jwtSecret,
        {
          expiresIn: this.config.deviceCodeTtlSec,
          issuer: "nomade-control-api"
        }
      );
    }
    return {
      ...created,
      intervalSec: 2,
      verificationUri,
      verificationUriComplete,
      scanPayload,
      scanShortCode: created.scanShortCode
    };
  }

  verifyScanPayload(token: string): {
    scanId: string;
    deviceCode: string;
    userCode: string;
  } | null {
    try {
      const claims = jwt.verify(token, this.config.jwtSecret) as Record<string, unknown>;
      if (claims.kind !== "scan_secure") {
        return null;
      }
      const scanId = typeof claims.scanId === "string" ? claims.scanId : "";
      const deviceCode = typeof claims.deviceCode === "string" ? claims.deviceCode : "";
      const userCode = typeof claims.userCode === "string" ? claims.userCode : "";
      if (!scanId || !deviceCode || !userCode) {
        return null;
      }
      return { scanId, deviceCode, userCode };
    } catch {
      return null;
    }
  }

  async approveDeviceCode(params: { userCode: string; email: string }): Promise<boolean> {
    const user = await this.repositories.findOrCreateUserByEmail(params.email);
    return this.repositories.approveDeviceCode(params.userCode, user.id);
  }

  async pollDeviceCode(deviceCode: string): Promise<
    | { status: "pending" }
    | { status: "pending_scan" }
    | {
        status: "pending_key_exchange";
        mobileDeviceId?: string | null;
        mobileEncPublicKey?: string | null;
        mobileSignPublicKey?: string | null;
        mobileExchangePublicKey?: string | null;
        hostBundleReady: boolean;
      }
    | { status: "expired" }
    | { status: "ok"; tokens: TokenPair }
  > {
    const state = await this.repositories.consumeDeviceCodePollState(deviceCode);
    if (!state) {
      return { status: "pending" };
    }
    if (state.status === "pending") {
      return { status: "pending" };
    }
    if (state.status === "pending_scan") {
      return { status: "pending_scan" };
    }
    if (state.status === "pending_key_exchange") {
      return {
        status: "pending_key_exchange",
        mobileDeviceId: state.mobileDeviceId,
        mobileEncPublicKey: state.mobileEncPublicKey,
        mobileSignPublicKey: state.mobileSignPublicKey,
        mobileExchangePublicKey: state.mobileExchangePublicKey,
        hostBundleReady: state.hostBundleReady
      };
    }
    if (state.status === "expired") {
      return { status: "expired" };
    }

    const user = await this.repositories.getUserById(state.userId);
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

  async verifyAccessTokenWithUser(token: string): Promise<UserClaims | null> {
    const claims = this.verifyAccessToken(token);
    if (!claims) {
      return null;
    }
    const user = await this.repositories.getUserById(claims.sub);
    if (!user) {
      return null;
    }
    return claims;
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
