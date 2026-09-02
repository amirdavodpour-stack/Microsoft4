FROM node:24-alpine AS build

RUN apk add --no-cache unzip

WORKDIR /work

COPY HOPE-*.zip /tmp/hope.zip

RUN set -eux; \
    mkdir -p /work/source /app; \
    unzip -q /tmp/hope.zip -d /work/source; \
    BACKEND_PACKAGE="$(find /work/source -type f -path '*/backend/package.json' -print -quit)"; \
    test -n "$BACKEND_PACKAGE"; \
    BACKEND_DIR="$(dirname "$BACKEND_PACKAGE")"; \
    cp -a "$BACKEND_DIR"/. /app/; \
    test -f /app/package.json; \
    test -f /app/src/server.js; \
    test -f /app/src/db/schema.js; \
    echo "Creating database migration..."; \
    cat > /app/src/preflight-migration.js <<'EOF'
import { getPool } from './db.js';

const pool = getPool();

if (!pool) {
  console.log('DATABASE_URL not configured; skipping PostgreSQL migration.');
  process.exit(0);
}

const client = await pool.connect();

try {
  console.log('Running HOPE PostgreSQL preflight migration...');

  await client.query(`
    ALTER TABLE notification_preferences
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  `);

  console.log('notification_preferences.created_at is ready.');
} finally {
  client.release();
  await pool.end();
}
EOF

WORKDIR /app

RUN npm ci --omit=dev && npm cache clean --force

FROM node:24-alpine

WORKDIR /app

ENV NODE_OPTIONS=--enable-source-maps

RUN addgroup -S hope && adduser -S -G hope hope \
    && mkdir -p /app/data /app/storage /app/tmp \
    && chown -R hope:hope /app

COPY --from=build --chown=hope:hope /app /app

USER hope

EXPOSE 3000

CMD ["sh", "-c", "node src/preflight-migration.js && node src/server.js"]
