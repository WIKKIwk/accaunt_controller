FLUTTER ?= flutter
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
DEVICE ?= macos
else
DEVICE ?= linux
endif

.PHONY: run pub-get analyze test build-linux build-macos clean

run:
	$(FLUTTER) run -d $(DEVICE)

pub-get:
	$(FLUTTER) pub get

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

build-linux:
	$(FLUTTER) build linux

build-macos:
	$(FLUTTER) build macos

clean:
	$(FLUTTER) clean
