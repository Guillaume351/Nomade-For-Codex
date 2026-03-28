import { describe, expect, it } from "vitest";
import { SessionManager } from "./session-manager.js";

describe("SessionManager", () => {
  it("spawns and emits output", async () => {
    const outputs: string[] = [];
    const statuses: string[] = [];

    const manager = new SessionManager({
      onOutput: (_id, _stream, data) => outputs.push(data),
      onStatus: (_id, status) => statuses.push(status)
    });

    manager.createSession({
      sessionId: "s1",
      command: "echo hello"
    });

    const timeoutAt = Date.now() + 3_000;
    while (Date.now() < timeoutAt && !outputs.join("").includes("hello")) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }

    expect(statuses).toContain("running");
    expect(outputs.join("")).toContain("hello");
  });
});
