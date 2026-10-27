# Finture — imagem de DESENVOLVIMENTO local do Chatwoot (não usar em produção).
# O código-fonte NÃO é copiado: ele entra por bind mount (hot reload). A imagem
# carrega só o toolchain e as gems; node_modules fica no volume "node_modules",
# populado pelo serviço one-shot "deps" do docker-compose.local.yaml.
#
# Debian (glibc) em vez de Alpine: o Gemfile.lock já traz binários x86_64-linux
# (nokogiri, grpc, ffi...), o que torna o build bem mais rápido.
FROM node:24.13.0-bookworm-slim AS node

FROM ruby:3.4.4-slim-bookworm

ARG PNPM_VERSION=10.2.0
ARG BUNDLER_VERSION=2.5.16

ENV LANG=C.UTF-8 \
    TZ=UTC \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/usr/local/pnpm \
    PATH=/usr/local/pnpm:$PATH

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    imagemagick \
    libffi-dev \
    libpq-dev \
    libvips42 \
    libyaml-dev \
    postgresql-client \
    shared-mime-info \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g "pnpm@${PNPM_VERSION}" \
  && node --version && pnpm --version

RUN gem install bundler -v "${BUNDLER_VERSION}"

WORKDIR /app

# Gems de development e test na imagem. Mudou o Gemfile.lock? `make build`.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without '' \
  && bundle install \
  && sha256sum Gemfile.lock | cut -d' ' -f1 > /usr/local/bundle/.finture-gemfile-lock.sha \
  && rm -rf /usr/local/bundle/cache/*.gem

RUN git config --system --add safe.directory /app

EXPOSE 3000 3036
