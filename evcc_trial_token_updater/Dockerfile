FROM alpine:3.22

RUN apk add --no-cache \
    bash \
    curl \
    jq

COPY run.sh /run.sh
COPY rootfs /

RUN chmod +x /run.sh
RUN chmod +x /usr/bin/update-token.sh

CMD [ "/run.sh" ]
