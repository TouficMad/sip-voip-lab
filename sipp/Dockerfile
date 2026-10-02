FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends sip-tester \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 sipp
COPY scenarios/ /sipp/
COPY run-load-test.sh /usr/local/bin/run-load-test
USER sipp
WORKDIR /tmp
ENTRYPOINT ["run-load-test"]
