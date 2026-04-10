import { defineEventHandler, getRequestHeaders, sendRedirect } from 'h3';
import { internalBackendHttpBaseUrl, waitForInternalBackendStart } from '../../../utils/internal-backend';

export default defineEventHandler(async (event) => {
  try {
    await waitForInternalBackendStart();
    const payload = await $fetch<{ url?: string | null }>('/billing/portal-session', {
      baseURL: internalBackendHttpBaseUrl,
      method: 'POST',
      headers: {
        cookie: getRequestHeaders(event).cookie
      },
      body: {}
    });
    if (payload.url) {
      return sendRedirect(event, payload.url, 302);
    }
  } catch {
    // fallthrough
  }
  return sendRedirect(event, '/billing?error=portal', 302);
});
