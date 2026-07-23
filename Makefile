# Convenience targets. CI and full-Xcode machines can just use `swift build`/`swift test`.
# On a Command-Line-Tools-only box, swift-testing ships as a framework off the default
# search path, so `test` adds it — but only when no full Xcode is selected.
CLT := /Library/Developer/CommandLineTools/Library/Developer
CLT_TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT)/Frameworks \
	-Xlinker -F -Xlinker $(CLT)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/usr/lib

.PHONY: build test run
build:
	swift build

test:
	@if xcode-select -p | grep -q CommandLineTools; then \
		swift test $(CLT_TEST_FLAGS); \
	else \
		swift test; \
	fi

run:
	swift run nabz
