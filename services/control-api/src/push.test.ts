import { describe, expect, it } from "vitest";
import { createPushGateway } from "./push.js";

describe("createPushGateway", () => {
  it("returns disabled gateway when firebase config is missing", async () => {
    const gateway = createPushGateway({});
    expect(gateway.enabled).toBe(false);
    const result = await gateway.send([], {
      title: "t",
      body: "b"
    });
    expect(result.disabled).toBe(true);
    expect(result.disabledReason).toBe("firebase_not_configured");
  });
});

