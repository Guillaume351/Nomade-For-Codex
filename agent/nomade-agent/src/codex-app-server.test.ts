import { describe, expect, it } from "vitest";
import {
  parseCodexCollaborationModeList,
  parseCodexMcpServerStatusList,
  parseCodexSkillsList
} from "./codex-app-server.js";

describe("codex-app-server parsers", () => {
  it("parses modern collaboration mode entries", () => {
    const parsed = parseCodexCollaborationModeList([
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
    ]);

    expect(parsed).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          slug: "plan",
          name: "Plan",
          mode: "plan",
          reasoningEffort: "medium",
          modeMask: {
            name: "Plan",
            mode: "plan",
            model: null,
            reasoning_effort: "medium"
          },
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
  });

  it("ignores invalid collaboration modes", () => {
    const parsed = parseCodexCollaborationModeList([
      {
        slug: "legacy-mode",
        label: "Legacy"
      },
      {
        name: "Plan"
      }
    ]);

    expect(parsed).toEqual([]);
  });

  it("parses nested skills/list response with metadata", () => {
    const parsed = parseCodexSkillsList([
      {
        cwd: "/repo",
        skills: [
          {
            name: "skill-a",
            path: "/skills/a/SKILL.md",
            description: "Skill A",
            scope: "user",
            enabled: true,
            interface: {
              shortDescription: "short-a"
            }
          }
        ],
        errors: []
      }
    ]);

    expect(parsed).toEqual([
      {
        name: "skill-a",
        path: "/skills/a/SKILL.md",
        description: "Skill A",
        shortDescription: "short-a",
        scope: "user",
        enabled: true,
        cwd: "/repo"
      }
    ]);
  });

  it("ignores flat skills/list entries without nested cwd groups", () => {
    const parsed = parseCodexSkillsList([
      {
        name: "legacy-skill",
        path: "/skills/legacy/SKILL.md"
      }
    ]);

    expect(parsed).toEqual([]);
  });

  it("parses mcp server status rows", () => {
    const parsed = parseCodexMcpServerStatusList([
      {
        name: "github",
        enabled: true,
        required: false,
        authStatus: "authorized",
        tools: [{ name: "issues" }, { name: "pulls" }]
      }
    ]);

    expect(parsed).toEqual([
      {
        name: "github",
        enabled: true,
        required: false,
        authStatus: "authorized",
        authRequired: undefined,
        toolCount: 2,
        resourceCount: 0
      }
    ]);
  });
});
