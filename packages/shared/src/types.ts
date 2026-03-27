export type Role = "user" | "agent";

export interface SessionCreateMessage {
  type: "session.create";
  sessionId: string;
  workspaceId: string;
  agentId: string;
  command: string;
  cwd?: string;
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
  status: "open" | "closed" | "error";
  reason?: string;
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
  | TunnelHttpRequestMessage;

export type AgentToMobileMessage =
  | SessionOutputMessage
  | SessionStatusMessage
  | TunnelStatusMessage
  | TunnelHttpResponseMessage
  | ErrorMessage;

export interface UserClaims {
  sub: string;
  role: "user";
  email: string;
}
