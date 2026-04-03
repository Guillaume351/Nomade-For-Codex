import { describe, expect, it } from "vitest";
import { normalizeTunnelHttpProxyError, normalizeTunnelWsOpenError } from "./runner.js";

describe("normalizeTunnelHttpProxyError", () => {
  it("maps loopback network failures to local_service_unreachable", () => {
    const code = normalizeTunnelHttpProxyError([
      {
        message: "127.0.0.1:fetch failed",
        code: "ECONNREFUSED"
      }
    ]);
    expect(code).toBe("local_service_unreachable");
  });

  it("keeps generic code for non-network failures", () => {
    const code = normalizeTunnelHttpProxyError([
      {
        message: "127.0.0.1:invalid response payload"
      }
    ]);
    expect(code).toBe("local_fetch_failed");
  });
});

describe("normalizeTunnelWsOpenError", () => {
  it("keeps ws unexpected response status", () => {
    const code = normalizeTunnelWsOpenError([
      {
        message: "127.0.0.1:tunnel_ws_unexpected_response_400"
      }
    ]);
    expect(code).toBe("tunnel_ws_unexpected_response_400");
  });

  it("maps timeout error", () => {
    const code = normalizeTunnelWsOpenError([
      {
        message: "localhost:tunnel_ws_open_timeout"
      }
    ]);
    expect(code).toBe("tunnel_ws_open_timeout");
  });

  it("maps loopback connectivity failures", () => {
    const code = normalizeTunnelWsOpenError([
      {
        message: "[::1]:connect ECONNREFUSED 127.0.0.1:5173",
        code: "ECONNREFUSED"
      }
    ]);
    expect(code).toBe("local_service_unreachable");
  });
});
