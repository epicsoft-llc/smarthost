ARG IMAGE_TAG=latest
FROM alpine:$IMAGE_TAG

ARG BUILD_DATE="development"
LABEL org.label-schema.name="Smarthost" \
      org.label-schema.description="Docker Image for Smarthost (SMTP relay) based on Alpine Linux" \
      org.label-schema.vendor="epicsoft LLC / Alexander Schwarz <as@epicsoft.one>" \
      org.label-schema.version="latest" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.build-date="$BUILD_DATE" \
      org.label-schema.url="https://gitlab.com/epicdocker/smarthost" \
      org.label-schema.vcs-url="https://gitlab.com/epicdocker/smarthost/tree/master"

LABEL image.name="epicsoft_smarthost" \
      image.description="Docker Image for Smarthost (SMTP relay) based on Alpine Linux" \
      maintainer="epicsoft LLC" \
      maintainer.name="Alexander Schwarz <as@epicsoft.one>" \
      maintainer.copyright="Copyright 2022-2023 epicsoft LLC / Alexander Schwarz" \
      license="MIT"

ENV SMARTHOST_HOST ""
ENV SMARTHOST_PORT "587"
ENV SMARTHOST_USER ""
ENV SMARTHOST_PASSWORD ""
ENV SMARTHOST_DOMAIN ""
ENV SMARTHOST_USE_TLS "true"
ENV SMARTHOST_NETWORKS "192.168.0.0/16,172.16.0.0/12"
ENV SMARTHOST_ADD_MISSING_HEADERS "true"
ENV SMARTHOST_FORCE_FROM ""
ENV SMARTHOST_INIT_ALIAS_DATABASE "true"

RUN apk --no-cache add bash \
                       postfix \
                       ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/cache/apk/*

ADD smarthost.sh smarthost.sh

CMD ["bash", "smarthost.sh"]
