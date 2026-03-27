FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json tsconfig.base.json ./
COPY services/tunnel-gateway/package.json services/tunnel-gateway/tsconfig.json ./services/tunnel-gateway/
COPY services/control-api/package.json ./services/control-api/package.json
COPY agent/nomade-agent/package.json ./agent/nomade-agent/package.json
COPY packages/shared/package.json ./packages/shared/package.json
RUN npm install

FROM deps AS build
COPY services/tunnel-gateway/src ./services/tunnel-gateway/src
RUN npm --workspace services/tunnel-gateway run build

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/services/tunnel-gateway/dist ./services/tunnel-gateway/dist
COPY services/tunnel-gateway/package.json ./services/tunnel-gateway/package.json
CMD ["node", "services/tunnel-gateway/dist/index.js"]
