export type Role = "user" | "agent";

export interface E2EEnvelope {
  v: 1;
  alg: "xchacha20poly1305";
  epoch: number;
  senderDeviceId: string;
  seq: number;
  nonce: string;
  aad: string;
  ciphertext: string;
  sig: string;
}

export interface SessionCreateMessage {
  type: "session.create";
  sessionId: string;
  workspaceId: string;
  agentId: string;
  command: string;
  e2eCommandEnvelope?: E2EEnvelope;
  cwd?: string;
  env?: Record<string, string>;
}

export interface SessionInputMessage {
  type: "session.input";
  sessionId: string;
  data: string;
  e2eEnvelope?: E2EEnvelope;
}

export interface SessionTerminateMessage {
  type: "session.terminate";
  sessionId: string;
}

export interface SessionOutputMessage {
  type: "session.output";
  sessionId: string;
  data: string;
  cursor: number;
  stream: "stdout" | "stderr";
  e2eEnvelope?: E2EEnvelope;
}

export interface SessionStatusMessage {
  type: "session.status";
  sessionId: string;
  status: "running" | "exited" | "failed";
  exitCode?: number;
}

export interface TunnelOpenMessage {
  type: "tunnel.open";
  tunnelId: string;
  slug: string;
  targetPort: number;
}

export interface TunnelHttpRequestMessage {
  type: "tunnel.http.request";
  requestId: string;
  tunnelId: string;
  method: string;
  path: string;
  query?: string;
  headers: Record<string, string>;
  bodyBase64?: string;
}

export interface TunnelHttpResponseMessage {
  type: "tunnel.http.response";
  requestId: string;
  status: number;
  headers: Record<string, string>;
  bodyBase64: string;
}

export interface TunnelStatusMessage {
  type: "tunnel.status";
  tunnelId: string;
  status: "open" | "closed" | "error" | "starting" | "healthy" | "unhealthy" | "stopped";
  reason?: string;
  detail?: string;
  probeStatus?: "ok" | "error" | "unknown";
  probeCode?: number;
  probeAt?: string;
  diagnostic?: TunnelDiagnostic | null;
}

export interface TunnelDiagnostic {
  code: string;
  message: string;
  scope: "transport" | "upstream_app";
  timestamp: string;
}

export interface TunnelWsOpenMessage {
  type: "tunnel.ws.open";
  requestId: string;
  connectionId: string;
  tunnelId: string;
  path: string;
  query?: string;
  headers?: Record<string, string>;
}

export interface TunnelWsFrameMessage {
  type: "tunnel.ws.frame";
  connectionId: string;
  dataBase64: string;
  isBinary: boolean;
}

export interface TunnelWsCloseMessage {
  type: "tunnel.ws.close";
  connectionId: string;
  code?: number;
  reason?: string;
}

export interface TunnelWsOpenedMessage {
  type: "tunnel.ws.opened";
  requestId: string;
  connectionId: string;
}

export interface TunnelWsClosedMessage {
  type: "tunnel.ws.closed";
  connectionId: string;
  code?: number;
  reason?: string;
}

export interface TunnelWsErrorMessage {
  type: "tunnel.ws.error";
  requestId?: string;
  connectionId?: string;
  error: string;
}

export interface ConversationTurnStartMessage {
  type: "conversation.turn.start";
  conversationId: string;
  turnId: string;
  threadId?: string;
  prompt?: string;
  e2ePromptEnvelope?: E2EEnvelope;
  inputItems?: ConversationInputItem[];
  collaborationMode?: Record<string, unknown>;
  model?: string;
  cwd?: string;
  approvalPolicy?: "untrusted" | "on-failure" | "on-request" | "never";
  sandboxMode?: "read-only" | "workspace-write" | "danger-full-access";
  effort?: "none" | "minimal" | "low" | "medium" | "high" | "xhigh";
}

export type ConversationInputItem =
  | {
      type: "text";
      text: string;
    }
  | {
      type: "image";
      imageUrl: string;
      detail?: string;
    }
  | {
      type: "local_image";
      path: string;
    }
  | {
      type: "skill";
      path: string;
      name?: string;
    }
  | {
      type: "mention";
      path: string;
      name?: string;
    };

export interface ConversationTurnInterruptMessage {
  type: "conversation.turn.interrupt";
  conversationId: string;
  turnId: string;
  threadId?: string;
}

export interface ConversationSyncThreadsMessage {
  type: "conversation.sync.threads";
  items: Array<{
    conversationId: string;
    threadId: string;
  }>;
}

export interface ConversationThreadStartedMessage {
  type: "conversation.thread.started";
  conversationId: string;
  threadId: string;
}

export interface ConversationTurnStartedMessage {
  type: "conversation.turn.started";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
}

export interface ConversationTurnDiffUpdatedMessage {
  type: "conversation.turn.diff.updated";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  diff: string;
  e2eEnvelope?: E2EEnvelope;
}

export interface ConversationItemDeltaMessage {
  type: "conversation.item.delta";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  itemId: string;
  stream: "agentMessage" | "commandExecution" | "fileChange" | "reasoning" | "plan";
  delta: string;
  e2eEnvelope?: E2EEnvelope;
}

export interface ConversationItemStartedMessage {
  type: "conversation.item.started";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  itemId: string;
  itemType: string;
  item: Record<string, unknown>;
  e2eEnvelope?: E2EEnvelope;
}

export interface ConversationItemCompletedMessage {
  type: "conversation.item.completed";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  itemId: string;
  itemType: string;
  item: Record<string, unknown>;
  e2eEnvelope?: E2EEnvelope;
}

export interface ConversationTurnPlanUpdatedMessage {
  type: "conversation.turn.plan.updated";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  plan: Record<string, unknown>;
}

export interface ConversationThreadStatusChangedMessage {
  type: "conversation.thread.status.changed";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  status: string;
  thread?: Record<string, unknown>;
}

export interface ConversationThreadTokenUsageUpdatedMessage {
  type: "conversation.thread.token_usage.updated";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  tokenUsage: Record<string, unknown>;
}

export interface ConversationServerRequestMessage {
  type: "conversation.server.request";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  requestId: string;
  method: string;
  params: Record<string, unknown>;
}

export interface ConversationServerRequestResolvedMessage {
  type: "conversation.server.request.resolved";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  requestId: string;
  resolvedAt: string;
  status: "completed" | "declined" | "failed";
  result?: unknown;
  error?: string;
}

export interface ConversationServerResponseMessage {
  type: "conversation.server.response";
  conversationId: string;
  turnId: string;
  threadId?: string;
  codexTurnId?: string;
  requestId: string;
  result?: unknown;
  error?: string;
  e2eEnvelope?: E2EEnvelope;
}

export interface ConversationTurnCompletedMessage {
  type: "conversation.turn.completed";
  conversationId: string;
  turnId: string;
  threadId: string;
  codexTurnId: string;
  status: "completed" | "interrupted" | "failed";
  error?: string;
}

export interface ErrorMessage {
  type: "error";
  code: string;
  message: string;
}

export type MobileToAgentMessage =
  | SessionCreateMessage
  | SessionInputMessage
  | SessionTerminateMessage
  | TunnelOpenMessage
  | TunnelHttpRequestMessage
  | TunnelWsOpenMessage
  | TunnelWsFrameMessage
  | TunnelWsCloseMessage
  | ConversationSyncThreadsMessage
  | ConversationTurnStartMessage
  | ConversationTurnInterruptMessage
  | ConversationServerResponseMessage;

export type AgentToMobileMessage =
  | SessionOutputMessage
  | SessionStatusMessage
  | TunnelStatusMessage
  | TunnelHttpResponseMessage
  | TunnelWsOpenedMessage
  | TunnelWsFrameMessage
  | TunnelWsClosedMessage
  | TunnelWsErrorMessage
  | ConversationThreadStartedMessage
  | ConversationTurnStartedMessage
  | ConversationTurnDiffUpdatedMessage
  | ConversationItemDeltaMessage
  | ConversationItemStartedMessage
  | ConversationItemCompletedMessage
  | ConversationTurnPlanUpdatedMessage
  | ConversationThreadStatusChangedMessage
  | ConversationThreadTokenUsageUpdatedMessage
  | ConversationServerRequestMessage
  | ConversationServerRequestResolvedMessage
  | ConversationTurnCompletedMessage
  | ErrorMessage;

export interface UserClaims {
  sub: string;
  role: "user";
  email: string;
}
