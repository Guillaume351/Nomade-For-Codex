import { describe, expect, it } from "vitest";
import { AuthService } from "./auth.js";

describe("auth primitives", () => {
  it("returns verification URLs in device start payload", async () => {
    const service = new AuthService(
      {
        appBaseUrl: "https://app.example.com",
        accessTtlSec: 900,
        refreshTtlSec: 3600,
        deviceCodeTtlSec: 600,
        pairingCodeTtlSec: 600,
        databaseUrl: "",
        gatewaySecret: "",
        jwtSecret: "test_test_test_test_test_test",
        paidMaxAgents: 10,
        freeMaxAgents: 1,
        devLoginEnabled: false,
        legacyDeviceApproveEnabled: false,
        oidcEnabled: false,
        oidcScope: "openid",
        previewBaseDomain: "preview.localhost",
        previewBaseOrigin: "https://preview.localhost",
        port: 8080,
        webSessionCookieName: "nomade_web_session",
        webSessionTtlSec: 3600,
        stripeEnabled: false
      },
      {
        createDeviceCode: async () => ({
          deviceCode: "dc_1",
          userCode: "ABCD1234",
          expiresAt: new Date("2026-04-03T10:00:00.000Z"),
          mode: "legacy"
        })
      } as any
    );

    const value = await service.startDeviceCode();
    expect(value.deviceCode).toBe("dc_1");
    expect(value.userCode).toBe("ABCD1234");
    expect(value.verificationUri).toBe("https://app.example.com/web/activate");
    expect(value.verificationUriComplete).toContain("user_code=ABCD1234");
  });
});
