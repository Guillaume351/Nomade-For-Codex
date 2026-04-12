import { createSign } from "node:crypto";

export interface PushTarget {
  id: string;
  userId: string;
  deviceId: string;
  provider: string;
  platform: string;
  token: string;
}

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushSendResult {
  delivered: number;
  failed: number;
  invalidRegistrationIds: string[];
  disabled: boolean;
  disabledReason?: string;
}

export interface PushGateway {
  readonly enabled: boolean;
  send(targets: PushTarget[], message: PushMessage): Promise<PushSendResult>;
}

const base64UrlEncode = (input: string): string => {
  return Buffer.from(input, "utf8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
};

const toStringMap = (value: Record<string, string> | undefined): Record<string, string> => {
  if (!value) {
    return {};
  }
  const mapped: Record<string, string> = {};
  for (const [key, raw] of Object.entries(value)) {
    const normalizedKey = String(key ?? "").trim();
    if (!normalizedKey) {
      continue;
    }
    mapped[normalizedKey] = String(raw ?? "");
  }
  return mapped;
};

const parseJsonObject = (raw: string): Record<string, unknown> | null => {
  if (!raw || raw.trim().length === 0) {
    return null;
  }
  try {
    const decoded = JSON.parse(raw);
    if (decoded && typeof decoded === "object" && !Array.isArray(decoded)) {
      return decoded as Record<string, unknown>;
    }
  } catch {
    return null;
  }
  return null;
};

const extractFcmErrorCode = (payload: Record<string, unknown> | null): string | null => {
  if (!payload) {
    return null;
  }
  const error = payload.error;
  if (!error || typeof error !== "object") {
    return null;
  }
  const status = (error as Record<string, unknown>).status;
  if (typeof status === "string" && status.trim().length > 0) {
    return status.trim().toUpperCase();
  }
  const details = (error as Record<string, unknown>).details;
  if (!Array.isArray(details)) {
    return null;
  }
  for (const detail of details) {
    if (!detail || typeof detail !== "object") {
      continue;
    }
    const detailCode = (detail as Record<string, unknown>).errorCode;
    if (typeof detailCode === "string" && detailCode.trim().length > 0) {
      return detailCode.trim().toUpperCase();
    }
  }
  return null;
};

const isInvalidDeviceTokenError = (errorCode: string | null): boolean => {
  if (!errorCode) {
    return false;
  }
  return (
    errorCode === "UNREGISTERED" ||
    errorCode === "NOT_FOUND" ||
    errorCode === "INVALID_ARGUMENT" ||
    errorCode === "MISMATCH_SENDER_ID"
  );
};

class DisabledPushGateway implements PushGateway {
  readonly enabled = false;

  constructor(private readonly reason: string) {}

  async send(_targets: PushTarget[], _message: PushMessage): Promise<PushSendResult> {
    return {
      delivered: 0,
      failed: 0,
      invalidRegistrationIds: [],
      disabled: true,
      disabledReason: this.reason
    };
  }
}

class FirebasePushGateway implements PushGateway {
  readonly enabled = true;
  private oauthToken: { value: string; expiresAtMs: number } | null = null;

  constructor(
    private readonly config: {
      projectId: string;
      clientEmail: string;
      privateKey: string;
    }
  ) {}

  async send(targets: PushTarget[], message: PushMessage): Promise<PushSendResult> {
    if (targets.length === 0) {
      return {
        delivered: 0,
        failed: 0,
        invalidRegistrationIds: [],
        disabled: false
      };
    }
    const accessToken = await this.getFirebaseAccessToken();
    const invalidRegistrationIds: string[] = [];
    let delivered = 0;
    let failed = 0;

    await Promise.all(
      targets.map(async (target) => {
        const sendResult = await this.sendToTarget(accessToken, target, message);
        if (sendResult.delivered) {
          delivered += 1;
          return;
        }
        failed += 1;
        if (sendResult.invalidRegistration) {
          invalidRegistrationIds.push(target.id);
        }
      })
    );

    return {
      delivered,
      failed,
      invalidRegistrationIds,
      disabled: false
    };
  }

  private buildServiceAccountJwt(): string {
    const nowSec = Math.floor(Date.now() / 1000);
    const header = base64UrlEncode(
      JSON.stringify({
        alg: "RS256",
        typ: "JWT"
      })
    );
    const claimSet = base64UrlEncode(
      JSON.stringify({
        iss: this.config.clientEmail,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: nowSec,
        exp: nowSec + 3600
      })
    );
    const unsigned = `${header}.${claimSet}`;
    const signer = createSign("RSA-SHA256");
    signer.update(unsigned);
    signer.end();
    const signature = signer
      .sign(this.config.privateKey, "base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/g, "");
    return `${unsigned}.${signature}`;
  }

  private async getFirebaseAccessToken(): Promise<string> {
    const cached = this.oauthToken;
    if (cached && cached.expiresAtMs - Date.now() > 60_000) {
      return cached.value;
    }

    const assertion = this.buildServiceAccountJwt();
    const body = new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion
    });
    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded"
      },
      body
    });
    const raw = await response.text();
    if (!response.ok) {
      throw new Error(`firebase_oauth_failed:${response.status}:${raw}`);
    }
    const payload = parseJsonObject(raw);
    const accessToken = payload?.access_token;
    const expiresIn = payload?.expires_in;
    if (typeof accessToken !== "string" || accessToken.length === 0) {
      throw new Error("firebase_oauth_missing_access_token");
    }
    const expiresInSec = typeof expiresIn === "number" ? expiresIn : 3600;
    this.oauthToken = {
      value: accessToken,
      expiresAtMs: Date.now() + Math.max(60, Math.floor(expiresInSec)) * 1000
    };
    return accessToken;
  }

  private async sendToTarget(
    accessToken: string,
    target: PushTarget,
    message: PushMessage
  ): Promise<{ delivered: boolean; invalidRegistration: boolean }> {
    const payload = {
      message: {
        token: target.token,
        notification: {
          title: message.title,
          body: message.body
        },
        data: toStringMap(message.data),
        android: {
          priority: "HIGH"
        },
        apns: {
          headers: {
            "apns-priority": "10"
          },
          payload: {
            aps: {
              sound: "default"
            }
          }
        }
      }
    };

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(this.config.projectId)}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify(payload)
      }
    );
    if (response.ok) {
      return { delivered: true, invalidRegistration: false };
    }

    const raw = await response.text();
    const body = parseJsonObject(raw);
    const errorCode = extractFcmErrorCode(body);
    if (isInvalidDeviceTokenError(errorCode)) {
      return { delivered: false, invalidRegistration: true };
    }
    return { delivered: false, invalidRegistration: false };
  }
}

export const createPushGateway = (config: {
  projectId?: string;
  clientEmail?: string;
  privateKey?: string;
}): PushGateway => {
  if (!config.projectId || !config.clientEmail || !config.privateKey) {
    return new DisabledPushGateway("firebase_not_configured");
  }
  return new FirebasePushGateway({
    projectId: config.projectId,
    clientEmail: config.clientEmail,
    privateKey: config.privateKey
  });
};

