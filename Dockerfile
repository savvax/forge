# forge — генератор интеграций платёжных провайдеров из OpenAPI (Ruby 3.3)
FROM ruby:3.3-slim

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

ENTRYPOINT ["bin/forge"]
CMD ["help"]
