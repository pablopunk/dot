.PHONY: build build-all test test-verbose clean install uninstall help

# Variables
APP_NAME := dot
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_DIR := build
DIST_DIR := dist

# Go build flags
LDFLAGS := -ldflags "-X main.version=$(VERSION) -s -w"
GOFLAGS := -trimpath

# Default target
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build for current platform
	@echo "Building $(APP_NAME) v$(VERSION) for current platform..."
	@mkdir -p $(BUILD_DIR)
	go build $(GOFLAGS) $(LDFLAGS) -o $(BUILD_DIR)/$(APP_NAME) ./cmd/dot

build-all: ## Build for all supported platforms
	@echo "Building $(APP_NAME) v$(VERSION) for all platforms..."
	@mkdir -p $(DIST_DIR)
	
	# macOS amd64
	GOOS=darwin GOARCH=amd64 go build $(GOFLAGS) $(LDFLAGS) -o $(DIST_DIR)/$(APP_NAME)-darwin-amd64 ./cmd/dot
	
	# macOS arm64
	GOOS=darwin GOARCH=arm64 go build $(GOFLAGS) $(LDFLAGS) -o $(DIST_DIR)/$(APP_NAME)-darwin-arm64 ./cmd/dot
	
	# Linux amd64
	GOOS=linux GOARCH=amd64 go build $(GOFLAGS) $(LDFLAGS) -o $(DIST_DIR)/$(APP_NAME)-linux-amd64 ./cmd/dot
	
	# Linux arm64
	GOOS=linux GOARCH=arm64 go build $(GOFLAGS) $(LDFLAGS) -o $(DIST_DIR)/$(APP_NAME)-linux-arm64 ./cmd/dot
	
	# Linux arm
	GOOS=linux GOARCH=arm go build $(GOFLAGS) $(LDFLAGS) -o $(DIST_DIR)/$(APP_NAME)-linux-arm ./cmd/dot
	
	@echo "Built binaries:"
	@ls -la $(DIST_DIR)/

test: ## Run tests
	@echo "Running tests..."
	go test ./...

test-verbose: ## Run tests with verbose output
	@echo "Running tests with verbose output..."
	go test -v ./...

test-coverage: ## Run tests with coverage
	@echo "Running tests with coverage..."
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR) $(DIST_DIR) coverage.out coverage.html

install: build ## Install to ~/.local/bin
	@echo "Installing $(APP_NAME) to ~/.local/bin..."
	@mkdir -p ~/.local/bin
	cp $(BUILD_DIR)/$(APP_NAME) ~/.local/bin/$(APP_NAME)
	@echo "Installed $(APP_NAME) to ~/.local/bin/$(APP_NAME)"
	@echo "Make sure ~/.local/bin is in your PATH"

uninstall: ## Uninstall from ~/.local/bin
	@echo "Uninstalling $(APP_NAME) from ~/.local/bin..."
	rm -f ~/.local/bin/$(APP_NAME)
	@echo "Uninstalled $(APP_NAME)"

lint: ## Run linter
	@echo "Running linter..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "golangci-lint not found, running basic checks..."; \
		go vet ./...; \
		go fmt ./...; \
	fi

tidy: ## Tidy up go modules
	@echo "Tidying up go modules..."
	go mod tidy

deps: ## Download dependencies
	@echo "Downloading dependencies..."
	go mod download

# Development targets
dev-deps: ## Install development dependencies
	@echo "Installing development dependencies..."
	@if ! command -v golangci-lint >/dev/null 2>&1; then \
		echo "Installing golangci-lint..."; \
		go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest; \
	fi

run: build ## Build and run with example config
	@echo "Running $(APP_NAME)..."
	./$(BUILD_DIR)/$(APP_NAME) --help

# Release targets
release-check: ## Check if ready for release
	@echo "Checking if ready for release..."
	@if [ -z "$(shell git status --porcelain)" ]; then \
		echo "✓ Working directory is clean"; \
	else \
		echo "✗ Working directory has uncommitted changes"; \
		exit 1; \
	fi
	@echo "✓ Ready for release"

# Example/demo targets
example: ## Create example configuration
	@echo "Creating example dot.yaml..."
	@cat > dot.yaml << 'EOF'
profiles:
  "*":
    bash:
      link:
        "bash/.bashrc": "~/.bashrc"
        "bash/.bash_profile": "~/.bash_profile"
    git:
      link:
        "git/.gitconfig": "~/.gitconfig"
      install:
        brew: "brew install git"
        apt: "apt install -y git"

  work:
    ssh:
      link:
        "ssh/config": "~/.ssh/config"
    vpn:
      install:
        brew: "brew install --cask viscosity"
        apt: "apt install -y openvpn"
      os: ["mac", "linux"]

  laptop:
    battery:
      install:
        brew: "brew install --cask battery-guardian"
      os: ["mac"]
	EOF
	@echo "Created example dot.yaml"

demo: example build ## Create example config and run demo
	@echo "Running demo..."
	./$(BUILD_DIR)/$(APP_NAME) --profiles
	@echo ""
	@echo "Try: ./$(BUILD_DIR)/$(APP_NAME) --dry-run work"