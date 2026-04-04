import { defineEventHandler, getRequestURL, sendRedirect } from 'h3';

const mapLegacyPath = (legacyPath: string): string => {
  const normalized = legacyPath.replace(/^\/web/, '') || '/';
  if (normalized === '/' || normalized === '') {
    return '/account';
  }
  if (normalized.startsWith('/login')) return '/login';
  if (normalized.startsWith('/signup')) return '/signup';
  if (normalized.startsWith('/forgot-password')) return '/forgot-password';
  if (normalized.startsWith('/reset-password')) return '/reset-password';
  if (normalized.startsWith('/verify-email')) return '/verify-email';
  if (normalized.startsWith('/activate')) return '/activate';
  if (normalized.startsWith('/account')) return '/account';
  if (normalized.startsWith('/devices')) return '/devices';
  if (normalized.startsWith('/logout')) return '/logout';
  if (normalized.startsWith('/billing')) return '/billing';
  return '/account';
};

export default defineEventHandler((event) => {
  const url = getRequestURL(event);
  const target = mapLegacyPath(url.pathname);
  const search = url.search || '';
  return sendRedirect(event, `${target}${search}`, 302);
});
