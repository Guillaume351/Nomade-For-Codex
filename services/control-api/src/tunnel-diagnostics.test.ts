import { describe, expect, it } from "vitest";
import {
  buildTransportTunnelDiagnostic,
  classifyProxyResponseDiagnostic,
  normalizeTransportTunnelErrorCode
} from "./tunnel-diagnostics.js";

describe("normalizeTransportTunnelErrorCode", () => {
  it("keeps ws unexpected response status code", () => {
    expect(normalizeTransportTunnelErrorCode("127.0.0.1:tunnel_ws_unexpected_response_403")).toBe(
      "tunnel_ws_unexpected_response_403"
    );
  });

  it("maps local loopback connectivity failures to stable code", () => {
    expect(normalizeTransportTunnelErrorCode("localhost: connect ECONNREFUSED 127.0.0.1:3000")).toBe(
      "local_service_unreachable"
    );
    expect(normalizeTransportTunnelErrorCode("local_service_unreachable")).toBe("local_service_unreachable");
  });
});

describe("buildTransportTunnelDiagnostic", () => {
  it("renders deterministic message for ws unexpected responses", () => {
    const diagnostic = buildTransportTunnelDiagnostic({
      rawError: "tunnel_ws_unexpected_response_400",
      now: new Date("2026-04-02T12:00:00.000Z")
    });

    expect(diagnostic.code).toBe("tunnel_ws_unexpected_response_400");
    expect(diagnostic.scope).toBe("transport");
    expect(diagnostic.message).toContain("400");
    expect(diagnostic.timestamp).toBe("2026-04-02T12:00:00.000Z");
  });
});

describe("classifyProxyResponseDiagnostic", () => {
  it("detects vite svg react transform mismatch", () => {
    const diagnostic = classifyProxyResponseDiagnostic({
      request: {
        path: "/src/assets/spinner.svg",
        query: "import&react"
      },
      response: {
        headers: {
          "content-type": "image/svg+xml"
        }
      }
    });

    expect(diagnostic).not.toBeNull();
    expect(diagnostic?.code).toBe("vite_svg_react_not_transformed");
    expect(diagnostic?.scope).toBe("upstream_app");
  });

  it("does not emit diagnostics for regular js modules", () => {
    const diagnostic = classifyProxyResponseDiagnostic({
      request: {
        path: "/src/main.tsx",
        query: "t=123"
      },
      response: {
        headers: {
          "content-type": "application/javascript"
        }
      }
    });

    expect(diagnostic).toBeNull();
  });
});
