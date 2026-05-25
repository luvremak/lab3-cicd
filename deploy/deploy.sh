#!/usr/bin/env bash
# deploy.sh — runs on the target node, invoked over SSH from the CD job.
#
# Inputs (environment variables):
#   IMAGE_REF   full image reference to deploy, e.g.
#               ghcr.io/owner/repo:v1.2.3
#
# Steps:
#   1. write IMAGE_REF into /opt/mywebapp/.env so docker-compose pulls it
#   2. systemctl restart mywebapp.service — the unit pulls and brings up
#   3. wait for the container to be healthy (probe /health/alive locally)
#   4. report status
#
set -euo pipefail

APP_DIR="/opt/mywebapp"
SERVICE="mywebapp.service"
HEALTH_URL="http://127.0.0.1/items"   # via nginx (200 = empty list)
DEPLOY_TIMEOUT=60

: "${IMAGE_REF:?IMAGE_REF must be provided by the CD job}"

echo "[deploy] target image: ${IMAGE_REF}"

# 1. Record the chosen image so the systemd unit picks it up.
printf "IMAGE_REF=%s\n" "$IMAGE_REF" | sudo tee "${APP_DIR}/.env" > /dev/null
sudo chmod 0640 "${APP_DIR}/.env"

# 2. Restart the unit — ExecStartPre pulls the image, ExecStart brings it up.
echo "[deploy] restarting ${SERVICE}..."
sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE}"

# 3. Wait for the service to respond (nginx → app → DB).
echo "[deploy] waiting for service to become healthy (timeout ${DEPLOY_TIMEOUT}s)..."
for i in $(seq 1 "$DEPLOY_TIMEOUT"); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || true)
    if [ "$code" = "200" ]; then
        echo "[deploy] service responded with HTTP $code after ${i}s."
        break
    fi
    if [ "$i" -eq "$DEPLOY_TIMEOUT" ]; then
        echo "[deploy] service did not become healthy in ${DEPLOY_TIMEOUT}s." >&2
        sudo systemctl status "$SERVICE" --no-pager || true
        exit 1
    fi
    sleep 1
done

# 4. Prune dangling images so old versions do not fill the disk.
sudo docker image prune -f >/dev/null || true

echo "[deploy] deployment of ${IMAGE_REF} completed successfully."
