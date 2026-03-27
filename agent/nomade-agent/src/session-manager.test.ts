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

    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(statuses[0]).toBe("running");
    expect(outputs.join("")).toContain("hello");
  });
});
