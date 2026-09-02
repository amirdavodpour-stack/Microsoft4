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
    echo "Patching notification_preferences schema..."; \
    sed -i 's/marketing BOOLEAN NOT NULL DEFAULT FALSE, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()/marketing BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()/' /app/src/db/schema.js; \
    echo "Verifying schema patch..."; \
    grep -n -A6 -B2 "CREATE TABLE IF NOT EXISTS notification_preferences" /app/src/db/schema.js; \
    echo "Schema patch completed."

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
