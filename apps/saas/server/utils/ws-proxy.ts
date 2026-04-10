import WebSocket from 'ws';
import { internalBackendWsBaseUrl } from './internal-backend';

const socketMap = new WeakMap<object, WebSocket>();

const toRawPayload = (message: any): string | Buffer => {
  if (typeof message === 'string' || Buffer.isBuffer(message)) {
    return message;
  }
  if (message && Buffer.isBuffer(message.raw)) {
    return message.raw;
  }
  if (message && typeof message.text === 'function') {
    return String(message.text());
  }
  return JSON.stringify(message ?? {});
};

const errorToMessage = (error: unknown): string => {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
};

const firstHeaderValue = (value: unknown): string | undefined => {
  if (typeof value === 'string' && value.length > 0) {
    return value;
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      if (typeof entry === 'string' && entry.length > 0) {
        return entry;
      }
    }
  }
  return undefined;
};

const selectUpstreamHeaders = (headers: Record<string, unknown>): Record<string, string> => {
  const candidates: Record<string, string | undefined> = {
    origin: firstHeaderValue(headers.origin),
    cookie: firstHeaderValue(headers.cookie),
    authorization: firstHeaderValue(headers.authorization),
    'x-gateway-secret': firstHeaderValue(headers['x-gateway-secret']),
    'x-nomade-token': firstHeaderValue(headers['x-nomade-token'])
  };

  const selected: Record<string, string> = {};
  for (const [key, value] of Object.entries(candidates)) {
    if (typeof value === 'string' && value.length > 0) {
      selected[key] = value;
    }
  }
  return selected;
};

export const createWsProxyHandler = (targetPathFromRequestUrl: (requestUrl: URL) => string) =>
  defineWebSocketHandler({
    open(peer) {
      const request = (peer as any).request as { url?: string; headers?: Record<string, unknown> };
      const requestUrl = new URL(request?.url ?? '/', 'http://localhost');
      const target = `${internalBackendWsBaseUrl}${targetPathFromRequestUrl(requestUrl)}`;
      const headers = request?.headers ?? {};
      let upstream: WebSocket;
      try {
        upstream = new WebSocket(target, {
          headers: selectUpstreamHeaders(headers)
        });
      } catch (error) {
        console.error('[saas-ws] upstream_init_error', {
          target,
          error: errorToMessage(error)
        });
        try {
          (peer as any).close(1011, 'upstream_init_error');
        } catch {
          // no-op
        }
        return;
      }

      socketMap.set(peer as any, upstream);

      upstream.on('message', (data, isBinary) => {
        try {
          (peer as any).send(data, isBinary ? { binary: true } : undefined);
        } catch {
          // no-op
        }
      });

      upstream.on('close', (code, reason) => {
        try {
          (peer as any).close(code, reason.toString());
        } catch {
          // no-op
        }
      });

      upstream.on('error', (error) => {
        console.error('[saas-ws] upstream_error', {
          target,
          error: errorToMessage(error)
        });
        try {
          (peer as any).close(1011, 'upstream_error');
        } catch {
          // no-op
        }
      });
    },

    message(peer, message) {
      const upstream = socketMap.get(peer as any);
      if (!upstream || upstream.readyState !== WebSocket.OPEN) {
        return;
      }
      upstream.send(toRawPayload(message));
    },

    close(peer, event) {
      const upstream = socketMap.get(peer as any);
      socketMap.delete(peer as any);
      if (!upstream || upstream.readyState >= WebSocket.CLOSING) {
        return;
      }
      try {
        const code = typeof (event as any)?.code === 'number' ? (event as any).code : 1000;
        const reason = typeof (event as any)?.reason === 'string' ? (event as any).reason : '';
        upstream.close(code, reason);
      } catch {
        upstream.terminate();
      }
    },

    error(peer, error) {
      const upstream = socketMap.get(peer as any);
      socketMap.delete(peer as any);
      console.error('[saas-ws] peer_error', { error: errorToMessage(error) });
      if (upstream && upstream.readyState < WebSocket.CLOSING) {
        upstream.terminate();
      }
    }
  });
