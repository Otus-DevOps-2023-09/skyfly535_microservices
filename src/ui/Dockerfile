FROM alpine:3.14

WORKDIR /app
COPY Gemfile* ./

RUN set -x \
 && apk --no-cache --update add ruby-full ruby-dev build-base \
 && gem install bundler:1.17.2 --no-document \
 && bundle install \
 && apk del ruby-dev build-base

COPY . ./
ENV POST_SERVICE_HOST=post POST_SERVICE_PORT=5000 COMMENT_SERVICE_HOST=comment COMMENT_SERVICE_PORT=9292
EXPOSE 9292/tcp

CMD ["puma"]
