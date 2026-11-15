#!/usr/bin/env bash
# Makes Docker ready for `make check` in a fresh agent container.
#
# 1. Starts the Docker daemon if it is not running. In an agent container
#    nothing starts it, so this runs `dockerd` in the background as root.
# 2. Makes sure the pinned Swift image is present. Docker Hub rate-limits
#    anonymous pulls, so it pulls from mirror.gcr.io first and from Docker Hub
#    only if the mirror fails, retrying each with backoff.
#
# Usage: scripts/docker-ready.sh <tag>   (for example 6.4.2-resolute)
set -euo pipefail

tag="${1:?usage: scripts/docker-ready.sh <swift image tag>}"
image="swift:$tag"
sources=("mirror.gcr.io/library/swift:$tag" "docker.io/library/swift:$tag")

if ! command -v docker > /dev/null 2>&1; then
    echo "docker-ready: FAIL: docker is not installed" >&2
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "docker-ready: FAIL: the Docker daemon is not running, and starting it needs root" >&2
        exit 1
    fi
    echo "docker-ready: starting dockerd (log: /tmp/dockerd.log)"
    nohup dockerd > /tmp/dockerd.log 2>&1 &
    for _ in $(seq 1 60); do
        docker info > /dev/null 2>&1 && break
        sleep 1
    done
    if ! docker info > /dev/null 2>&1; then
        echo "docker-ready: FAIL: dockerd did not start within 60 s. See /tmp/dockerd.log" >&2
        exit 1
    fi
fi

if docker image inspect "$image" > /dev/null 2>&1; then
    echo "docker-ready: OK ($image is present)"
    exit 0
fi

for source in "${sources[@]}"; do
    for attempt in 1 2 3; do
        echo "docker-ready: pulling $source (attempt $attempt)"
        if docker pull -q "$source"; then
            docker tag "$source" "$image"
            echo "docker-ready: OK ($image from $source)"
            exit 0
        fi
        sleep $((attempt * 5))
    done
done

echo "docker-ready: FAIL: could not pull $image from any source" >&2
exit 1
