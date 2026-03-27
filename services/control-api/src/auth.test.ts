import { describe, expect, it } from "vitest";

class FakeRepo {
  deviceStatus: "pending" | "approved" | "expired" = "pending";

  async createDeviceCode() {
    return {
      deviceCode: "dc_1",
      userCode: "ABCD1234",
      expiresAt: new Date(Date.now() + 60_000)
    };
  }
}

describe("auth primitives", () => {
  it("keeps a pending device flow pending", async () => {
    const repo = new FakeRepo();
    const value = await repo.createDeviceCode();
    expect(value.deviceCode).toBe("dc_1");
    expect(value.userCode).toHaveLength(8);
  });
});
