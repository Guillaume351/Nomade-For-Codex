import { createHash, hkdfSync, randomBytes } from "node:crypto";
import { xchacha20poly1305 } from "@noble/ciphers/chacha.js";
import { ed25519, x25519 } from "@noble/curves/ed25519.js";
import { newId } from "./ids.js";
import type { E2EEnvelope } from "./types.js";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const E2E_CONTEXT = "nomade-e2e-v1";
const SCAN_EXCHANGE_CONTEXT = "nomade-scan-exchange-v1";

export interface DeviceKeyMaterial {
  deviceId: string;
  encPublicKey: string;
  encPrivateKey: string;
  signPublicKey: string;
  signPrivateKey: string;
  createdAt: string;
}

export interface ExchangeKeyPair {
  publicKey: string;
  privateKey: string;
}

export interface ScanEncryptedBundle {
  alg: "xchacha20poly1305";
  nonce: string;
  aad: string;
  ciphertext: string;
}

const ensureBuffer = (value: Uint8Array): Uint8Array => {
  if (value instanceof Uint8Array) {
    return value;
  }
  return new Uint8Array(value);
};

export const toBase64Url = (value: Uint8Array): string =>
  Buffer.from(value)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");

export const fromBase64Url = (value: string): Uint8Array => {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized + "===".slice((normalized.length + 3) % 4);
  return new Uint8Array(Buffer.from(padded, "base64"));
};

const canonicalize = (value: unknown): string => {
  if (value === null || value === undefined) {
    return "null";
  }
  if (typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalize(entry)).join(",")}]`;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, entry]) => entry !== undefined)
      .sort(([left], [right]) => left.localeCompare(right));
    return `{${entries
      .map(([key, entry]) => `${JSON.stringify(key)}:${canonicalize(entry)}`)
      .join(",")}}`;
  }
  return JSON.stringify(String(value));
};

export const generateDeviceKeyMaterial = (): DeviceKeyMaterial => {
  const encPrivate = x25519.utils.randomSecretKey();
  const encPublic = x25519.getPublicKey(encPrivate);
  const signPrivate = ed25519.utils.randomSecretKey();
  const signPublic = ed25519.getPublicKey(signPrivate);
  return {
    deviceId: `dev_${newId()}`,
    encPublicKey: toBase64Url(encPublic),
    encPrivateKey: toBase64Url(encPrivate),
    signPublicKey: toBase64Url(signPublic),
    signPrivateKey: toBase64Url(signPrivate),
    createdAt: new Date().toISOString()
  };
};

export const generateExchangeKeyPair = (): ExchangeKeyPair => {
  const privateKey = x25519.utils.randomSecretKey();
  const publicKey = x25519.getPublicKey(privateKey);
  return {
    publicKey: toBase64Url(publicKey),
    privateKey: toBase64Url(privateKey)
  };
};

export const deriveSharedSecret = (params: { privateKey: string; remotePublicKey: string }): Uint8Array => {
  const privateKey = fromBase64Url(params.privateKey);
  const remotePublicKey = fromBase64Url(params.remotePublicKey);
  const shared = x25519.getSharedSecret(privateKey, remotePublicKey);
  return ensureBuffer(shared);
};

const deriveScopedKey = (params: {
  rootKey: Uint8Array;
  epoch: number;
  scope: string;
  context: string;
}): Uint8Array => {
  const salt = textEncoder.encode(`${params.context}:epoch:${params.epoch}`);
  const info = textEncoder.encode(params.scope);
  return new Uint8Array(hkdfSync("sha256", params.rootKey, salt, info, 32));
};

const signEnvelope = (params: {
  payload: Omit<E2EEnvelope, "sig">;
  signPrivateKey: string;
}): string => {
  const body = textEncoder.encode(canonicalize(params.payload));
  const privateKey = fromBase64Url(params.signPrivateKey);
  const signature = ed25519.sign(body, privateKey);
  return toBase64Url(signature);
};

export const verifyEnvelopeSignature = (params: {
  payload: Omit<E2EEnvelope, "sig">;
  sig: string;
  signPublicKey: string;
}): boolean => {
  const body = textEncoder.encode(canonicalize(params.payload));
  const signature = fromBase64Url(params.sig);
  const publicKey = fromBase64Url(params.signPublicKey);
  return ed25519.verify(signature, body, publicKey);
};

export const encryptEnvelope = (params: {
  rootKey: Uint8Array;
  epoch: number;
  scope: string;
  senderDeviceId: string;
  seq: number;
  plaintext: string;
  aad?: Record<string, unknown>;
  signPrivateKey: string;
}): E2EEnvelope => {
  const nonce = randomBytes(24);
  const aad = textEncoder.encode(canonicalize(params.aad ?? {}));
  const key = deriveScopedKey({
    rootKey: params.rootKey,
    epoch: params.epoch,
    scope: params.scope,
    context: E2E_CONTEXT
  });
  const cipher = xchacha20poly1305(key, nonce, aad);
  const ciphertext = cipher.encrypt(textEncoder.encode(params.plaintext));
  const payload: Omit<E2EEnvelope, "sig"> = {
    v: 1,
    alg: "xchacha20poly1305",
    epoch: params.epoch,
    senderDeviceId: params.senderDeviceId,
    seq: params.seq,
    nonce: toBase64Url(nonce),
    aad: toBase64Url(aad),
    ciphertext: toBase64Url(ciphertext)
  };
  return {
    ...payload,
    sig: signEnvelope({ payload, signPrivateKey: params.signPrivateKey })
  };
};

export const decryptEnvelope = (params: {
  rootKey: Uint8Array;
  scope: string;
  envelope: E2EEnvelope;
  senderSignPublicKey: string;
}): string => {
  const payload: Omit<E2EEnvelope, "sig"> = {
    v: params.envelope.v,
    alg: params.envelope.alg,
    epoch: params.envelope.epoch,
    senderDeviceId: params.envelope.senderDeviceId,
    seq: params.envelope.seq,
    nonce: params.envelope.nonce,
    aad: params.envelope.aad,
    ciphertext: params.envelope.ciphertext
  };
  if (
    !verifyEnvelopeSignature({
      payload,
      sig: params.envelope.sig,
      signPublicKey: params.senderSignPublicKey
    })
  ) {
    throw new Error("e2e_invalid_signature");
  }
  const key = deriveScopedKey({
    rootKey: params.rootKey,
    epoch: params.envelope.epoch,
    scope: params.scope,
    context: E2E_CONTEXT
  });
  const nonce = fromBase64Url(params.envelope.nonce);
  const aad = fromBase64Url(params.envelope.aad);
  const ciphertext = fromBase64Url(params.envelope.ciphertext);
  const cipher = xchacha20poly1305(key, nonce, aad);
  const plaintext = cipher.decrypt(ciphertext);
  return textDecoder.decode(plaintext);
};

export const encryptScanBundle = (params: {
  sharedSecret: Uint8Array;
  scope: string;
  payload: Record<string, unknown>;
}): ScanEncryptedBundle => {
  const nonce = randomBytes(24);
  const aadValue = canonicalize({
    scope: params.scope,
    v: 1
  });
  const aad = textEncoder.encode(aadValue);
  const key = deriveScopedKey({
    rootKey: params.sharedSecret,
    epoch: 1,
    scope: params.scope,
    context: SCAN_EXCHANGE_CONTEXT
  });
  const cipher = xchacha20poly1305(key, nonce, aad);
  const ciphertext = cipher.encrypt(textEncoder.encode(canonicalize(params.payload)));
  return {
    alg: "xchacha20poly1305",
    nonce: toBase64Url(nonce),
    aad: toBase64Url(aad),
    ciphertext: toBase64Url(ciphertext)
  };
};

export const decryptScanBundle = (params: {
  sharedSecret: Uint8Array;
  scope: string;
  bundle: ScanEncryptedBundle;
}): Record<string, unknown> => {
  const key = deriveScopedKey({
    rootKey: params.sharedSecret,
    epoch: 1,
    scope: params.scope,
    context: SCAN_EXCHANGE_CONTEXT
  });
  const nonce = fromBase64Url(params.bundle.nonce);
  const aad = fromBase64Url(params.bundle.aad);
  const ciphertext = fromBase64Url(params.bundle.ciphertext);
  const cipher = xchacha20poly1305(key, nonce, aad);
  const plaintext = cipher.decrypt(ciphertext);
  const decoded = JSON.parse(textDecoder.decode(plaintext)) as Record<string, unknown>;
  return decoded;
};

export const sha256Base64Url = (value: string): string =>
  toBase64Url(createHash("sha256").update(value).digest());
