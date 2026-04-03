export type TunnelDiagnosticScope = "transport" | "upstream_app";

export interface TunnelDiagnostic {
  code: string;
  message: string;
  scope: TunnelDiagnosticScope;
  timestamp: string;
}

interface TunnelProxyRequestShape {
  path: string;
  query?: string;
}

interface TunnelProxyResponseShape {
  headers: Record<string, string>;
}

const parseQuery = (query: string | undefined): URLSearchParams => {
  if (!query || query.trim().length === 0) {
    return new URLSearchParams();
  }
  return new URLSearchParams(query);
};

const hasReactToken = (query: string | undefined): boolean => {
  const params = parseQuery(query);
  if (params.has("react")) {
    return true;
  }
  for (const [key] of params.entries()) {
    if (key.toLowerCase() === "react") {
      return true;
    }
  }
  return false;
};

const pickHeaderValue = (headers: Record<string, string>, name: string): string => {
  const direct = headers[name];
  if (typeof direct === "string" && direct.trim().length > 0) {
    return direct;
  }
  const lower = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lower && typeof value === "string") {
      return value;
    }
  }
  return "";
};

const startsLikeSvgPath = (path: string): boolean => {
  return path.toLowerCase().endsWith(".svg");
};

const isSvgMime = (contentType: string): boolean => {
  return contentType.toLowerCase().includes("image/svg+xml");
};

const transportErrorCodeMap: Array<{ matcher: RegExp; code: string }> = [
  { matcher: /\bagent_offline\b/i, code: "agent_offline" },
  { matcher: /\btunnel_ws_open_timeout\b/i, code: "tunnel_ws_open_timeout" },
  {
    matcher: /\btunnel_ws_closed_before_open\b/i,
    code: "tunnel_ws_closed_before_open",
  },
  { matcher: /\blocal_service_unreachable\b/i, code: "local_service_unreachable" },
  {
    matcher: /\b(localhost|127\.0\.0\.1|\[::1\]).*(ECONNREFUSED|EHOSTUNREACH|ENOTFOUND)\b/i,
    code: "local_service_unreachable",
  },
];

const messageForErrorCode = (code: string): string => {
  switch (code) {
    case "agent_offline":
      return "Agent is offline";
    case "tunnel_ws_unexpected_response":
      return "WebSocket upstream rejected the handshake";
    case "tunnel_ws_open_timeout":
      return "WebSocket upstream timed out while opening";
    case "tunnel_ws_closed_before_open":
      return "WebSocket upstream closed before opening";
    case "local_service_unreachable":
      return "Local dev service is unreachable from the agent";
    default:
      return "Tunnel proxy request failed";
  }
};

export const normalizeTransportTunnelErrorCode = (rawError: string): string => {
  const wsUnexpected = /\btunnel_ws_unexpected_response_(\d{3})\b/i.exec(rawError);
  if (wsUnexpected) {
    const status = wsUnexpected[1];
    if (status) {
      return `tunnel_ws_unexpected_response_${status}`;
    }
    return "tunnel_ws_unexpected_response";
  }
  for (const entry of transportErrorCodeMap) {
    if (entry.matcher.test(rawError)) {
      return entry.code;
    }
  }
  return "tunnel_proxy_failed";
};

export const classifyProxyResponseDiagnostic = (params: {
  request: TunnelProxyRequestShape;
  response: TunnelProxyResponseShape;
  now?: Date;
}): TunnelDiagnostic | null => {
  if (!startsLikeSvgPath(params.request.path)) {
    return null;
  }
  if (!hasReactToken(params.request.query)) {
    return null;
  }
  const contentType = pickHeaderValue(params.response.headers, "content-type");
  if (!isSvgMime(contentType)) {
    return null;
  }
  return {
    code: "vite_svg_react_not_transformed",
    scope: "upstream_app",
    message:
      "SVG requested with ?react was served as image/svg+xml instead of a JS React component module.",
    timestamp: (params.now ?? new Date()).toISOString(),
  };
};

export const buildTransportTunnelDiagnostic = (params: {
  rawError: string;
  now?: Date;
}): TunnelDiagnostic => {
  const code = normalizeTransportTunnelErrorCode(params.rawError);
  const wsUnexpectedMatch = /^tunnel_ws_unexpected_response_(\d{3})$/i.exec(code);
  const message = wsUnexpectedMatch
    ? `WebSocket upstream rejected the handshake (${wsUnexpectedMatch[1]}).`
    : messageForErrorCode(code);
  return {
    code,
    scope: "transport",
    message,
    timestamp: (params.now ?? new Date()).toISOString(),
  };
};
