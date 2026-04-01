import { describe, expect, it, vi } from "vitest";
import type { DevServiceRecord, Repositories } from "./repositories.js";
import type { WsHub } from "./ws-hub.js";
import { DevServiceManager } from "./service-manager.js";

const buildService = (overrides: Partial<DevServiceRecord>): DevServiceRecord => {
  const now = new Date("2026-01-01T00:00:00.000Z");
  return {
    id: "svc-default",
    user_id: "user-1",
    workspace_id: "workspace-1",
    agent_id: "agent-1",
    name: "default",
    role: "service",
    command: "echo ok",
    cwd: null,
    port: 3000,
    health_path: "/health",
    env_template: {},
    depends_on: [],
    auto_tunnel: true,
    created_at: now,
    updated_at: now,
    ...overrides
  };
};

const createManager = (repositories: Partial<Repositories>): DevServiceManager => {
  return new DevServiceManager(repositories as Repositories, {} as WsHub, "preview.localhost");
};

describe("DevServiceManager template resolution", () => {
  it("resolves workspace and dependent service URLs", async () => {
    const backend = buildService({
      id: "svc-backend",
      name: "backend",
      port: 8080,
      auto_tunnel: true
    });

    const repositories: Partial<Repositories> = {
      findOpenTunnelByService: vi.fn().mockResolvedValue({
        id: "tnl-1",
        user_id: "user-1",
        workspace_id: "workspace-1",
        agent_id: "agent-1",
        service_id: "svc-backend",
        slug: "backend",
        target_port: 8080,
        access_token_hash: "hash",
        token_required: false,
        status: "open"
      }),
      createTunnel: vi.fn(),
      updateTunnelToken: vi.fn()
    };

    const manager = createManager(repositories);
    const context = {
      userId: "user-1",
      workspacePath: "/repo/workspace",
      servicesByName: new Map<string, DevServiceRecord>([["backend", backend]])
    };

    const publicUrl = await (manager as any).resolveTemplateValue(
      "API_URL=${service.backend.public_url}",
      context,
      true
    );
    const origin = await (manager as any).resolveTemplateValue(
      "${service.backend.public_origin}",
      context,
      true
    );
    const internalUrl = await (manager as any).resolveTemplateValue(
      "${service.backend.internal_url}",
      context,
      true
    );
    const workspacePath = await (manager as any).resolveTemplateValue(
      "${workspace.path}",
      context,
      true
    );

    expect(publicUrl).toBe("API_URL=https://backend.preview.localhost");
    expect(origin).toBe("https://backend.preview.localhost");
    expect(internalUrl).toBe("http://127.0.0.1:8080");
    expect(workspacePath).toBe("/repo/workspace");
    expect(repositories.createTunnel).not.toHaveBeenCalled();
  });

  it("throws when a referenced service does not exist", async () => {
    const manager = createManager({
      findOpenTunnelByService: vi.fn(),
      createTunnel: vi.fn(),
      updateTunnelToken: vi.fn()
    });

    const context = {
      userId: "user-1",
      workspacePath: "/repo/workspace",
      servicesByName: new Map<string, DevServiceRecord>()
    };

    await expect(
      (manager as any).resolveTemplateValue("${service.api.public_url}", context, true)
    ).rejects.toThrow("unknown_service_dependency:api");
  });
});

describe("DevServiceManager dependency graph", () => {
  it("rejects dependency cycles", () => {
    const web = buildService({
      id: "svc-web",
      name: "web",
      depends_on: ["api"]
    });
    const api = buildService({
      id: "svc-api",
      name: "api",
      depends_on: ["web"]
    });

    const services = new Map<string, DevServiceRecord>([
      ["web", web],
      ["api", api]
    ]);

    const manager = createManager({});
    expect(() => (manager as any).resolveDependencyOrder(web, services)).toThrow(
      "service_dependency_cycle:web"
    );
  });
});
