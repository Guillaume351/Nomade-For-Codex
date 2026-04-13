import { describe, expect, it } from "vitest";
import { parseCodexRuntimeOptions, parseCodexThreadReadSummary } from "./ws-hub.js";

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

describe("parseCodexRuntimeOptions", () => {
  it("normalizes modern collaboration mode and nested skills payloads", () => {
    const parsed = parseCodexRuntimeOptions({
      models: [],
      approvalPolicies: ["on-request"],
      sandboxModes: ["workspace-write"],
      reasoningEfforts: ["medium"],
      collaborationModes: [
        {
          name: "Plan",
          mode: "plan",
          model: null,
          reasoning_effort: "medium"
        },
        {
          name: "Default",
          mode: "default"
        }
      ],
      skills: [
        {
          cwd: "/repo",
          skills: [
            {
              name: "skill-a",
              path: "/skills/a/SKILL.md",
              description: "A skill",
              scope: "user",
              enabled: true,
              interface: {
                shortDescription: "short-a"
              }
            }
          ],
          errors: []
        }
      ],
      defaults: {
        model: "gpt-5.4"
      }
    });

    expect(parsed.collaborationModes).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          slug: "plan",
          name: "Plan",
          mode: "plan",
          turnStartCollaborationMode: {
            mode: "plan",
            settings: {
              developer_instructions: null
            }
          }
        }),
        expect.objectContaining({
          slug: "default",
          mode: "default"
        })
      ])
    );
    expect(parsed.skills).toEqual([
      expect.objectContaining({
        name: "skill-a",
        path: "/skills/a/SKILL.md",
        description: "A skill",
        shortDescription: "short-a",
        scope: "user",
        enabled: true,
        cwd: "/repo"
      })
    ]);
    expect(parsed.defaults.model).toBe("gpt-5.4");
  });

  it("drops unsupported legacy collaboration/skills payloads", () => {
    const parsed = parseCodexRuntimeOptions({
      models: [],
      approvalPolicies: [],
      sandboxModes: [],
      reasoningEfforts: [],
      collaborationModes: [
        {
          slug: "legacy",
          label: "Legacy",
          description: "legacy mode"
        }
      ],
      skills: [
        {
          name: "legacy-skill",
          path: "/skills/legacy/SKILL.md"
        }
      ],
      defaults: {}
    });

    expect(parsed.collaborationModes).toEqual([]);
    expect(parsed.skills).toEqual([]);
  });
});
