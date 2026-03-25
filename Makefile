FLUTTER ?= flutter
DEVICE ?= linux

.PHONY: run pub-get analyze test build-linux clean

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

clean:
	$(FLUTTER) clean
