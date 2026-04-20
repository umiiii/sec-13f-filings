FROM ruby:3.0.2-bullseye

ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production \
    NODE_ENV=production

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_VERSION=14.21.3
RUN curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && npm install -g yarn@1.22.22

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .

RUN SECRET_KEY_BASE=build-placeholder bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "foreman", "start", "-m", "web=1,worker=1,clock=1"]
