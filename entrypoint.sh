#!/usr/bin/env sh
# Container entrypoint: run the DB migration with a bounded retry loop, then
# start uvicorn. Mirrors the ExecStartPre step from Lab 1's systemd unit.
set -e

ATTEMPTS=10
DELAY=2

i=1
while [ "$i" -le "$ATTEMPTS" ]; do
    echo "[entrypoint] running migration (attempt $i/$ATTEMPTS)..."
    if python -m app.migrate; then
        break
    fi
    if [ "$i" -eq "$ATTEMPTS" ]; then
        echo "[entrypoint] migration still failing, giving up." >&2
        exit 1
    fi
    sleep "$DELAY"
    i=$((i + 1))
done

echo "[entrypoint] starting uvicorn on 0.0.0.0:5200..."
exec uvicorn app.main:app --host 0.0.0.0 --port 5200
