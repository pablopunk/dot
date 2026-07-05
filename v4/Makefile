.PHONY: test build build-all clean install

BUN ?= bun
SRC ?= src/index.ts
OUT ?= dist/dot
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")

test:
	$(BUN) test

build:
	$(BUN) build --compile --define 'process.env.DOT_VERSION="$(VERSION)"' $(SRC) --outfile $(OUT)

build-all:
	$(BUN) build --compile --define 'process.env.DOT_VERSION="$(VERSION)"' --target=bun-linux-x64     $(SRC) --outfile dist/dot-linux-x64
	$(BUN) build --compile --define 'process.env.DOT_VERSION="$(VERSION)"' --target=bun-linux-arm64   $(SRC) --outfile dist/dot-linux-arm64
	$(BUN) build --compile --define 'process.env.DOT_VERSION="$(VERSION)"' --target=bun-darwin-x64    $(SRC) --outfile dist/dot-darwin-x64
	$(BUN) build --compile --define 'process.env.DOT_VERSION="$(VERSION)"' --target=bun-darwin-arm64  $(SRC) --outfile dist/dot-darwin-arm64
	$(BUN) build --compile --define 'process.env.DOT_VERSION="$(VERSION)"' --target=bun-windows-x64   $(SRC) --outfile dist/dot-windows-x64.exe

clean:
	rm -rf dist

install: build
	sudo cp $(OUT) /usr/local/bin/dot
	cp $(OUT) $(HOME)/.local/bin/dot 2>/dev/null || true
