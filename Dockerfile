ARG IMAGE_TAG=latest
FROM alpine:$IMAGE_TAG

ARG IMAGE_TAG=latest
ARG BUILD_DATE="development"
ARG VCS_REF="development"
LABEL org.label-schema.name="Smarthost" \
      org.label-schema.description="Docker Image for Smarthost (SMTP relay) based on official Alpine image" \
      org.label-schema.vendor="epicsoft LLC / Alexander Schwarz <info@epicsoft.one>" \
      org.label-schema.url="https://gitlab.com/epicsoft-networks/smarthost" \
      org.label-schema.vcs-url="https://gitlab.com/epicsoft-networks/smarthost/tree/master" \
      org.label-schema.vcs-ref=${VCS_REF} \
      org.label-schema.version=${IMAGE_TAG} \
      org.label-schema.schema-version="1.0" \
      org.label-schema.build-date=${BUILD_DATE}

LABEL org.opencontainers.image.title="Smarthost" \
      org.opencontainers.image.description="Docker Image for Smarthost (SMTP relay) based on official Alpine image" \
      org.opencontainers.image.vendor="epicsoft LLC" \
      org.opencontainers.image.authors="Alexander Schwarz <info@epicsoft.one>" \
      org.opencontainers.image.url="https://hub.docker.com/r/epicsoft/smarthost" \
      org.opencontainers.image.source="https://gitlab.com/epicsoft-networks/smarthost" \
      org.opencontainers.image.documentation="https://gitlab.com/epicsoft-networks/smarthost/blob/master/README.md" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version=${IMAGE_TAG} \
      org.opencontainers.image.revision=${VCS_REF} \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.base.name="docker.io/library/alpine:${IMAGE_TAG}"

LABEL image.name="epicsoft_smarthost" \
      image.description="Docker Image for Smarthost (SMTP relay) based on official Alpine image" \
      maintainer="epicsoft LLC" \
      maintainer.name="Alexander Schwarz <info@epicsoft.one>" \
      maintainer.url="https://epicsoft.one/" \
      maintainer.copyright="Copyright 2022-2026 epicsoft LLC / Alexander Schwarz" \
      license="MIT"

ENV SMARTHOST_HOST=""
ENV SMARTHOST_PORT="587"
ENV SMARTHOST_USER=""
ENV SMARTHOST_PASSWORD=""
ENV SMARTHOST_DOMAIN=""
ENV SMARTHOST_TLS_SECURITY_LEVEL="may"
ENV SMARTHOST_NETWORKS="192.168.0.0/16,172.16.0.0/12"
ENV SMARTHOST_ADD_MISSING_HEADERS="true"
ENV SMARTHOST_FORCE_FROM=""
ENV SMARTHOST_INIT_ALIAS_DATABASE="true"

RUN apk --no-cache add bash \
                       tzdata \
                       postfix \
                       ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/cache/apk/*

ADD smarthost.sh smarthost.sh

CMD [ "bash", "smarthost.sh" ]
