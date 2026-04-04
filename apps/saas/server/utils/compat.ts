import { getRequestURL, type H3Event } from 'h3';

export const COMPAT_PREFIXES = [
  '/api/auth/',
  '/auth/',
  '/me',
  '/billing/',
  '/agents',
  '/workspaces',
  '/conversations',
  '/sessions',
  '/tunnels',
  '/internal/',
  '/health',
  '/ws'
] as const;

export const shouldProxyToCompat = (pathname: string): boolean => {
  if (pathname === "/ws" || /^\/internal\/tunnels\/[^/]+\/ws$/.test(pathname)) {
    return false;
  }
  if (pathname === "/auth/login") {
    return false;
  }
  if (pathname === '/api/auth' || pathname === '/auth') {
    return true;
  }
  return COMPAT_PREFIXES.some((prefix) => pathname.startsWith(prefix));
};

export const compatTargetFromEvent = (event: H3Event): string => {
  const config = useRuntimeConfig(event);
  const base = String(process.env.COMPAT_BACKEND_URL || config.compatBackendUrl || 'http://127.0.0.1:8080').replace(/\/$/, '');
  const url = getRequestURL(event);
  return `${base}${url.pathname}${url.search}`;
};
