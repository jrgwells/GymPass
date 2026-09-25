# GymPass developer tasks.
#
# A full Xcode installation is not required; the project builds with
# CommandLineTools. An .app bundle is assembled by scripts/build-app.sh.

.PHONY: build test app run-agent run-demo run-app clean icon

build:
	swift build

test:
	swift run GymPassTests

app:
	./scripts/build-app.sh

icon:
	swift scripts/build-icon.swift build/AppIcon.iconset

run-agent:
	swift run GymPassAgent --agent

run-demo:
	swift run GymPassAgent --demo

run-app:
	swift run GymPassApp

clean:
	swift package clean
	rm -rf dist build
