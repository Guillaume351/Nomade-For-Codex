import { defineEventHandler, getRequestHeaders, sendRedirect } from 'h3';

export default defineEventHandler(async (event) => {
  const compatBaseUrl = String(useRuntimeConfig(event).compatBackendUrl || "http://127.0.0.1:8080");
  try {
    const payload = await $fetch<{ url?: string | null }>('/billing/checkout-session', {
      baseURL: compatBaseUrl,
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
  return sendRedirect(event, '/billing?error=checkout', 302);
});
