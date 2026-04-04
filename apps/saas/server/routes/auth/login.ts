import { defineEventHandler, getRequestURL, sendRedirect } from 'h3';

export default defineEventHandler((event) => {
  const url = getRequestURL(event);
  const search = url.search || '';
  return sendRedirect(event, `/login${search}`, 302);
});
