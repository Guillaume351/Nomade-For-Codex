FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/tsconfig.json ./packages/shared/
COPY services/control-api/package.json services/control-api/tsconfig.json ./services/control-api/
COPY services/tunnel-gateway/package.json ./services/tunnel-gateway/package.json
COPY agent/nomade-agent/package.json ./agent/nomade-agent/package.json
COPY apps/saas/package.json ./apps/saas/package.json
RUN npm install

FROM deps AS build
COPY packages/shared/src ./packages/shared/src
COPY services/control-api/src ./services/control-api/src
COPY apps/saas ./apps/saas
RUN npm --workspace packages/shared run build \
  && npm --workspace services/control-api run build \
  && npm --workspace apps/saas run build

FROM node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
ENV COMPAT_BACKEND_PORT=8090
ENV COMPAT_BACKEND_URL=http://127.0.0.1:8090

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/services/control-api/node_modules ./services/control-api/node_modules

COPY --from=build /app/packages/shared/dist ./packages/shared/dist
COPY --from=build /app/services/control-api/dist ./services/control-api/dist
COPY --from=build /app/apps/saas/.output ./apps/saas/.output

COPY packages/shared/package.json ./packages/shared/package.json
COPY services/control-api/package.json ./services/control-api/package.json
COPY apps/saas/package.json ./apps/saas/package.json
COPY apps/saas/scripts/start-saas.sh ./apps/saas/scripts/start-saas.sh

RUN chmod +x ./apps/saas/scripts/start-saas.sh

CMD ["sh", "./apps/saas/scripts/start-saas.sh"]
