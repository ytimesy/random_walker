# syntax = docker/dockerfile:1

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t my-app .
# docker run -d -p 80:80 -p 443:443 --name my-app -e RAILS_MASTER_KEY=<value from config/master.key> my-app

ARG RUBY_VERSION=3.3.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails

RUN apt-get update -qq &&     apt-get install --no-install-recommends -y curl libjemalloc2 libyaml-0-2 &&     rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production"     BUNDLE_DEPLOYMENT="1"     BUNDLE_PATH="/usr/local/bundle"     BUNDLE_WITHOUT="development:test"

FROM base AS build

RUN apt-get update -qq &&     apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config &&     rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 &&     rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails &&     useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash &&     chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
