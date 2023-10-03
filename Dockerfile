ARG IMAGE_TAG=latest
FROM alpine:$IMAGE_TAG

LABEL image.name="epicsoft_smarthost" \
      image.description="Docker Image for Smarthost (SMTP relay) based on Alpine Linux" \
      maintainer="epicsoft.de" \
      maintainer.name="Alexander Schwarz <schwarz@epicsoft.de>" \
      maintainer.copyright="Copyright 2022 epicsoft.de / Alexander Schwarz" \
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
                       postfix

ADD smarthost.sh smarthost.sh

CMD ["bash", "smarthost.sh"]
