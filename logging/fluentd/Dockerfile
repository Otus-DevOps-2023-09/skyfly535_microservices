FROM fluent/fluentd:v1.14.0-1.0
USER root
RUN gem uninstall -I elasticsearch && gem install elasticsearch -v 7.17.1
RUN gem install fluent-plugin-elasticsearch --no-document --version 5.2.3
RUN gem install fluent-plugin-grok-parser --no-document --version 2.6.2
USER fluent
ADD fluent.conf /fluentd/etc
