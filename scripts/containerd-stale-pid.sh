#!/usr/bin/env bash
# Clears a stale containerd pid file left by a Docker daemon that did not shut
# down cleanly, for example after the agent container's worker restarted.
#
# The symptom: `dockerd` starts, logs "containerd is still running" for a
# process id that no longer exists, waits 15 seconds and exits. It reads that
# pid from <folder>/containerd.pid.
#
# If the pid file names a process that does not exist, this removes the pid
# file and the containerd sockets beside it, so the next `dockerd` starts its
# own containerd. It never removes a pid file whose process exists, nor one
# whose content is not a process id. Run it only while dockerd is not running.
#
# Usage: scripts/containerd-stale-pid.sh [folder]   (default: /var/run/docker/containerd)
# Exit status 0 in every case it understands; it prints what it did.
set -euo pipefail

folder="${1:-/var/run/docker/containerd}"
pidfile="$folder/containerd.pid"

if [ ! -e "$pidfile" ]; then
    echo "containerd-stale-pid: no pid file in $folder"
    exit 0
fi

pid=$(tr -d '[:space:]' < "$pidfile")

if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    echo "containerd-stale-pid: left alone: $pidfile does not hold a process id"
    exit 0
fi

# Without /proc (not Linux) it cannot tell a live process from a dead one.
if [ ! -d /proc/self ]; then
    echo "containerd-stale-pid: left alone: no /proc here, so it cannot tell whether process $pid is alive"
    exit 0
fi

# /proc/<pid> exists for any live process, whoever owns it. (kill -0 fails for
# a live process owned by another user, so it is not used here.)
if [ -d "/proc/$pid" ]; then
    echo "containerd-stale-pid: left alone: process $pid in $pidfile is alive"
    exit 0
fi

rm -f "$pidfile" "$folder/containerd.sock" "$folder/containerd.sock.ttrpc" "$folder/containerd-debug.sock"
echo "containerd-stale-pid: removed the stale pid file (process $pid does not exist) and its sockets in $folder"
