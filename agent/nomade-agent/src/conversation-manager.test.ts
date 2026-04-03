import { describe, expect, it } from "vitest";
import { ConversationManager } from "./conversation-manager.js";

describe("ConversationManager app-server mapping", () => {
  it("maps item.started and plan updates into conversation events", () => {
    const emitted: Array<Record<string, unknown>> = [];
    const manager = new ConversationManager((payload) => emitted.push(payload));
    const anyManager = manager as unknown as Record<string, unknown>;

    (anyManager["bindTurn"] as (
      threadId: string,
      codexTurnId: string,
      context: { conversationId: string; turnId: string }
    ) => void)("thread-1", "turn-codex-1", {
      conversationId: "conversation-1",
      turnId: "turn-1"
    });

    (anyManager["onNotification"] as (notification: {
      method: string;
      params: Record<string, unknown>;
    }) => void)({
      method: "item/started",
      params: {
        threadId: "thread-1",
        turnId: "turn-codex-1",
        item: {
          id: "item-1",
          type: "commandExecution",
          command: "npm run build"
        }
      }
    });
    (anyManager["onNotification"] as (notification: {
      method: string;
      params: Record<string, unknown>;
    }) => void)({
      method: "turn/plan/updated",
      params: {
        threadId: "thread-1",
        turnId: "turn-codex-1",
        plan: {
          steps: [{ title: "Do the thing", status: "in_progress" }]
        }
      }
    });

    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.item.started",
        conversationId: "conversation-1",
        turnId: "turn-1",
        itemId: "item-1",
        itemType: "commandExecution"
      })
    );
    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.turn.plan.updated",
        conversationId: "conversation-1",
        turnId: "turn-1"
      })
    );

    manager.close();
  });

  it("supports server request round-trip from app-server to mobile response", async () => {
    const emitted: Array<Record<string, unknown>> = [];
    const manager = new ConversationManager((payload) => emitted.push(payload));
    const anyManager = manager as unknown as Record<string, unknown>;

    (anyManager["bindTurn"] as (
      threadId: string,
      codexTurnId: string,
      context: { conversationId: string; turnId: string }
    ) => void)("thread-2", "turn-codex-2", {
      conversationId: "conversation-2",
      turnId: "turn-2"
    });

    const pending = (anyManager["onServerRequest"] as (request: {
      requestId: string;
      method: string;
      params: Record<string, unknown>;
    }) => Promise<{ result?: Record<string, unknown>; error?: string }>)({
      requestId: "42",
      method: "item/tool/requestUserInput",
      params: {
        threadId: "thread-2",
        turnId: "turn-codex-2",
        itemId: "item-request-1"
      }
    });

    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.server.request",
        conversationId: "conversation-2",
        turnId: "turn-2",
        requestId: "42",
        method: "item/tool/requestUserInput"
      })
    );

    const resolved = manager.resolveServerRequest({
      requestId: "42",
      result: { answer: "yes", status: "completed" }
    });
    expect(resolved).toBe(true);

    await expect(pending).resolves.toEqual({
      result: { answer: "yes", status: "completed" }
    });
    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.server.request.resolved",
        conversationId: "conversation-2",
        turnId: "turn-2",
        requestId: "42",
        status: "completed"
      })
    );

    manager.close();
  });
});
