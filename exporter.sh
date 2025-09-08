#!/bin/sh
set -eu

METRICS_FILE="/tmp/metrics"
PORT=9102

# Wait until /shared/image_tag-int.txt exists
while [ ! -f /shared/image_tag-int.txt ]; do
    echo "Waiting for /shared/image_tag-int.txt..."
    sleep 5
done

# Metrics server in background
while true; do
    (echo -e "HTTP/1.1 200 OK\n"; cat "$METRICS_FILE" 2>/dev/null) | nc -l -p "$PORT" -q 1 &
    sleep 1
done &

# Main loop
while true; do
    IMAGE_PULL=$(cat /shared/image_tag-int.txt)

    # Remove image to force full download
    ctr -n default images rm "$IMAGE_PULL" >/dev/null 2>&1 || true

    # Pull measurement 
    START_PULL=$(date +%s.%N)
    ctr -n default images pull --user "$USER:$PASS" "$IMAGE_PULL"
    END_PULL=$(date +%s.%N)

    ELAPSED_PULL=$(echo "$END_PULL - $START_PULL" | bc)

    # Write Prometheus metrics
    {
      echo "# HELP image_pull_duration_seconds Duration of container image pull"
      echo "# TYPE image_pull_duration_seconds gauge"
      echo "image_pull_duration_seconds $ELAPSED_PULL"
    } > "$METRICS_FILE"

    echo "$(date +%s)" > /tmp/heartbeat
    sleep 10
done
