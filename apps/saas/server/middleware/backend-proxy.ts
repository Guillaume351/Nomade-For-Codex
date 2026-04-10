import { defineEventHandler, getRequestURL, proxyRequest } from 'h3';
import { shouldProxyToBackend } from '../utils/backend-proxy';
import { internalBackendTargetFromEvent, waitForInternalBackendStart } from '../utils/internal-backend';

export default defineEventHandler(async (event) => {
  const pathname = getRequestURL(event).pathname;
  if (!shouldProxyToBackend(pathname)) {
    return;
  }
  await waitForInternalBackendStart();
  return proxyRequest(event, internalBackendTargetFromEvent(event));
});
