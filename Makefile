CC65   ?= cl65
CCOPTS ?= --target nes
ifeq "$(DEBUG)" "1"
CCOPTS += -g -Ln out/labels.txt
endif
QUIET  = @echo '   ' CC65 $@;

SOURCES = $(shell find src/ -type f -name '*.s' -printf "%f\n")
ROMS = $(SOURCES:%.s=out/%.nes)

.PHONY: all
all: clean deps build

.PHONY: clean
clean:
	@sed -i 's/RUN_TESTS = 1/RUN_TESTS = 0/g' test/defines.s
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

.PHONY: test
test:
	@bash test/run.sh
