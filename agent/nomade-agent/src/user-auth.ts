import fs from "node:fs/promises";
import { spawn } from "node:child_process";
import os from "node:os";
import { randomBytes } from "node:crypto";
import QRCode from "qrcode";
import {
  deriveSharedSecret,
  encryptScanBundle,
  generateDeviceKeyMaterial,
  generateExchangeKeyPair,
  toBase64Url
} from "@nomade/shared";
import { z } from "zod";
import { defaultSessionPath, readUserSession, writeUserSession, type UserSessionConfig } from "./config.js";

const deviceStartSchema = z.object({
  deviceCode: z.string(),
  userCode: z.string(),
  mode: z.enum(["legacy", "scan_secure"]).optional(),
  expiresAt: z.string(),
  intervalSec: z.number().int().positive().optional(),
  verificationUri: z.string().optional(),
  verificationUriComplete: z.string().optional(),
  scanPayload: z.string().optional(),
  scanShortCode: z.string().optional()
});

const devicePollSchema = z.object({
  status: z.string(),
  mobileDeviceId: z.string().optional().nullable(),
  mobileEncPublicKey: z.string().optional().nullable(),
  mobileSignPublicKey: z.string().optional().nullable(),
  mobileExchangePublicKey: z.string().optional().nullable(),
  hostBundleReady: z.boolean().optional(),
  accessToken: z.string().optional(),
  refreshToken: z.string().optional(),
  expiresInSec: z.number().int().positive().optional()
});

const meSchema = z.object({
  id: z.string(),
  email: z.string().email()
});

const entitlementsSchema = z.object({
  planCode: z.string(),
  maxAgents: z.number().int().positive(),
  currentAgents: z.number().int().nonnegative(),
  limitReached: z.boolean()
});

const sleep = async (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

const openInBrowser = async (url: string): Promise<void> => {
  const platform = process.platform;
  const command = platform === "darwin" ? "open" : platform === "win32" ? "cmd" : "xdg-open";
  const args =
    platform === "win32"
      ? ["/c", "start", "", url]
      : [url];
  try {
    const child = spawn(command, args, {
      detached: true,
      stdio: "ignore"
    });
    child.on("error", () => {
      // best effort
    });
    child.unref();
  } catch {
    // Best effort only.
  }
};

const printLocalQr = async (value: string): Promise<void> => {
  try {
    const rendered = await QRCode.toString(value, {
      type: "terminal",
      small: true
    });
    if (rendered) {
      console.log(rendered);
      return;
    }
  } catch {
    // fallback below
  }
  console.log("QR rendering failed locally. Use the URL above.");
};

const parseApiError = async (response: {
  status: number;
  text: () => Promise<string>;
}): Promise<{ message: string; payload: Record<string, unknown> }> => {
  const raw = await response.text();
  let payload: Record<string, unknown> = {};
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    if (parsed && typeof parsed === "object") {
      payload = parsed;
    }
  } catch {
    payload = {};
  }
  const message = typeof payload.error === "string" ? payload.error : `http_${response.status}`;
  return { message, payload };
};

const fetchMe = async (serverUrl: string, accessToken: string): Promise<{ id: string; email: string }> => {
  const response = await fetch(`${serverUrl}/me`, {
    headers: { authorization: `Bearer ${accessToken}` }
  });
  if (!response.ok) {
    const err = await parseApiError(response);
    throw new Error(`fetch_me_failed:${err.message}`);
  }
  return meSchema.parse(await response.json());
};

const refreshTokens = async (serverUrl: string, refreshToken: string): Promise<{ accessToken: string; refreshToken: string; expiresInSec: number }> => {
  const response = await fetch(`${serverUrl}/auth/refresh`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refreshToken })
  });
  if (!response.ok) {
    const err = await parseApiError(response);
    throw new Error(`refresh_failed:${err.message}`);
  }
  const payload = (await response.json()) as Record<string, unknown>;
  const accessToken = typeof payload.accessToken === "string" ? payload.accessToken : "";
  const nextRefreshToken =
    typeof payload.refreshToken === "string" && payload.refreshToken.trim().length > 0 ? payload.refreshToken : refreshToken;
  const expiresInSec = typeof payload.expiresInSec === "number" ? payload.expiresInSec : 900;
  if (!accessToken) {
    throw new Error("refresh_failed:missing_access_token");
  }
  return { accessToken, refreshToken: nextRefreshToken, expiresInSec };
};

const saveSession = async (params: {
  sessionPath: string;
  serverUrl: string;
  accessToken: string;
  refreshToken: string;
  expiresInSec: number;
  email?: string;
  e2e?: UserSessionConfig["e2e"];
}): Promise<UserSessionConfig> => {
  const expiresAt = new Date(Date.now() + Math.max(60, params.expiresInSec) * 1000).toISOString();
  const value: UserSessionConfig = {
    controlHttpUrl: params.serverUrl,
    accessToken: params.accessToken,
    refreshToken: params.refreshToken,
    expiresAt,
    email: params.email,
    e2e: params.e2e
  };
  await writeUserSession(params.sessionPath, value);
  return value;
};

const normalizeServerUrl = (value: string): string => value.replace(/\/$/, "");

const loadReusableE2EState = async (params: {
  serverUrl: string;
  sessionPath: string;
}): Promise<NonNullable<UserSessionConfig["e2e"]> | null> => {
  try {
    const session = await readUserSession(params.sessionPath);
    if (normalizeServerUrl(session.controlHttpUrl) !== normalizeServerUrl(params.serverUrl)) {
      return null;
    }
    const e2e = session.e2e;
    if (
      !e2e ||
      !e2e.rootKey ||
      !e2e.device?.deviceId ||
      !e2e.device?.encPublicKey ||
      !e2e.device?.encPrivateKey ||
      !e2e.device?.signPublicKey ||
      !e2e.device?.signPrivateKey
    ) {
      return null;
    }
    return e2e;
  } catch {
    return null;
  }
};

export const ensureSession = async (params: {
  serverUrl: string;
  sessionPath?: string;
}): Promise<UserSessionConfig> => {
  const sessionPath = params.sessionPath ?? defaultSessionPath();
  const session = await readUserSession(sessionPath);
  const serverUrl = params.serverUrl.replace(/\/$/, "");
  if (session.controlHttpUrl.replace(/\/$/, "") !== serverUrl) {
    throw new Error(
      `session_server_mismatch: session=${session.controlHttpUrl} requested=${serverUrl}. Run login again for this server.`
    );
  }

  const expiresAt = Date.parse(session.expiresAt);
  const timeLeftMs = expiresAt - Date.now();
  if (Number.isFinite(expiresAt) && timeLeftMs > 60_000) {
    return session;
  }

  const refreshed = await refreshTokens(serverUrl, session.refreshToken);
  const me = await fetchMe(serverUrl, refreshed.accessToken).catch(() => null);
  return saveSession({
    sessionPath,
    serverUrl,
    accessToken: refreshed.accessToken,
    refreshToken: refreshed.refreshToken,
    expiresInSec: refreshed.expiresInSec,
    email: me?.email ?? session.email,
    e2e: session.e2e
  });
};

export const loginWithDeviceCode = async (params: {
  serverUrl: string;
  sessionPath?: string;
  openBrowser?: boolean;
}): Promise<void> => {
  const serverUrl = params.serverUrl.replace(/\/$/, "");
  const sessionPath = params.sessionPath ?? defaultSessionPath();
  const reusableE2E = await loadReusableE2EState({ serverUrl, sessionPath });
  const hostDevice = reusableE2E
    ? {
        ...reusableE2E.device
      }
    : generateDeviceKeyMaterial();
  const exchangeKeyPair = generateExchangeKeyPair();
  const startResponse = await fetch(`${serverUrl}/auth/device/start`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      mode: "scan_secure",
      hostDevice: {
        deviceId: hostDevice.deviceId,
        name: os.hostname(),
        platform: process.platform,
        encPublicKey: hostDevice.encPublicKey,
        signPublicKey: hostDevice.signPublicKey,
        exchangePublicKey: exchangeKeyPair.publicKey
      }
    })
  });
  if (!startResponse.ok) {
    const err = await parseApiError(startResponse);
    throw new Error(`login_start_failed:${err.message}`);
  }
  const started = deviceStartSchema.parse(await startResponse.json());
  const verificationUri = started.verificationUri ?? `${serverUrl}/web/activate`;
  const verificationUriComplete =
    started.verificationUriComplete ?? `${verificationUri}?user_code=${encodeURIComponent(started.userCode)}`;
  const secureScanUri =
    started.mode === "scan_secure" && started.scanPayload
      ? `nomade://scan?server=${encodeURIComponent(serverUrl)}&scan_payload=${encodeURIComponent(started.scanPayload)}${
          started.scanShortCode ? `&short_code=${encodeURIComponent(started.scanShortCode)}` : ""
        }`
      : verificationUriComplete;

  console.log("");
  console.log("Nomade device login");
  console.log("-------------------");
  console.log(`User code: ${started.userCode}`);
  if (started.mode === "scan_secure") {
    console.log("Scan the QR in the mobile app to approve and bootstrap E2E keys.");
    if (started.scanShortCode) {
      console.log(`Fallback short code: ${started.scanShortCode}`);
    }
    console.log("Secure scan is mandatory for this login; browser code approval is disabled.");
  } else {
    console.log(`Open this URL on any device: ${verificationUriComplete}`);
  }
  console.log(`Manual URL: ${verificationUri}`);
  console.log("");
  console.log("QR:");
  await printLocalQr(secureScanUri);
  console.log("");

  if (params.openBrowser && started.mode !== "scan_secure") {
    await openInBrowser(verificationUriComplete);
  }

  const intervalSec = started.intervalSec ?? 2;
  const expiresAtMs = Date.parse(started.expiresAt);
  let hostRootKeyBase64: string | null = reusableE2E?.rootKey ?? null;
  let hostBundleSent = false;
  let mobilePeer:
    | {
        deviceId: string;
        encPublicKey: string;
        signPublicKey: string;
      }
    | undefined;
  while (true) {
    if (Number.isFinite(expiresAtMs) && Date.now() >= expiresAtMs) {
      throw new Error("device_code_expired");
    }
    await sleep(intervalSec * 1000);
    const pollResponse = await fetch(`${serverUrl}/auth/device/poll`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceCode: started.deviceCode })
    });
    if (!pollResponse.ok) {
      const err = await parseApiError(pollResponse);
      if (pollResponse.status === 410 || err.message === "expired") {
        throw new Error("device_code_expired");
      }
      if (pollResponse.status === 429) {
        continue;
      }
      throw new Error(`login_poll_failed:${err.message}`);
    }
    const polled = devicePollSchema.parse(await pollResponse.json());
    if (polled.status === "pending") {
      continue;
    }
    if (polled.status === "pending_scan") {
      continue;
    }
    if (polled.status === "pending_key_exchange") {
      if (
        polled.mobileDeviceId &&
        polled.mobileEncPublicKey &&
        polled.mobileSignPublicKey
      ) {
        mobilePeer = {
          deviceId: polled.mobileDeviceId,
          encPublicKey: polled.mobileEncPublicKey,
          signPublicKey: polled.mobileSignPublicKey
        };
      }
      if (!hostBundleSent && polled.mobileExchangePublicKey) {
        hostRootKeyBase64 ??= toBase64Url(randomBytes(32));
        const sharedSecret = deriveSharedSecret({
          privateKey: exchangeKeyPair.privateKey,
          remotePublicKey: polled.mobileExchangePublicKey
        });
        const hostBundle = encryptScanBundle({
          sharedSecret,
          scope: `scan:${started.deviceCode}`,
          payload: {
            rootKey: hostRootKeyBase64,
            epoch: 1,
            hostDevice: {
              deviceId: hostDevice.deviceId,
              encPublicKey: hostDevice.encPublicKey,
              signPublicKey: hostDevice.signPublicKey
            }
          }
        });
        const hostCompleteResponse = await fetch(`${serverUrl}/auth/device/scan-host-complete`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            deviceCode: started.deviceCode,
            hostBundle
          })
        });
        if (!hostCompleteResponse.ok) {
          const err = await parseApiError(hostCompleteResponse);
          throw new Error(`login_scan_host_complete_failed:${err.message}`);
        }
        hostBundleSent = true;
        console.log("Scan approved. Completing secure key exchange...");
      }
      continue;
    }
    if (polled.status === "expired") {
      throw new Error("device_code_expired");
    }
    if (
      polled.status === "ok" &&
      polled.accessToken &&
      polled.refreshToken &&
      typeof polled.expiresInSec === "number"
    ) {
      const me = await fetchMe(serverUrl, polled.accessToken).catch(() => null);
      await saveSession({
        sessionPath,
        serverUrl,
        accessToken: polled.accessToken,
        refreshToken: polled.refreshToken,
        expiresInSec: polled.expiresInSec,
        email: me?.email,
        e2e:
          hostRootKeyBase64 && started.mode === "scan_secure"
            ? {
                epoch: 1,
                rootKey: hostRootKeyBase64,
                device: {
                  deviceId: hostDevice.deviceId,
                  encPublicKey: hostDevice.encPublicKey,
                  encPrivateKey: hostDevice.encPrivateKey,
                  signPublicKey: hostDevice.signPublicKey,
                  signPrivateKey: hostDevice.signPrivateKey,
                  createdAt: hostDevice.createdAt
                },
                peers: {
                  ...(reusableE2E?.peers ?? {}),
                  ...(mobilePeer
                    ? {
                        [mobilePeer.deviceId]: {
                          ...mobilePeer,
                          addedAt: new Date().toISOString()
                        }
                      }
                    : {})
                },
                seqByScope: reusableE2E?.seqByScope ?? {}
              }
            : undefined
      });
      console.log(`Logged in${me?.email ? ` as ${me.email}` : ""}. Session saved to ${sessionPath}`);
      return;
    }
  }
};

export const logoutSession = async (params: {
  serverUrl?: string;
  sessionPath?: string;
}): Promise<void> => {
  const sessionPath = params.sessionPath ?? defaultSessionPath();
  let session: UserSessionConfig | null = null;
  try {
    session = await readUserSession(sessionPath);
  } catch {
    session = null;
  }

  if (session) {
    const serverUrl = (params.serverUrl ?? session.controlHttpUrl).replace(/\/$/, "");
    try {
      await fetch(`${serverUrl}/auth/logout`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${session.accessToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({ refreshToken: session.refreshToken })
      });
    } catch {
      // best effort
    }
  }

  try {
    await fs.unlink(sessionPath);
  } catch {
    // no-op
  }
};

export const printWhoAmI = async (params: {
  serverUrl: string;
  sessionPath?: string;
}): Promise<void> => {
  const serverUrl = params.serverUrl.replace(/\/$/, "");
  const session = await ensureSession({ serverUrl, sessionPath: params.sessionPath });
  const me = await fetchMe(serverUrl, session.accessToken);
  const entitlementsResponse = await fetch(`${serverUrl}/me/entitlements`, {
    headers: { authorization: `Bearer ${session.accessToken}` }
  });
  if (!entitlementsResponse.ok) {
    const err = await parseApiError(entitlementsResponse);
    throw new Error(`fetch_entitlements_failed:${err.message}`);
  }
  const entitlements = entitlementsSchema.parse(await entitlementsResponse.json());
  console.log(`User: ${me.email} (${me.id})`);
  console.log(
    `Plan: ${entitlements.planCode} | Devices: ${entitlements.currentAgents}/${entitlements.maxAgents} | Limit reached: ${
      entitlements.limitReached ? "yes" : "no"
    }`
  );
};

export const createPairingCodeFromSession = async (params: {
  serverUrl: string;
  sessionPath?: string;
  _retriedAfterRefresh?: boolean;
}): Promise<{ pairingCode: string; expiresInSec: number }> => {
  const serverUrl = params.serverUrl.replace(/\/$/, "");
  const session = await ensureSession({ serverUrl, sessionPath: params.sessionPath });
  const response = await fetch(`${serverUrl}/agents/pair`, {
    method: "POST",
    headers: { authorization: `Bearer ${session.accessToken}` }
  });
  if (!response.ok) {
    const err = await parseApiError(response);
    if (response.status === 401 && !params._retriedAfterRefresh) {
      const refreshed = await refreshTokens(serverUrl, session.refreshToken);
      await saveSession({
        sessionPath: params.sessionPath ?? defaultSessionPath(),
        serverUrl,
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
        expiresInSec: refreshed.expiresInSec,
        email: session.email,
        e2e: session.e2e
      });
      return createPairingCodeFromSession({
        ...params,
        _retriedAfterRefresh: true
      });
    }
    if (response.status === 403 && err.message === "device_limit_reached") {
      const upgradeUrl = typeof err.payload.upgradeUrl === "string" ? err.payload.upgradeUrl : `${serverUrl}/web/account`;
      const currentAgents = Number(err.payload.currentAgents ?? 0);
      const maxAgents = Number(err.payload.maxAgents ?? 1);
      throw new Error(
        `device_limit_reached: ${currentAgents}/${maxAgents} devices registered on current plan. Upgrade at ${upgradeUrl}`
      );
    }
    throw new Error(`create_pairing_code_failed:${err.message}`);
  }
  const payload = (await response.json()) as Record<string, unknown>;
  const pairingCode = typeof payload.pairingCode === "string" ? payload.pairingCode : "";
  const expiresInSec = typeof payload.expiresInSec === "number" ? payload.expiresInSec : 600;
  if (!pairingCode) {
    throw new Error("create_pairing_code_failed:missing_pairing_code");
  }
  return { pairingCode, expiresInSec };
};
