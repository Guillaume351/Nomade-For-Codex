import { randomToken } from "@nomade/shared";
import type {
  DevServiceRecord,
  DevServiceRuntimeRecord,
  Repositories,
  SessionRecord,
  TunnelRecord
} from "./repositories.js";
import type { WsHub } from "./ws-hub.js";

export type ServiceHealthState = "stopped" | "starting" | "healthy" | "unhealthy" | "crashed";

export interface ServiceStateView {
  id: string;
  workspaceId: string;
  agentId: string;
  name: string;
  role: string;
  command: string;
  cwd: string | null;
  port: number;
  healthPath: string;
  envTemplate: Record<string, string>;
  dependsOn: string[];
  autoTunnel: boolean;
  state: ServiceHealthState;
  runtimeStatus: string;
  lastError: string | null;
  tunnel: null | {
    id: string;
    slug: string;
    previewUrl: string;
    tokenRequired: boolean;
    isReachable: boolean;
    lastProbeAt: string | null;
    lastProbeStatus: string | null;
    lastError: string | null;
    lastProbeCode: number | null;
  };
  session: null | {
    id: string;
    status: string;
    cursor: number;
  };
}

interface StartContext {
  userId: string;
  workspacePath: string;
  servicesByName: Map<string, DevServiceRecord>;
}

const healthPathOrDefault = (value: string | null | undefined): string => {
  const raw = (value ?? "").trim();
  if (!raw) {
    return "/";
  }
  if (raw.startsWith("/")) {
    return raw;
  }
  return `/${raw}`;
};

export class DevServiceManager {
  private readonly probeTimers = new Map<string, NodeJS.Timeout>();
  private readonly issuedTunnelTokens = new Map<string, string>();
  private readonly probeIntervalMs = 5000;

  constructor(
    private readonly repositories: Repositories,
    private readonly wsHub: WsHub,
    private readonly previewBaseDomain: string
  ) {}

  async listWorkspaceServices(userId: string, workspaceId: string): Promise<ServiceStateView[] | null> {
    const workspace = await this.repositories.findWorkspaceById(userId, workspaceId);
    if (!workspace) {
      return null;
    }

    const services = await this.repositories.listDevServices(userId, workspaceId);
    const states = await Promise.all(services.map((service) => this.getServiceState(userId, service.id)));
    return states.filter((state): state is ServiceStateView => Boolean(state));
  }

  async getServiceState(userId: string, serviceId: string): Promise<ServiceStateView | null> {
    const service = await this.repositories.findDevServiceById(userId, serviceId);
    if (!service) {
      return null;
    }

    const runtime = await this.repositories.getServiceRuntime(service.id);
    let session: SessionRecord | null = null;
    if (runtime?.session_id) {
      session = await this.repositories.getSessionById(runtime.session_id);
    }

    let tunnel: TunnelRecord | null = null;
    if (runtime?.tunnel_id) {
      tunnel = await this.repositories.findTunnelByIdForUser(userId, runtime.tunnel_id);
    }
    if (!tunnel && service.auto_tunnel) {
      tunnel = await this.repositories.findOpenTunnelByService(service.id);
    }

    const state = this.deriveState(runtime, session, tunnel);

    return {
      id: service.id,
      workspaceId: service.workspace_id,
      agentId: service.agent_id,
      name: service.name,
      role: service.role,
      command: service.command,
      cwd: service.cwd,
      port: service.port,
      healthPath: service.health_path,
      envTemplate: service.env_template,
      dependsOn: service.depends_on,
      autoTunnel: service.auto_tunnel,
      state,
      runtimeStatus: runtime?.status ?? "stopped",
      lastError: runtime?.last_error ?? null,
      tunnel: tunnel
        ? {
            id: tunnel.id,
            slug: tunnel.slug,
            previewUrl: this.previewOrigin(tunnel.slug),
            tokenRequired: tunnel.token_required,
            isReachable: tunnel.last_probe_status === "ok",
            lastProbeAt: tunnel.last_probe_at ? tunnel.last_probe_at.toISOString() : null,
            lastProbeStatus: tunnel.last_probe_status ?? null,
            lastError: tunnel.last_probe_error ?? null,
            lastProbeCode: tunnel.last_probe_code ?? null
          }
        : null,
      session: session
        ? {
            id: session.id,
            status: session.status,
            cursor: session.cursor
          }
        : null
    };
  }

  async startService(userId: string, serviceId: string): Promise<ServiceStateView | null> {
    const service = await this.repositories.findDevServiceById(userId, serviceId);
    if (!service) {
      return null;
    }

    const workspace = await this.repositories.findWorkspaceById(userId, service.workspace_id);
    if (!workspace) {
      return null;
    }

    const allServices = await this.repositories.listDevServices(userId, service.workspace_id);
    const servicesByName = new Map<string, DevServiceRecord>();
    for (const item of allServices) {
      servicesByName.set(item.name, item);
    }

    const chain = this.resolveDependencyOrder(service, servicesByName);
    const context: StartContext = {
      userId,
      workspacePath: workspace.path,
      servicesByName
    };

    for (const item of chain) {
      await this.startSingleService(item, context);
    }

    return this.getServiceState(userId, serviceId);
  }

  async stopService(userId: string, serviceId: string): Promise<ServiceStateView | null> {
    const service = await this.repositories.findDevServiceById(userId, serviceId);
    if (!service) {
      return null;
    }

    const runtime = await this.repositories.getServiceRuntime(service.id);
    if (runtime?.session_id) {
      this.wsHub.sendToAgent(service.agent_id, {
        type: "session.terminate",
        sessionId: runtime.session_id
      });
    }

    this.stopProbeTimer(service.id);
    await this.repositories.upsertServiceRuntime({
      serviceId: service.id,
      sessionId: null,
      tunnelId: runtime?.tunnel_id ?? null,
      status: "stopped",
      lastError: null
    });

    if (runtime?.tunnel_id) {
      await this.repositories.updateTunnelProbe({
        tunnelId: runtime.tunnel_id,
        probeStatus: "unknown",
        error: "service_stopped"
      });
      this.wsHub.publishTunnelStatus(runtime.tunnel_id, {
        status: "stopped",
        detail: `Service ${service.name} stopped`,
        probeStatus: "unknown"
      });
    }

    return this.getServiceState(userId, service.id);
  }

  async issueTunnelToken(userId: string, tunnelId: string): Promise<{ token: string; previewUrl: string } | null> {
    const tunnel = await this.repositories.findTunnelByIdForUser(userId, tunnelId);
    if (!tunnel) {
      return null;
    }

    const token = randomToken("tp");
    await this.repositories.updateTunnelToken(tunnelId, token);
    this.issuedTunnelTokens.set(tunnelId, token);

    const origin = this.previewOrigin(tunnel.slug);
    const previewUrl = tunnel.token_required
      ? `${origin}?nomade_token=${encodeURIComponent(token)}`
      : origin;

    return {
      token,
      previewUrl
    };
  }

  async rotateTunnelToken(userId: string, tunnelId: string): Promise<{ token: string; previewUrl: string } | null> {
    return this.issueTunnelToken(userId, tunnelId);
  }

  async closeTunnel(userId: string, tunnelId: string): Promise<boolean> {
    const tunnel = await this.repositories.findTunnelByIdForUser(userId, tunnelId);
    if (!tunnel) {
      return false;
    }

    this.issuedTunnelTokens.delete(tunnelId);
    await this.repositories.updateTunnelStatus(tunnelId, "closed");

    if (tunnel.service_id) {
      const runtime = await this.repositories.getServiceRuntime(tunnel.service_id);
      if (runtime) {
        await this.repositories.upsertServiceRuntime({
          serviceId: tunnel.service_id,
          sessionId: runtime.session_id,
          tunnelId: null,
          status: runtime.status,
          lastError: runtime.last_error
        });
      }
    }

    this.wsHub.publishTunnelStatus(tunnelId, {
      status: "closed",
      detail: "Tunnel closed"
    });

    return this.repositories.deleteTunnel(tunnelId, userId);
  }

  private async startSingleService(service: DevServiceRecord, context: StartContext): Promise<void> {
    const currentState = await this.getServiceState(context.userId, service.id);
    if (currentState && (currentState.state === "starting" || currentState.state === "healthy")) {
      return;
    }

    const settings = await this.repositories.getWorkspaceDevSettings(context.userId, service.workspace_id);
    const tokenRequired = !(settings?.trusted_dev_mode ?? false);

    let tunnel: TunnelRecord | null = null;
    if (service.auto_tunnel) {
      tunnel = await this.repositories.findOpenTunnelByService(service.id);
      if (!tunnel) {
        const created = await this.repositories.createTunnel({
          userId: context.userId,
          workspaceId: service.workspace_id,
          agentId: service.agent_id,
          serviceId: service.id,
          targetPort: service.port,
          tokenRequired
        });
        tunnel = created.tunnel;
        if (tokenRequired) {
          this.issuedTunnelTokens.set(tunnel.id, created.accessToken);
        }
      }

      this.wsHub.rememberTunnelOwner(tunnel.id, context.userId);
      const delivered = this.wsHub.sendToAgent(service.agent_id, {
        type: "tunnel.open",
        tunnelId: tunnel.id,
        slug: tunnel.slug,
        targetPort: service.port
      });
      if (!delivered) {
        await this.repositories.updateTunnelStatus(tunnel.id, "error");
        throw new Error("agent_offline");
      }
    }

    const env = await this.resolveServiceEnv(service, context, tokenRequired);

    const session = await this.repositories.createSession({
      userId: context.userId,
      workspaceId: service.workspace_id,
      agentId: service.agent_id,
      name: `service:${service.name}`
    });

    this.wsHub.rememberSessionOwner(session.id, context.userId, service.agent_id);
    const delivered = this.wsHub.sendToAgent(service.agent_id, {
      type: "session.create",
      sessionId: session.id,
      workspaceId: service.workspace_id,
      agentId: service.agent_id,
      command: service.command,
      cwd: service.cwd ?? context.workspacePath,
      env
    });

    if (!delivered) {
      await this.repositories.updateSessionStatus(session.id, "failed");
      await this.repositories.upsertServiceRuntime({
        serviceId: service.id,
        sessionId: session.id,
        tunnelId: tunnel?.id ?? null,
        status: "crashed",
        lastError: "agent_offline"
      });
      throw new Error("agent_offline");
    }

    await this.repositories.upsertServiceRuntime({
      serviceId: service.id,
      sessionId: session.id,
      tunnelId: tunnel?.id ?? null,
      status: tunnel ? "starting" : "running",
      lastError: null
    });

    if (tunnel) {
      this.wsHub.publishTunnelStatus(tunnel.id, {
        status: "starting",
        detail: `Service ${service.name} is starting`,
        probeStatus: "unknown"
      });
      this.startProbe(service, session.id, tunnel.id);
    }
  }

  private async resolveServiceEnv(
    service: DevServiceRecord,
    context: StartContext,
    tokenRequiredFallback: boolean
  ): Promise<Record<string, string>> {
    const env: Record<string, string> = {};
    const entries = Object.entries(service.env_template ?? {});
    for (const [key, value] of entries) {
      env[key] = await this.resolveTemplateValue(value, context, tokenRequiredFallback);
    }
    return env;
  }

  private async resolveTemplateValue(value: string, context: StartContext, tokenRequiredFallback: boolean): Promise<string> {
    const pattern = /\$\{([^}]+)\}/g;
    let out = value;
    let match: RegExpExecArray | null;

    // eslint-disable-next-line no-cond-assign
    while ((match = pattern.exec(value)) !== null) {
      const token = match[1]?.trim() ?? "";
      let replacement: string | null = null;

      if (token === "workspace.path") {
        replacement = context.workspacePath;
      } else if (token.startsWith("service.")) {
        const parts = token.split(".");
        if (parts.length !== 3) {
          throw new Error(`invalid_service_template:${token}`);
        }
        const serviceName = parts[1];
        const field = parts[2];
        const depService = context.servicesByName.get(serviceName);
        if (!depService) {
          throw new Error(`unknown_service_dependency:${serviceName}`);
        }
        let tunnel = await this.repositories.findOpenTunnelByService(depService.id);
        if (!tunnel && depService.auto_tunnel) {
          const created = await this.repositories.createTunnel({
            userId: context.userId,
            workspaceId: depService.workspace_id,
            agentId: depService.agent_id,
            serviceId: depService.id,
            targetPort: depService.port,
            tokenRequired: tokenRequiredFallback
          });
          tunnel = created.tunnel;
          if (tunnel.token_required) {
            this.issuedTunnelTokens.set(tunnel.id, created.accessToken);
          }
        }

        if (field === "internal_url") {
          replacement = `http://127.0.0.1:${depService.port}`;
        } else {
          if (!tunnel) {
            throw new Error(`missing_tunnel_for:${serviceName}`);
          }
          const origin = this.previewOrigin(tunnel.slug);
          if (field === "public_origin") {
            replacement = origin;
          } else if (field === "public_url") {
            if (!tunnel.token_required) {
              replacement = origin;
            } else {
              let issued = this.issuedTunnelTokens.get(tunnel.id);
              if (!issued) {
                issued = randomToken("tp");
                await this.repositories.updateTunnelToken(tunnel.id, issued);
                this.issuedTunnelTokens.set(tunnel.id, issued);
              }
              replacement = `${origin}?nomade_token=${encodeURIComponent(issued)}`;
            }
          } else {
            throw new Error(`unsupported_service_field:${field}`);
          }
        }
      }

      if (replacement === null) {
        throw new Error(`unresolved_template_token:${token}`);
      }
      out = out.replace(match[0], replacement);
    }

    return out;
  }

  private resolveDependencyOrder(
    root: DevServiceRecord,
    servicesByName: Map<string, DevServiceRecord>
  ): DevServiceRecord[] {
    const ordered: DevServiceRecord[] = [];
    const visiting = new Set<string>();
    const visited = new Set<string>();

    const visit = (service: DevServiceRecord): void => {
      if (visited.has(service.id)) {
        return;
      }
      if (visiting.has(service.id)) {
        throw new Error(`service_dependency_cycle:${service.name}`);
      }
      visiting.add(service.id);
      for (const depName of service.depends_on) {
        const dep = servicesByName.get(depName);
        if (!dep) {
          throw new Error(`service_dependency_not_found:${depName}`);
        }
        visit(dep);
      }
      visiting.delete(service.id);
      visited.add(service.id);
      ordered.push(service);
    };

    visit(root);
    return ordered;
  }

  private deriveState(
    runtime: DevServiceRuntimeRecord | null,
    session: SessionRecord | null,
    tunnel: TunnelRecord | null
  ): ServiceHealthState {
    if (!runtime) {
      return "stopped";
    }

    const runtimeStatus = runtime.status;
    if (runtimeStatus === "stopped") {
      return "stopped";
    }
    if (runtimeStatus === "crashed") {
      return "crashed";
    }
    if (session && session.status !== "running") {
      return "crashed";
    }

    if (!tunnel && runtimeStatus === "running") {
      return "healthy";
    }

    if (tunnel) {
      if (tunnel.last_probe_status === "ok") {
        return "healthy";
      }
      if (tunnel.last_probe_status === "error") {
        return "unhealthy";
      }
    }

    return "starting";
  }

  private previewOrigin(slug: string): string {
    return `https://${slug}.${this.previewBaseDomain}`;
  }

  private startProbe(service: DevServiceRecord, sessionId: string, tunnelId: string): void {
    this.stopProbeTimer(service.id);

    const runProbe = async (): Promise<void> => {
      const runtime = await this.repositories.getServiceRuntime(service.id);
      if (!runtime || runtime.session_id !== sessionId) {
        this.stopProbeTimer(service.id);
        return;
      }

      const session = await this.repositories.getSessionById(sessionId);
      if (!session || session.status !== "running") {
        await this.repositories.upsertServiceRuntime({
          serviceId: service.id,
          sessionId,
          tunnelId,
          status: "crashed",
          lastError: `session_${session?.status ?? "missing"}`
        });
        await this.repositories.updateTunnelProbe({
          tunnelId,
          probeStatus: "error",
          error: `session_${session?.status ?? "missing"}`
        });
        this.wsHub.publishTunnelStatus(tunnelId, {
          status: "unhealthy",
          detail: `Service ${service.name} crashed`,
          probeStatus: "error"
        });
        this.stopProbeTimer(service.id);
        return;
      }

      try {
        const proxied = await this.wsHub.proxyHttpThroughAgent({
          agentId: service.agent_id,
          tunnelId,
          method: "GET",
          path: healthPathOrDefault(service.health_path),
          headers: {
            accept: "application/json"
          }
        });

        if (proxied.status >= 200 && proxied.status < 400) {
          await this.repositories.updateTunnelProbe({
            tunnelId,
            probeStatus: "ok",
            probeCode: proxied.status
          });
          await this.repositories.upsertServiceRuntime({
            serviceId: service.id,
            sessionId,
            tunnelId,
            status: "running",
            lastError: null
          });
          this.wsHub.publishTunnelStatus(tunnelId, {
            status: "healthy",
            detail: `Service ${service.name} healthy`,
            probeStatus: "ok",
            probeCode: proxied.status
          });
          return;
        }

        await this.repositories.updateTunnelProbe({
          tunnelId,
          probeStatus: "error",
          probeCode: proxied.status,
          error: `health_http_${proxied.status}`
        });
        await this.repositories.upsertServiceRuntime({
          serviceId: service.id,
          sessionId,
          tunnelId,
          status: "running",
          lastError: `health_http_${proxied.status}`
        });
        this.wsHub.publishTunnelStatus(tunnelId, {
          status: "unhealthy",
          detail: `Health check failed (${proxied.status})`,
          probeStatus: "error",
          probeCode: proxied.status
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : "health_probe_failed";
        await this.repositories.updateTunnelProbe({
          tunnelId,
          probeStatus: "error",
          error: message
        });
        await this.repositories.upsertServiceRuntime({
          serviceId: service.id,
          sessionId,
          tunnelId,
          status: "running",
          lastError: message
        });
        this.wsHub.publishTunnelStatus(tunnelId, {
          status: "unhealthy",
          detail: message,
          probeStatus: "error"
        });
      }
    };

    void runProbe();
    const timer = setInterval(() => {
      void runProbe();
    }, this.probeIntervalMs);
    this.probeTimers.set(service.id, timer);
  }

  private stopProbeTimer(serviceId: string): void {
    const timer = this.probeTimers.get(serviceId);
    if (!timer) {
      return;
    }
    clearInterval(timer);
    this.probeTimers.delete(serviceId);
  }
}
