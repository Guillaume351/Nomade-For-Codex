import { defineEventHandler, getRequestURL, proxyRequest } from 'h3';
import { compatTargetFromEvent, shouldProxyToCompat } from '../utils/compat';

export default defineEventHandler(async (event) => {
  const pathname = getRequestURL(event).pathname;
  if (!shouldProxyToCompat(pathname)) {
    return;
  }
  return proxyRequest(event, compatTargetFromEvent(event));
});
