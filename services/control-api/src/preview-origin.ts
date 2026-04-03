const defaultPreviewOrigin = (baseDomain: string): string =>
  `https://${baseDomain}`;

const parseBaseOrigin = (baseOrigin: string, baseDomain: string): URL => {
  try {
    return new URL(baseOrigin);
  } catch {
    return new URL(defaultPreviewOrigin(baseDomain));
  }
};

export const previewOriginForSlug = (params: {
  slug: string;
  baseDomain: string;
  baseOrigin: string;
}): string => {
  const parsed = parseBaseOrigin(params.baseOrigin, params.baseDomain);
  const host = `${params.slug}.${params.baseDomain}`.toLowerCase();
  const port = parsed.port ? `:${parsed.port}` : "";
  return `${parsed.protocol}//${host}${port}`;
};
