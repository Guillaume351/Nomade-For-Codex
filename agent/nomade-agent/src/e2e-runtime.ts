import {
  decryptEnvelope,
  encryptEnvelope,
  fromBase64Url,
  type E2EEnvelope
} from "@nomade/shared";
import type { UserSessionConfig } from "./config.js";

interface E2EPeerSnapshot {
  signPublicKey: string;
}

export class E2ERuntime {
  private readonly rootKey: Uint8Array;
  private readonly epoch: number;
  private readonly selfDeviceId: string;
  private readonly selfSignPublicKey: string;
  private readonly selfSignPrivateKey: string;
  private readonly peers = new Map<string, E2EPeerSnapshot>();
  private readonly seqByScope = new Map<string, number>();
  private readonly lastSeenSeqBySenderScope = new Map<string, number>();

  constructor(state: NonNullable<UserSessionConfig["e2e"]>) {
    this.rootKey = fromBase64Url(state.rootKey);
    this.epoch = Math.max(1, Number(state.epoch ?? 1));
    this.selfDeviceId = state.device.deviceId;
    this.selfSignPublicKey = state.device.signPublicKey;
    this.selfSignPrivateKey = state.device.signPrivateKey;

    for (const [scope, rawSeq] of Object.entries(state.seqByScope ?? {})) {
      const seq = Math.max(0, Number(rawSeq ?? 0));
      this.seqByScope.set(scope, seq);
    }

    for (const peer of Object.values(state.peers ?? {})) {
      if (!peer?.deviceId || !peer.signPublicKey) {
        continue;
      }
      this.peers.set(peer.deviceId, {
        signPublicKey: peer.signPublicKey
      });
    }
  }

  encrypt(scope: string, plaintext: string): E2EEnvelope {
    const seq = (this.seqByScope.get(scope) ?? 0) + 1;
    this.seqByScope.set(scope, seq);
    return encryptEnvelope({
      rootKey: this.rootKey,
      epoch: this.epoch,
      scope,
      senderDeviceId: this.selfDeviceId,
      seq,
      plaintext,
      signPrivateKey: this.selfSignPrivateKey
    });
  }

  decrypt(scope: string, envelope: E2EEnvelope): string {
    const key = `${scope}:${envelope.senderDeviceId}`;
    const lastSeenSeq = this.lastSeenSeqBySenderScope.get(key) ?? -1;
    if (envelope.seq <= lastSeenSeq) {
      throw new Error("e2e_replay_detected");
    }

    const senderSignPublicKey = this.resolveSignPublicKey(envelope.senderDeviceId);
    const plaintext = decryptEnvelope({
      rootKey: this.rootKey,
      scope,
      envelope,
      senderSignPublicKey
    });
    this.lastSeenSeqBySenderScope.set(key, envelope.seq);
    return plaintext;
  }

  private resolveSignPublicKey(senderDeviceId: string): string {
    if (senderDeviceId === this.selfDeviceId) {
      return this.selfSignPublicKey;
    }
    const peer = this.peers.get(senderDeviceId);
    if (!peer) {
      throw new Error(`e2e_unknown_sender_device:${senderDeviceId}`);
    }
    return peer.signPublicKey;
  }
}

export const createE2ERuntime = (session?: UserSessionConfig["e2e"]): E2ERuntime | null => {
  if (!session || !session.rootKey || !session.device?.deviceId || !session.device?.signPrivateKey) {
    return null;
  }
  return new E2ERuntime(session);
};

