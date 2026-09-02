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
    \
    echo "Patching notification_preferences schema..."; \
    sed -i "s/marketing BOOLEAN NOT NULL DEFAULT FALSE, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()/marketing BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()/" /app/src/db/schema.js; \
    \
    echo "Adding safe migration for existing notification_preferences tables..."; \
    python3 - <<'PY'
from pathlib import Path

p = Path("/app/src/db/schema.js")
s = p.read_text()

needle = """    CREATE TABLE IF NOT EXISTS notification_preferences ( 
      id UUID PRIMARY KEY, user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE, 
      in_app BOOLEAN NOT NULL DEFAULT TRUE, push BOOLEAN NOT NULL DEFAULT TRUE, email BOOLEAN NOT NULL DEFAULT TRUE, 
      job_alerts BOOLEAN NOT NULL DEFAULT TRUE, application_updates BOOLEAN NOT NULL DEFAULT TRUE, 
      payment_updates BOOLEAN NOT NULL DEFAULT TRUE, marketing BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW() 
    );"""

if needle in s and "ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS created_at" not in s:
    replacement = needle + """
    ALTER TABLE notification_preferences
      ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
"""
    s = s.replace(needle, replacement)

p.write_text(s)
PY

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

CMD ["node", "src/server.js"]
