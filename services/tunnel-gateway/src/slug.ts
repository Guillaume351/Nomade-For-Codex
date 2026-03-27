export const extractTunnelSlug = (hostHeader: string | undefined, baseDomain: string): string | null => {
  if (!hostHeader) {
    return null;
  }

  const host = hostHeader.split(":")[0].toLowerCase();
  const domain = baseDomain.toLowerCase();
  if (!host.endsWith(`.${domain}`)) {
    return null;
  }

  const suffix = `.${domain}`;
  const slug = host.slice(0, -suffix.length);
  if (!slug || slug.includes(".")) {
    return null;
  }

  return slug;
};
