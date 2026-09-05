# forge — генератор интеграций платёжных провайдеров из OpenAPI (Ruby 3.3)
FROM ruby:3.3-slim AS base

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8

COPY Gemfile Gemfile.lock* ./
RUN bundle install

COPY . .

# Быстрая самопроверка сборки: CLI загружается и показывает команды
RUN bin/forge help

# --- CLI (по умолчанию): docker run --rm forge analyze --spec … ---
FROM base AS cli
ENTRYPOINT ["bin/forge"]
CMD ["help"]

# --- Веб-интерфейс: docker build --target web -t forge-web . && docker run -p 8080:8080 forge-web ---
FROM base AS web
ENV PORT=8080 FORGE_WORKDIR=/data/web RACK_ENV=production
RUN mkdir -p /data/web
EXPOSE 8080
ENTRYPOINT ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:8080", "-e", "production", "config.ru"]
CMD []
