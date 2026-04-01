export type Role = "user" | "agent";

export interface SessionCreateMessage {
  type: "session.create";
  sessionId: string;
  workspaceId: string;
  agentId: string;
  command: string;
  cwd?: string;
  env?: Record<string, string>;
}

export interface SessionInputMessage {
  type: "session.input";
  sessionId: string;
  data: string;
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
  prompt: string;
  model?: string;
  cwd?: string;
}

export interface ConversationTurnInterruptMessage {
  type: "conversation.turn.interrupt";
  conversationId: string;
  turnId: string;
  threadId?: string;
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
  | ConversationTurnStartMessage
  | ConversationTurnInterruptMessage;

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
  | ConversationItemCompletedMessage
  | ConversationTurnCompletedMessage
  | ErrorMessage;

export interface UserClaims {
  sub: string;
  role: "user";
  email: string;
}
