FROM alpine:latest

RUN apk add --no-cache \
    bash \
    curl \
    coreutils \
    containerd-ctr \
    buildkit \
    buildctl \
    netcat-openbsd \
    runc \
    git

COPY exporter.sh /exporter.sh
RUN chmod +x /exporter.sh
