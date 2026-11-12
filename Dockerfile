# syntax=docker/dockerfile:1
#
# Image de production de Quotor.
#
#   docker build -t quotor .
#   docker run -p 4000:4000 -v quotor_data:/data quotor            # base PostgreSQL interne
#   docker run -p 4000:4000 -e DATABASE_URL=postgresql://… quotor  # base externe (Neon…)
#
# Si DATABASE_URL n'est pas fourni, l'entrypoint initialise et démarre un
# PostgreSQL local dans le conteneur (données dans /data/postgres).

ARG ELIXIR_IMAGE=elixir:1.19
ARG RUNNER_IMAGE=debian:trixie-slim

########## Build ##########
FROM ${ELIXIR_IMAGE} AS builder

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends build-essential git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile
RUN mix assets.setup

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
RUN mix release

########## Runtime ##########
FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates curl tini \
      ffmpeg python3 \
      postgresql \
    && curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

RUN useradd --create-home --uid 1000 quotor \
    && mkdir -p /data && chown quotor:quotor /data

WORKDIR /app
COPY --from=builder --chown=quotor:quotor /app/_build/prod/rel/quotor ./
COPY --chown=quotor:quotor --chmod=755 docker/entrypoint.sh /app/entrypoint.sh

USER quotor

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    DATA_DIR=/data \
    MEDIA_DIR=/data/media

VOLUME ["/data"]
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
