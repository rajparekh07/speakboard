# Rung 1 checks for the pure-Swift core. Swift runs only inside Docker, so the
# host needs Docker, bash, grep and make. See CONTRIBUTING.md.

# The Swift image, pinned to an exact Swift version and Ubuntu release.
SWIFT_TAG := 6.4.2-resolute
SWIFT_IMAGE := swift:$(SWIFT_TAG)

# Runs a command in the Swift image with the repo mounted at /work, as the
# calling user, so files in .build are not owned by root.
SWIFT_RUN := docker run --rm -v "$(CURDIR)":/work -w /work \
	--user "$$(id -u):$$(id -g)" -e HOME=/tmp $(SWIFT_IMAGE)

FORMAT_PATHS := Package.swift Sources Tests scripts

.PHONY: check docker-ready guard guard-deps build test format-check format clean

# check: everything a ticket must pass. The two core guards, build, tests,
# format check.
check: guard docker-ready guard-deps build test format-check
	@echo "make check: OK"

# docker-ready: start dockerd if needed and make sure the Swift image is present.
docker-ready:
	@scripts/docker-ready.sh $(SWIFT_TAG)

# guard: the core never imports FoundationNetworking and never uses URLSession.
# The self-test runs first, so a broken guard cannot pass silently.
guard:
	@scripts/core-guard-selftest.sh
	@scripts/core-guard.sh

# guard-deps: the SpeakboardCore target in Package.swift declares no dependencies
# and sets no path, sources, plugins or unsafe flags.
# Its self-test runs first, for the same reason.
guard-deps: docker-ready
	@$(SWIFT_RUN) bash -c 'scripts/core-deps-selftest.sh && scripts/core-deps-guard.sh'

build: docker-ready
	$(SWIFT_RUN) swift build

test: docker-ready
	$(SWIFT_RUN) swift test

format-check: docker-ready
	$(SWIFT_RUN) swift format lint --strict --recursive $(FORMAT_PATHS)
	@echo "format check: OK"

# format: rewrite the Swift files in place to match .swift-format.
format: docker-ready
	$(SWIFT_RUN) swift format format --in-place --recursive $(FORMAT_PATHS)

clean:
	rm -rf .build
