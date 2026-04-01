import type WebSocket from "ws";

export class TunnelManager {
  private readonly tunnelPorts = new Map<string, number>();
  private readonly tunnelSockets = new Map<string, WebSocket>();

  openTunnel(tunnelId: string, targetPort: number): void {
    this.tunnelPorts.set(tunnelId, targetPort);
  }

  getPort(tunnelId: string): number | null {
    return this.tunnelPorts.get(tunnelId) ?? null;
  }

  bindSocket(connectionId: string, socket: WebSocket): void {
    this.tunnelSockets.set(connectionId, socket);
  }

  getSocket(connectionId: string): WebSocket | null {
    return this.tunnelSockets.get(connectionId) ?? null;
  }

  closeSocket(connectionId: string, code?: number, reason?: string): void {
    const socket = this.tunnelSockets.get(connectionId);
    if (!socket) {
      return;
    }
    try {
      socket.close(code, reason);
    } catch {
      // ignore
    }
    this.tunnelSockets.delete(connectionId);
  }

  unbindSocket(connectionId: string): void {
    this.tunnelSockets.delete(connectionId);
  }
}
