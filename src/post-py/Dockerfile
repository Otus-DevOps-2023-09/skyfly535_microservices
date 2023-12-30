FROM python:3.6-alpine

WORKDIR /app
COPY . ./

RUN set -x \
 && apk --no-cache --update add build-base \
 && pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && apk del build-base

ENV POST_DATABASE_HOST=post_db POST_DATABASE=posts

ENTRYPOINT ["python3", "post_app.py"]
