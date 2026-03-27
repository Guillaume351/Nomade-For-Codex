FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/tsconfig.json ./packages/shared/
COPY services/control-api/package.json services/control-api/tsconfig.json ./services/control-api/
COPY services/tunnel-gateway/package.json ./services/tunnel-gateway/package.json
COPY agent/nomade-agent/package.json ./agent/nomade-agent/package.json
RUN npm install

FROM deps AS build
COPY packages/shared/src ./packages/shared/src
COPY services/control-api/src ./services/control-api/src
RUN npm --workspace packages/shared run build && npm --workspace services/control-api run build

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/packages/shared/dist ./packages/shared/dist
COPY --from=build /app/services/control-api/dist ./services/control-api/dist
COPY services/control-api/package.json ./services/control-api/package.json
COPY packages/shared/package.json ./packages/shared/package.json
CMD ["node", "services/control-api/dist/index.js"]
