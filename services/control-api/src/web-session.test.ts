import { describe, expect, it } from "vitest";
import { createWebSessionToken, parseCookieHeader } from "./web-session.js";

describe("web-session helpers", () => {
  it("parses cookie headers safely", () => {
    const parsed = parseCookieHeader("a=1; b=hello%40example.com; c=ok");
    expect(parsed.a).toBe("1");
    expect(parsed.b).toBe("hello@example.com");
    expect(parsed.c).toBe("ok");
  });

  it("creates signed session tokens", () => {
    const token = createWebSessionToken({
      userId: "user_1",
      email: "hello@example.com",
      jwtSecret: "secret",
      ttlSec: 3600
    });
    expect(token.split(".")).toHaveLength(3);
  });
});
