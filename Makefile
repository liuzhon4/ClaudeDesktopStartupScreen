.PHONY: build check preview clean

build:
	./build.sh

check:
	./tools/verify.sh

preview:
	python3 -m http.server 8765 --bind 127.0.0.1

clean:
	rm -rf ClauEd.app
