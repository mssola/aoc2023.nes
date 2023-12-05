CC65   ?= cl65
CCOPTS ?= --target nes
QUIET  = @echo '   ' CC65 $@;

SOURCES = $(shell find src/ -type f -name '*.s' -printf "%f\n")
ROMS = $(SOURCES:%.s=out/%.nes)

.PHONY: all
all: clean deps build

.PHONY: clean
clean:
	@rm -rf out
	@mkdir out
	@find . -type f -name "*.o" -delete
	@find . -type f -name "*.nes" -delete

.PHONY: deps
deps:
	@which $(CC65) >/dev/null 2>/dev/null || (echo "ERROR: $(CC65) not found." && false)

.PHONY: build
build: $(ROMS)

out/%.nes: src/%.s
	$(QUIET) $(CC65) $(CCOPTS) $< -o $@
