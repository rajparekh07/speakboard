# Rung 1 checks for the pure-Swift core. Swift runs only inside Docker, so the
# host needs Docker, bash, grep and make. See CONTRIBUTING.md.
#
# `make check-native` runs the same steps without Docker, with the active Swift
# toolchain: on a Mac with Xcode, or on any host with Swift installed. It runs
# them by calling this Makefile again with NATIVE=1, so both paths share one
# list of steps (CHECK_STEPS) and one recipe per step.
#
# Keep this file to GNU make 3.81, the make macOS ships.
#
# What this file defends, and what it does not. The variables the check steps
# read are declared `override`, and the repo is mounted by the shell's own
# working directory rather than make's CURDIR, so a value given for any of them
# on the command line, in the environment or through MAKEFLAGS (make check
# RUN=, SWIFT_TAG=..., CHECK_STEPS=, CURDIR=...) is ignored; and make check
# refuses NATIVE=1. Make's own flags (-i, -k, -o, -n, -t), make's own
# variables (SHELL=, MAKE=) and edits to this file are not defended: with
# them, "make check: OK" can print for a check that did not run. CI, which runs
# this file unmodified, is the authority for a green check.

# The Swift image, pinned to an exact Swift version and Ubuntu release.
override SWIFT_TAG := 6.4.2-resolute
override SWIFT_IMAGE := swift:$(SWIFT_TAG)
# The Swift version alone (6.4.2), which make check-native requires of the
# active toolchain.
override SWIFT_VERSION := $(firstword $(subst -, ,$(SWIFT_TAG)))

# Runs a command in the Swift image with the repo mounted at /work, as the
# calling user, so files in .build are not owned by root.
# "$$(pwd)", not $(CURDIR): CURDIR can be set on the command line.
override SWIFT_RUN := docker run --rm -v "$$(pwd)":/work -w /work \
	--user "$$(id -u):$$(id -g)" -e HOME=/tmp $(SWIFT_IMAGE)

# NATIVE=1 runs each step on the host, with no Docker: nothing depends on
# docker-ready, and the core imports guard gets the compiler frontend from
# scripts/native-tools.sh (on macOS, `xcrun -f swift-frontend`), and fails if
# there is none.
ifeq ($(NATIVE),1)
# make check: OK must only ever come from the pinned image, so make check
# refuses NATIVE=1, from the command line or the environment. (check is also
# the default goal.) make check-native's own call names the steps, not check.
ifneq ($(filter check,$(if $(MAKECMDGOALS),$(MAKECMDGOALS),check)),)
$(error make check runs only in the pinned Swift image, and NATIVE=1 is set (on the command line or in the environment). Run make check-native for the native path, or unset NATIVE)
endif
override RUN :=
override DOCKER_READY :=
override FRONTEND := frontend="$$(scripts/native-tools.sh frontend)" && export SWIFT_FRONTEND="$$frontend" &&
else
override RUN := $(SWIFT_RUN)
override DOCKER_READY := docker-ready
override FRONTEND :=
endif

override FORMAT_PATHS := Package.swift Sources Tests scripts Apple

# The steps of a check, in order, for both paths. On the Docker path every step
# but guard needs docker-ready first, so make check runs guard, docker-ready,
# guard-deps, and on.
override CHECK_STEPS := guard guard-deps guard-imports guard-extension guard-literals metrics-check build test \
	format-check

.PHONY: check check-native native-tools docker-ready guard guard-deps guard-imports guard-extension guard-literals \
	metrics-check metrics build \
	test format-check format clean

# check: everything a ticket must pass. The three core guards, the extension
# guard, the literal guard, the token pin and the generated token files, build,
# tests, format check.
check: $(CHECK_STEPS)
	@echo "make check: OK"

# check-native: the same steps on the host, without Docker. It first checks
# that every tool they use is there, and fails, naming the tool, if one is not,
# and that the active Swift is the pinned SWIFT_VERSION.
# docker-ready and its stale containerd pid self-test are not part of it: they
# look after the Docker daemon on a Linux host, which this path does not use.
check-native: native-tools
	@$(MAKE) --no-print-directory NATIVE=1 $(CHECK_STEPS)
	@echo "make check-native: OK"

native-tools:
	@scripts/native-tools.sh check $(SWIFT_VERSION)

# docker-ready: start dockerd if needed and make sure the Swift image is present.
# The self-test of its stale containerd pid check runs first and needs no daemon.
docker-ready:
	@scripts/containerd-stale-pid-selftest.sh
	@scripts/docker-ready.sh $(SWIFT_TAG)

# guard: the core never imports FoundationNetworking and never uses URLSession.
# The self-test runs first, so a broken guard cannot pass silently.
guard:
	@scripts/core-guard-selftest.sh
	@scripts/core-guard.sh

# guard-deps: the SpeakboardCore target in Package.swift is a regular target,
# declares no dependencies and sets no path, sources, plugins or build settings,
# the package builds it as Swift 6, and the SpeakboardCore product holds only
# that target.
# Its self-test runs first, for the same reason.
guard-deps: $(DOCKER_READY)
	@$(RUN) bash -c 'scripts/core-deps-selftest.sh && scripts/core-deps-guard.sh'

# guard-imports: the core has no conditional compilation, and every Swift file
# in it imports Foundation and nothing else, as the compiler reads it. Its
# self-test runs first, for the same reason.
guard-imports: $(DOCKER_READY)
	@$(RUN) bash -c '$(FRONTEND) scripts/core-imports-selftest.sh && scripts/core-imports-guard.sh'

# guard-extension: the keyboard extension's folders (Apple/Keyboard and the
# Apple/KeyboardKit code linked into it) hold only Swift files, with no
# conditional compilation, importing only the modules the guard allows (as the
# compiler reads the imports, so it needs the frontend, like guard-imports),
# and naming no networking API (a text net, not a proof). See the guard's
# header for what it cannot see. macOS CI also checks project.yml's sources
# and the built extension's binaries. The self-test runs first.
guard-extension: $(DOCKER_READY)
	@$(RUN) bash -c '$(FRONTEND) scripts/extension-guard-selftest.sh && scripts/extension-guard.sh sources'

# guard-literals: the keyboard's view code (Apple/Keyboard, Apple/KeyboardKit)
# types no number used as a metric and makes no colour from literals, as the
# compiler parses it (so it needs the frontend, like guard-imports). See the
# guard's header for its allowances and what it cannot see. The self-test runs
# first.
guard-literals: $(DOCKER_READY)
	@$(RUN) bash -c '$(FRONTEND) scripts/literal-guard-selftest.sh && scripts/literal-guard.sh'

# metrics-check: the pinned token export matches DesignTokens/tokens.pin, and the
# committed generated files (the metrics tables and the drawing tokens) are
# exactly what the generator makes from it.
metrics-check: $(DOCKER_READY)
	@$(RUN) scripts/metrics.sh check

# metrics: regenerate the metrics tables and drawing tokens from the pinned token export.
metrics: $(DOCKER_READY)
	@$(RUN) scripts/metrics.sh write

build: $(DOCKER_READY)
	$(RUN) swift build

test: $(DOCKER_READY)
	$(RUN) swift test

format-check: $(DOCKER_READY)
	$(RUN) swift format lint --strict --recursive $(FORMAT_PATHS)
	@echo "format check: OK"

# format: rewrite the Swift files in place to match .swift-format.
format: $(DOCKER_READY)
	$(RUN) swift format format --in-place --recursive $(FORMAT_PATHS)

clean:
	rm -rf .build
