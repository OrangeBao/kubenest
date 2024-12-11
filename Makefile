GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
VERSION ?= '$(shell hack/version.sh)'

# Images management
REGISTRY?="ghcr.io/kosmos-io"
REGISTRY_USER_NAME?=""
REGISTRY_PASSWORD?=""
REGISTRY_SERVER_ADDRESS?=""
KIND_IMAGE_TAG?="v1.25.3"

MACOS_TARGETS := node-agent

TARGETS := node-agent


# If GOOS is macOS, assign the value of MACOS_TARGETS to TARGETS
ifeq ($(GOOS), darwin)
	TARGETS := $(MACOS_TARGETS)
endif

#CTL_TARGETS := nestctl

# Build code.
#
# Args:
#   GOOS:   OS to build.
#   GOARCH: Arch to build.
#
# Example:
#   make
#   make all
#   make node-agent
#   make node-agent GOOS=linux
CMD_TARGET=$(TARGETS) $(CTL_TARGETS)

.PHONY: all
all: $(CMD_TARGET)

.PHONY: $(CMD_TARGET)
$(CMD_TARGET):
	BUILD_PLATFORMS=$(GOOS)/$(GOARCH) hack/build.sh $@

# Build image.
#
# Args:
#   GOARCH:      Arch to build.
#   OUTPUT_TYPE: Destination to save image(docker/registry).
#
# Example:
#   make images
#   make image-kubenest-operator
#   make image-kubenest-operator GOARCH=arm64
IMAGE_TARGET=$(addprefix image-, $(TARGETS))
.PHONY: $(IMAGE_TARGET)
$(IMAGE_TARGET):
	set -e;\
	target=$$(echo $(subst image-,,$@));\
	make $$target GOOS=linux;\
	VERSION=$(VERSION) REGISTRY=$(REGISTRY) BUILD_PLATFORMS=linux/$(GOARCH) hack/docker.sh $$target

images: $(IMAGE_TARGET)

# Build and push multi-platform image to DockerHub
#
# Example
#   make multi-platform-images
#   make mp-image-kubenest-operator
MP_TARGET=$(addprefix mp-image-, $(TARGETS))
.PHONY: $(MP_TARGET)
$(MP_TARGET):
	set -e;\
	target=$$(echo $(subst mp-image-,,$@));\
	make $$target GOOS=linux GOARCH=amd64;\
	make $$target GOOS=linux GOARCH=arm64;\
	VERSION=$(VERSION) REGISTRY=$(REGISTRY) \
		OUTPUT_TYPE=registry \
		BUILD_PLATFORMS=linux/amd64,linux/arm64 \
		hack/docker.sh $$target

multi-platform-images: $(MP_TARGET)

.PHONY: clean
clean:
	hack/clean.sh

.PHONY: update
update:
	hack/update-all.sh

# verify-all.sh for verify crds vendor codegen
.PHONY: verify
verify:
	hack/verify-all.sh

.PHONY: test
test:
	mkdir -p ./_output/coverage/
	go test -tags=test --race --v ./pkg/... -coverprofile=./_output/coverage/coverage_pkg.txt -covermode=atomic
	go test -tags=test --race --v ./cmd/... -coverprofile=./_output/coverage/coverage_cmd.txt -covermode=atomic

upload-images: images
	@echo "push images to $(REGISTRY)"
	docker push ${REGISTRY}/node-agent:${VERSION}
	docker push ${REGISTRY}/kubenest-operator:${VERSION}

.PHONY: release
release:
	@make release-nodectl GOOS=linux GOARCH=amd64
	@make release-nodectl GOOS=linux GOARCH=arm64
	@make release-nodectl GOOS=darwin GOARCH=amd64
	@make release-nodectl GOOS=darwin GOARCH=arm64

release-nodecli:
	hack/release.sh nodectl ${GOOS} ${GOARCH} ${VERSION}

.PHONY: lint
lint: golangci-lint
	$(GOLANGLINT_BIN) run

.PHONY: lint-fix
lint-fix: golangci-lint
	$(GOLANGLINT_BIN) run --fix

golangci-lint:
ifeq (, $(shell which golangci-lint))
	GO111MODULE=on go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
GOLANGLINT_BIN=$(shell go env GOPATH)/bin/golangci-lint
else
GOLANGLINT_BIN=$(shell which golangci-lint)
endif
