# syntax=docker/dockerfile:1.7
# Multi-stage build for Athen backend.

# ---- Builder ----
FROM node:22-alpine AS builder
WORKDIR /app

# Install deps with a clean cache layer
COPY package.json package-lock.json* ./
RUN npm ci --ignore-scripts

# Copy source + tsconfig and compile
COPY tsconfig.json ./
COPY src ./src
COPY scripts ./scripts
RUN npm run build

# Prune dev deps for the runtime image
RUN npm prune --omit=dev

# ---- Runtime ----
FROM node:22-alpine AS runtime

# Run as a non-root user.
RUN addgroup -S civic && adduser -S civic -G civic
WORKDIR /app

# Production-only deps
COPY --from=builder --chown=civic:civic /app/node_modules ./node_modules
COPY --from=builder --chown=civic:civic /app/package.json ./package.json
COPY --from=builder --chown=civic:civic /app/dist ./dist

# Copy non-compiled data + script assets that runtime reads.
COPY --chown=civic:civic src/data ./src/data
# Create empty data/ at the image layer. Real data is written at runtime
# by the ingestion orchestrator and persisted to a mounted volume in prod
# (Railway volume / Fly volume). We do NOT bake dev-state into the image.
RUN mkdir -p /app/data && chown civic:civic /app/data

ENV NODE_ENV=production
ENV PORT=8787

USER civic
EXPOSE 8787

# Process metadata for the platform's health check.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:8787/healthz || exit 1

CMD ["node", "dist/server.js"]
