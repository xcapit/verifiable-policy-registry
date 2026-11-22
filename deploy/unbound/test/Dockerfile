# SPDX-License-Identifier: AGPL-3.0-only
# Pinned resolver for the resolver check (examples/resolver, VPR-055). Not a production image.
# Unbound is built from the NLnet Labs release tarball, verified against a fixed SHA-256, on a Debian
# base pinned by digest. The build and runtime libraries come from Debian trixie at build time and
# are not pinned individually; `unbound -V` in the evidence file records what was built.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS build
ARG UNBOUND_VERSION=1.26.2
ARG UNBOUND_SHA256=d8ee7aa6bbb3ff1be7d9e57637d0d0ec2f18273a8efff1a0afe2c665858b96f7
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential ca-certificates curl libexpat1-dev libssl-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSLo unbound.tar.gz "https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz" \
 && echo "${UNBOUND_SHA256}  unbound.tar.gz" | sha256sum -c - \
 && tar xzf unbound.tar.gz --strip-components=1 \
 && ./configure --prefix=/usr/local --sysconfdir=/etc --disable-static \
 && make -j"$(nproc)" \
 && make install

FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
RUN apt-get update \
 && apt-get install -y --no-install-recommends bind9-dnsutils libexpat1 libssl3t64 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --no-create-home unbound
COPY --from=build /usr/local/ /usr/local/
RUN ldconfig
EXPOSE 53/udp 53/tcp
ENTRYPOINT ["/usr/local/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]
