#!/bin/sh
# Entrypoint de l'image Quotor.
#
# - DATABASE_URL absent  -> PostgreSQL interne au conteneur (données dans $DATA_DIR/postgres)
# - SECRET_KEY_BASE absent -> généré une fois et conservé dans $DATA_DIR
# - migrations + seeds (admin ADMIN_EMAIL/ADMIN_PASSWORD) puis démarrage de l'application
set -eu

DATA_DIR="${DATA_DIR:-/data}"
export MEDIA_DIR="${MEDIA_DIR:-$DATA_DIR/media}"
mkdir -p "$DATA_DIR" "$MEDIA_DIR"

log() { echo "[quotor] $*"; }

EMBEDDED_PG=0

if [ -z "${DATABASE_URL:-}" ] && [ "${ROLE:-all}" != "all" ]; then
  log "ROLE=${ROLE} nécessite une base partagée : définissez DATABASE_URL"
  exit 1
fi

if [ -z "${DATABASE_URL:-}" ]; then
  EMBEDDED_PG=1
  PG_BIN=$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -n 1)
  export PGDATA="$DATA_DIR/postgres"

  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    log "DATABASE_URL absent : initialisation d'une base PostgreSQL interne ($PGDATA)"
    "$PG_BIN/initdb" -D "$PGDATA" -U postgres --auth=trust --encoding=UTF8 --locale=C.UTF-8 >/dev/null
  else
    log "DATABASE_URL absent : utilisation de la base PostgreSQL interne existante"
  fi

  "$PG_BIN/pg_ctl" -D "$PGDATA" -l "$DATA_DIR/postgres.log" -w \
    -o "-c listen_addresses=127.0.0.1 -c unix_socket_directories=/tmp" start >/dev/null

  "$PG_BIN/createdb" -h 127.0.0.1 -U postgres quotor 2>/dev/null || true
  export DATABASE_URL="ecto://postgres@127.0.0.1/quotor"
fi

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  SECRET_FILE="$DATA_DIR/.secret_key_base"
  if [ ! -s "$SECRET_FILE" ]; then
    log "SECRET_KEY_BASE absent : génération d'une clé conservée dans $SECRET_FILE"
    head -c 48 /dev/urandom | base64 | tr -d '\n' > "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
  fi
  SECRET_KEY_BASE="$(cat "$SECRET_FILE")"
  export SECRET_KEY_BASE
fi

log "migrations et données initiales"
/app/bin/quotor eval "Quotor.Release.setup()"

if [ "$EMBEDDED_PG" = "0" ]; then
  exec /app/bin/quotor start
fi

# Base interne : on garde la main pour arrêter proprement PostgreSQL.
/app/bin/quotor start &
APP_PID=$!

shutdown() {
  log "arrêt"
  kill -TERM "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
  "$PG_BIN/pg_ctl" -D "$PGDATA" -m fast stop >/dev/null || true
  exit 0
}
trap shutdown TERM INT

set +e
wait "$APP_PID"
STATUS=$?
"$PG_BIN/pg_ctl" -D "$PGDATA" -m fast stop >/dev/null || true
exit "$STATUS"
