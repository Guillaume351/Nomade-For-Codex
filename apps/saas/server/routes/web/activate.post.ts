import { defineEventHandler, getRequestHeaders, readBody, sendRedirect } from 'h3';

export default defineEventHandler(async (event) => {
  const compatBaseUrl = String(useRuntimeConfig(event).compatBackendUrl || "http://127.0.0.1:8080");
  const body = (await readBody<Record<string, unknown>>(event).catch(() => ({}))) ?? {};
  const userCode = typeof body.userCode === 'string' ? body.userCode.trim().toUpperCase() : '';
  if (!userCode) {
    return sendRedirect(event, '/activate', 302);
  }
  try {
    await $fetch('/auth/device/approve', {
      baseURL: compatBaseUrl,
      method: 'POST',
      headers: {
        cookie: getRequestHeaders(event).cookie
      },
      body: { userCode }
    });
    return sendRedirect(event, '/activate?approved=1', 302);
  } catch {
    return sendRedirect(event, '/activate?error=1', 302);
  }
});
