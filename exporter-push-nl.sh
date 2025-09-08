#!/bin/sh
set -eu

METRICS_FILE="/tmp/metrics"
PORT=9101
IMAGE_ORIG="swr.eu-nl.otc.t-systems.com/container/nginx:latest"
IMAGE_NEW="swr.eu-nl.otc.t-systems.com/container/swr-performance-test"
REGISTRY="swr.eu-nl.otc.t-systems.com"

# --- Auth config (for ctr push) ---
if [ -n "${USER:-}" ] && [ -n "${PASS:-}" ]; then
    mkdir -p /root/.docker
    cat > /root/.docker/config.json <<EOF
{
  "auths": {
    "$REGISTRY": {
      "auth": "$(printf "%s" "$USER:$PASS" | base64 -w0)"
    }
  }
}
EOF
    echo "Auth configured for $REGISTRY"
fi

# Start BuildKit daemon
buildkitd --addr unix:///run/buildkit/buildkitd.sock >/tmp/buildkitd.log 2>&1 &
while ! buildctl --addr unix:///run/buildkit/buildkitd.sock debug workers >/dev/null 2>&1; do
    sleep 1
done

# Start metrics server in background
while true; do
    (echo -e "HTTP/1.1 200 OK\n"; cat "$METRICS_FILE" 2>/dev/null) | nc -l -p "$PORT" -q 1
done &

# --- Main loop ---
while true; do
    TAG=$(date +%s)
    IMAGE_TAG="$IMAGE_NEW:$TAG"
    echo ">>> Building $IMAGE_TAG"

    # Dynamic Dockerfile
    echo "FROM $IMAGE_ORIG" > Dockerfile
    echo "RUN echo $TAG > /random.txt" >> Dockerfile

    buildctl build \
      --frontend dockerfile.v0 \
      --local context=. \
      --local dockerfile=. \
      --output type=docker,name=$IMAGE_TAG | ctr -n default images import -

    # Measuring the pull
    echo ">>> Pushing $IMAGE_TAG"
    START_PUSH=$(date +%s.%N)
    ctr -n default images push --user "$USER:$PASS" "$IMAGE_TAG"
    END_PUSH=$(date +%s.%N)
    ELAPSED_PUSH=$(echo "$END_PUSH - $START_PUSH" | bc)

    # Metrics
    {
      echo "# HELP image_push_duration_seconds Duration of container image push"
      echo "# TYPE image_push_duration_seconds gauge"
      echo "image_push_duration_seconds $ELAPSED_PUSH"
    } > "$METRICS_FILE"

    # Save latest tag for pull side
    mkdir -p /shared
    echo "$IMAGE_TAG" > /shared/image_tag-nl.txt
    echo "$(date +%s)" > /tmp/heartbeat

    sleep 10
done
