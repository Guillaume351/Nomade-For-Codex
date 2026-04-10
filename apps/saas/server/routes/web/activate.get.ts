import { defineEventHandler, getRequestURL, sendRedirect } from "h3";

export default defineEventHandler((event) => {
  const url = getRequestURL(event);
  return sendRedirect(event, `/activate${url.search || ""}`, 302);
});

