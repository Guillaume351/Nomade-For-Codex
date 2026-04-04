import WebSocket from 'ws';

const socketMap = new WeakMap<object, WebSocket>();

const compatWsBase = (): string => {
  const raw = (process.env.COMPAT_BACKEND_URL || 'http://127.0.0.1:8080').replace(/\/$/, '');
  if (raw.startsWith('https://')) {
    return `wss://${raw.slice('https://'.length)}`;
  }
  if (raw.startsWith('http://')) {
    return `ws://${raw.slice('http://'.length)}`;
  }
  if (raw.startsWith('wss://') || raw.startsWith('ws://')) {
    return raw;
  }
  return `ws://${raw}`;
};

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

export const createWsProxyHandler = (targetPathFromRequestUrl: (requestUrl: URL) => string) =>
  defineWebSocketHandler({
    open(peer) {
      const request = (peer as any).request as { url?: string; headers?: Record<string, string | undefined> };
      const requestUrl = new URL(request?.url ?? '/', 'http://localhost');
      const target = `${compatWsBase()}${targetPathFromRequestUrl(requestUrl)}`;
      const headers = request?.headers ?? {};
      const upstream = new WebSocket(target, {
        headers: {
          origin: headers.origin,
          cookie: headers.cookie,
          authorization: headers.authorization,
          'x-gateway-secret': headers['x-gateway-secret'],
          'x-nomade-token': headers['x-nomade-token']
        }
      });

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
