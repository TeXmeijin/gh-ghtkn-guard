FROM alpine:3.22

ARG GH_VERSION=2.92.0
ARG TARGETARCH
ARG GH_LINUX_AMD64_SHA256=b57848131bdf0c229cd35e1f2a51aa718199858b2e728410b37e89a428943ec4
ARG GH_LINUX_ARM64_SHA256=c2248526dd0160c08d3fccca2332c3c1a07c15a78b23978e77735f1b5a18cfee

RUN apk add --no-cache ca-certificates curl git less openssh-client tar \
  && case "$TARGETARCH" in \
    amd64) GH_ARCH=amd64; GH_SHA256="$GH_LINUX_AMD64_SHA256" ;; \
    arm64) GH_ARCH=arm64; GH_SHA256="$GH_LINUX_ARM64_SHA256" ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac \
  && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" -o /tmp/gh.tar.gz \
  && echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/gh.tar.gz -C /tmp \
  && mv "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh \
  && rm -rf /tmp/gh*

WORKDIR /work
