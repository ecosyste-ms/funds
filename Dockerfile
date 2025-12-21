# ========================================================
# Builder stage
# ========================================================
FROM ruby:3.4.8-alpine AS builder

ENV APP_ROOT=/usr/src/app
ENV DATABASE_PORT=5432
WORKDIR $APP_ROOT

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    postgresql-dev \
    tzdata \
    curl-dev \
    yaml-dev

# Will invalidate cache as soon as the Gemfile changes
COPY Gemfile Gemfile.lock .ruby-version $APP_ROOT/

RUN bundle config --global frozen 1 \
 && bundle config set without 'test' \
 && bundle install --jobs 2

# Copy application code
COPY . $APP_ROOT

# Precompile bootsnap and assets
RUN bundle exec bootsnap precompile --gemfile app/ lib/

# Precompile assets for a production environment.
# This is done to include assets in production images on Dockerhub.
RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rake assets:precompile

# ========================================================
# Final stage
# ========================================================
FROM ruby:3.4.8-alpine

ENV APP_ROOT=/usr/src/app
ENV DATABASE_PORT=5432
WORKDIR $APP_ROOT

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    nodejs \
    postgresql-libs \
    tzdata \
    curl \
    yaml \
    jemalloc

ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2
ENV RUBY_YJIT_ENABLE=1

# Copy compiled gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY . $APP_ROOT

# Copy precompiled bootsnap cache from builder
COPY --from=builder $APP_ROOT/tmp/cache/bootsnap $APP_ROOT/tmp/cache/bootsnap

# Copy precompiled assets from builder
COPY --from=builder $APP_ROOT/public/assets $APP_ROOT/public/assets

# Startup
CMD ["bin/docker-start"]
