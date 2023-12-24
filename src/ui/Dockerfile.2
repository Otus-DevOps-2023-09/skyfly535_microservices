FROM ubuntu:16.04

ARG APP_HOME=/app

RUN set -x \
 && apt-get update \
 && apt-get install -y ruby-full ruby-dev build-essential \
 && apt-get clean \
 && gem install bundler -v 2.3.26 --no-ri --no-rdoc

ARG APP_HOME /app
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/
RUN bundle install
ADD . $APP_HOME/


ENV POST_SERVICE_HOST=post POST_SERVICE_PORT=5000 COMMENT_SERVICE_HOST=comment COMMENT_SERVICE_PORT=9292

CMD ["puma"]
