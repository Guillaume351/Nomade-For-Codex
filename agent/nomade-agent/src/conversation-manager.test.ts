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
        explanation: "Do the thing",
        plan: [{ step: "Do the thing", status: "in_progress" }]
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

  it("normalizes v2 turn/plan/updated payload into a map", () => {
    const emitted: Array<Record<string, unknown>> = [];
    const manager = new ConversationManager((payload) => emitted.push(payload));
    const anyManager = manager as unknown as Record<string, unknown>;

    (anyManager["bindTurn"] as (
      threadId: string,
      codexTurnId: string,
      context: { conversationId: string; turnId: string }
    ) => void)("thread-v2", "turn-codex-v2", {
      conversationId: "conversation-v2",
      turnId: "turn-v2"
    });

    (anyManager["onNotification"] as (notification: {
      method: string;
      params: Record<string, unknown>;
    }) => void)({
      method: "turn/plan/updated",
      params: {
        threadId: "thread-v2",
        turnId: "turn-codex-v2",
        explanation: "Implement changes safely",
        plan: [
          { step: "Parse options", status: "completed" },
          { step: "Render plan", status: "inProgress" }
        ]
      }
    });

    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.turn.plan.updated",
        conversationId: "conversation-v2",
        turnId: "turn-v2",
        plan: {
          explanation: "Implement changes safely",
          plan: [
            { step: "Parse options", status: "completed" },
            { step: "Render plan", status: "inProgress" }
          ]
        }
      })
    );

    manager.close();
  });

  it("maps thread/status/changed v2 payload and thread/name/updated into conversation events", () => {
    const emitted: Array<Record<string, unknown>> = [];
    const manager = new ConversationManager((payload) => emitted.push(payload));
    const anyManager = manager as unknown as Record<string, unknown>;
    const threadByConversation = anyManager["threadByConversation"] as Map<string, string>;
    threadByConversation.set("conversation-3", "thread-3");

    (anyManager["onNotification"] as (notification: {
      method: string;
      params: Record<string, unknown>;
    }) => void)({
      method: "thread/status/changed",
      params: {
        threadId: "thread-3",
        status: {
          type: "idle"
        }
      }
    });

    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.thread.status.changed",
        conversationId: "conversation-3",
        threadId: "thread-3",
        status: "completed",
        thread: {
          status: "completed"
        }
      })
    );

    (anyManager["onNotification"] as (notification: {
      method: string;
      params: Record<string, unknown>;
    }) => void)({
      method: "thread/name/updated",
      params: {
        threadId: "thread-3",
        threadName: "Renamed by Codex"
      }
    });

    expect(emitted).toContainEqual(
      expect.objectContaining({
        type: "conversation.thread.name.updated",
        conversationId: "conversation-3",
        threadId: "thread-3",
        threadName: "Renamed by Codex"
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

  it("coalesces repeated sync snapshots and skips resume for already-loaded threads", async () => {
    const manager = new ConversationManager(() => undefined);
    const anyManager = manager as unknown as Record<string, unknown>;
    const calls = {
      start: 0,
      loadedList: 0,
      resume: 0
    };
    anyManager["codexClient"] = {
      start: async () => {
        calls.start += 1;
      },
      threadLoadedList: async () => {
        calls.loadedList += 1;
        return { data: ["thread-1"], nextCursor: null };
      },
      threadUnsubscribe: async () => "notSubscribed",
      threadResume: async () => {
        calls.resume += 1;
        return { thread: { id: "thread-1" } };
      },
      close: () => undefined
    };

    await manager.syncThreads({
      bindings: [{ conversationId: "conversation-1", threadId: "thread-1" }]
    });
    await manager.syncThreads({
      bindings: [{ conversationId: "conversation-1", threadId: "thread-1" }]
    });

    expect(calls.start).toBe(1);
    expect(calls.loadedList).toBe(1);
    expect(calls.resume).toBe(0);

    manager.close();
  });
});
