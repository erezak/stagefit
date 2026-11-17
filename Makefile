.PHONY: build check test dist install run clean

build:
	./Scripts/build.sh

check:
	./Scripts/check.sh

test:
	./Scripts/test.sh

dist: build
	./Scripts/dist.sh

install: build
	@echo "Quit the installed StageFit first, then copying to /Applications."
	ditto build/StageFit.app /Applications/StageFit.app

run:
	open build/StageFit.app

clean:
	rm -rf build dist
