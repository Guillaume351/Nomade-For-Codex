import type http from 'node:http';
import { getRequestURL, type H3Event } from 'h3';

declare global {
  // eslint-disable-next-line no-var
  var __nomadeInternalBackendServer: http.Server | undefined;
  // eslint-disable-next-line no-var
  var __nomadeInternalBackendServerStart: Promise<void> | undefined;
}

const internalBackendHost = process.env.INTERNAL_BACKEND_HOST || '127.0.0.1';

const parseBackendPort = (): number => {
  const raw = process.env.INTERNAL_BACKEND_PORT || '8090';
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`Invalid INTERNAL_BACKEND_PORT: ${raw}`);
  }
  return parsed;
};

const internalBackendPort = parseBackendPort();

export const internalBackendAddress = {
  host: internalBackendHost,
  port: internalBackendPort
} as const;

export const internalBackendHttpBaseUrl = `http://${internalBackendHost}:${internalBackendPort}`;
export const internalBackendWsBaseUrl = `ws://${internalBackendHost}:${internalBackendPort}`;

export const internalBackendTargetFromEvent = (event: H3Event): string => {
  const url = getRequestURL(event);
  return `${internalBackendHttpBaseUrl}${url.pathname}${url.search}`;
};

export const waitForInternalBackendStart = async (): Promise<void> => {
  if (globalThis.__nomadeInternalBackendServer) {
    return;
  }
  if (globalThis.__nomadeInternalBackendServerStart) {
    await globalThis.__nomadeInternalBackendServerStart;
  }
};
