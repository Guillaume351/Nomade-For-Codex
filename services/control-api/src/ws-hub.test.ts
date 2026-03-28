import { describe, expect, it } from "vitest";
import { parseCodexThreadReadSummary } from "./ws-hub.js";

describe("parseCodexThreadReadSummary", () => {
  it("parses raw codex thread/read items", () => {
    const parsed = parseCodexThreadReadSummary({
      id: "thread-1",
      title: "Raw thread",
      turns: [
        {
          id: "turn-1",
          status: "completed",
          userPrompt: "hello",
          items: [
            {
              id: "item-1",
              type: "userMessage",
              text: "hello"
            },
            {
              id: "item-2",
              type: "agentMessage",
              text: "world"
            }
          ]
        }
      ]
    });

    expect(parsed.threadId).toBe("thread-1");
    expect(parsed.turns).toHaveLength(1);
    expect(parsed.turns[0].items[0].itemType).toBe("userMessage");
    expect(parsed.turns[0].items[1].itemType).toBe("agentMessage");
    expect(parsed.turns[0].items[1].payload.text).toBe("world");
  });

  it("parses normalized wrapped items from agent bridge", () => {
    const parsed = parseCodexThreadReadSummary({
      threadId: "thread-2",
      turns: [
        {
          turnId: "turn-2",
          status: "failed",
          error: { message: "agent_offline" },
          userPrompt: "foo",
          items: [
            {
              itemId: "item-9",
              itemType: "agentMessage",
              payload: {
                id: "item-9",
                type: "agentMessage",
                text: "bar"
              }
            }
          ]
        }
      ]
    });

    expect(parsed.threadId).toBe("thread-2");
    expect(parsed.turns[0].error).toBe("agent_offline");
    expect(parsed.turns[0].items[0].itemId).toBe("item-9");
    expect(parsed.turns[0].items[0].itemType).toBe("agentMessage");
    expect(parsed.turns[0].items[0].payload.text).toBe("bar");
  });
});
