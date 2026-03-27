export class TunnelManager {
  private readonly tunnelPorts = new Map<string, number>();

  openTunnel(tunnelId: string, targetPort: number): void {
    this.tunnelPorts.set(tunnelId, targetPort);
  }

  getPort(tunnelId: string): number | null {
    return this.tunnelPorts.get(tunnelId) ?? null;
  }
}
