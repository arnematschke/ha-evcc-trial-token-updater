FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache bash curl jq python3 py3-yaml

COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]
