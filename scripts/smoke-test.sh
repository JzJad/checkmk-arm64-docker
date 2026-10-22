#!/bin/bash
# Start the given image, wait for the site to come up and check that the GUI
# answers. Usage: scripts/smoke-test.sh <image> [timeout seconds]

set -e -o pipefail

IMAGE="${1:?usage: $0 <image> [timeout seconds]}"
TIMEOUT="${2:-600}"
NAME="cmk-smoke-test-$$"
PORT=5000
SITE=cmk

cleanup() {
    docker logs "$NAME" 2>&1 | tail -n 50 || true
    docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$NAME" \
    -e CMK_SITE_ID="$SITE" \
    -e CMK_PASSWORD=smoke-test \
    --tmpfs "/opt/omd/sites/$SITE/tmp:uid=1000,gid=1000" \
    -p "127.0.0.1:$PORT:5000" \
    "$IMAGE" >/dev/null

echo "### Waiting up to ${TIMEOUT}s for the container to start"
deadline=$((SECONDS + TIMEOUT))
until docker logs "$NAME" 2>&1 | grep -q '### CONTAINER STARTED'; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != "true" ]; then
        echo "ERROR: container exited"
        exit 1
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: timed out waiting for the container"
        exit 1
    fi
    sleep 5
done

echo "### omd status"
docker exec "$NAME" omd status "$SITE"

echo "### Checking that PHP is up to date"
docker exec "$NAME" dpkg-query -W 'php*-cgi'
outdated=$(docker exec "$NAME" bash -c \
    "apt-get update -qq && apt list --upgradable 2>/dev/null | grep -E '^(php|libapache2-mod-php)' || true")
if [ -n "$outdated" ]; then
    echo "ERROR: PHP packages have pending updates:"
    echo "$outdated"
    exit 1
fi

echo "### Checking the login page"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/$SITE/check_mk/login.py")
if [ "$code" != "200" ]; then
    echo "ERROR: login page returned HTTP $code"
    exit 1
fi

echo "### Smoke test passed"
