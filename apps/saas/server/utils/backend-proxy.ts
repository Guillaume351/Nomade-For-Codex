export const BACKEND_PROXY_PREFIXES = [
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

export const shouldProxyToBackend = (pathname: string): boolean => {
  if (pathname === '/ws' || /^\/internal\/tunnels\/[^/]+\/ws$/.test(pathname)) {
    return false;
  }
  if (pathname === '/auth/login') {
    return false;
  }
  if (pathname === '/api/auth' || pathname === '/auth') {
    return true;
  }
  return BACKEND_PROXY_PREFIXES.some((prefix) => pathname.startsWith(prefix));
};
