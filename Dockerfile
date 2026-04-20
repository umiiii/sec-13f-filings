FROM ruby:3.0.2-bullseye

ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production \
    NODE_ENV=production

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs postgresql-client python3 build-essential \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && npm install -g yarn@1.22.22 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .

RUN SECRET_KEY_BASE=build-placeholder bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "foreman", "start", "-m", "web=1,worker=1,clock=1"]
