FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends asterisk asterisk-core-sounds-en-gsm \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /etc/asterisk/* \
 && groupmod -g 10010 asterisk && usermod -u 10010 asterisk \
 && mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk /var/lib/asterisk \
 && chown -R asterisk:asterisk /var/run/asterisk /var/log/asterisk /var/spool/asterisk /var/lib/asterisk
COPY config/ /etc/asterisk/
# numeric user so Kubernetes can verify runAsNonRoot
USER 10010:10010
EXPOSE 5060/udp 8088/tcp
HEALTHCHECK --interval=10s --timeout=3s CMD asterisk -rx "pjsip show transports" | grep -q transport-udp || exit 1
ENTRYPOINT ["asterisk", "-f", "-vvv"]
