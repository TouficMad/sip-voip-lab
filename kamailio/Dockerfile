FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends kamailio kamailio-extra-modules kamailio-utils-modules \
 && rm -rf /var/lib/apt/lists/* \
 && groupmod -g 10011 kamailio && usermod -u 10011 kamailio \
 && mkdir -p /run/kamailio && chown kamailio:kamailio /run/kamailio
COPY kamailio.cfg dispatcher.list /etc/kamailio/
# numeric user so Kubernetes can verify runAsNonRoot
USER 10011:10011
EXPOSE 5060/udp 9090/tcp
HEALTHCHECK --interval=10s --timeout=3s CMD kamcmd -s unixs:/run/kamailio/kamailio_ctl core.uptime > /dev/null || exit 1
ENTRYPOINT ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg", "-Y", "/run/kamailio"]
