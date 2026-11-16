#!/usr/bin/env bash
# Proves the stale containerd pid check works, with no Docker daemon: it must
# remove a pid file (and its sockets) whose process does not exist, and leave
# alone a pid file whose process is alive, one that is not a process id, and a
# folder with no pid file. Runs on throwaway folders, never on the real one.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/containerd-stale-pid.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

# The check reads /proc, which only Linux has. Elsewhere it leaves every pid
# file alone, and there is nothing to prove.
if [ ! -d /proc/self ]; then
    echo "containerd stale pid self-test: skipped: no /proc on this host, so the check never removes anything"
    exit 0
fi

# A process id that certainly does not exist: start a process, end it, and
# wait for it, so its id is free.
sleep 60 &
dead=$!
kill "$dead"
wait "$dead" 2> /dev/null || true
if [ -d "/proc/$dead" ]; then
    echo "containerd stale pid self-test: FAIL: could not make a dead process id" >&2
    exit 1
fi

# case <description> <pid file content, or "none"> <removed|kept>
case_() {
    local description="$1" content="$2" want="$3"
    local dir="$work/case$RANDOM"
    mkdir -p "$dir"
    : > "$dir/containerd.sock"
    : > "$dir/containerd.sock.ttrpc"
    : > "$dir/containerd-debug.sock"
    : > "$dir/containerd.toml"
    if [ "$content" != none ]; then printf '%s' "$content" > "$dir/containerd.pid"; fi

    "$check" "$dir" > /dev/null

    local got
    if [ "$content" = none ]; then
        [ -e "$dir/containerd.sock" ] && got=kept || got=removed
    elif [ ! -e "$dir/containerd.pid" ] && [ ! -e "$dir/containerd.sock" ] \
        && [ ! -e "$dir/containerd.sock.ttrpc" ] && [ ! -e "$dir/containerd-debug.sock" ]; then
        got=removed
    elif [ -e "$dir/containerd.pid" ] && [ -e "$dir/containerd.sock" ]; then
        got=kept
    else
        got=partly-removed
    fi
    # Its config is never touched.
    [ -e "$dir/containerd.toml" ] || got="$got, config removed"

    if [ "$got" = "$want" ]; then
        echo "containerd stale pid self-test: ok: $description ($want)"
    else
        echo "containerd stale pid self-test: WRONG: $description (wanted $want, got $got)" >&2
        failures=$((failures + 1))
    fi
}

case_ "a pid whose process does not exist" "$dead" removed
case_ "a dead pid with a trailing newline" "$dead
" removed
case_ "a pid whose process is alive (this shell)" "$$" kept
case_ "a live pid owned by root (pid 1)" "1" kept
case_ "a pid file that is not a process id" "abc" kept
case_ "an empty pid file" "" kept
case_ "no pid file" none kept

if [ "$failures" -ne 0 ]; then
    echo "containerd stale pid self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "containerd stale pid self-test: OK"
