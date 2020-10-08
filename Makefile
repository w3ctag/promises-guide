specs = $(patsubst %.bs,build/%.html,$(wildcard *.bs))

.PHONY: all clean
.SUFFIXES: .bs .html

all: $(specs)

clean:
	rm -rf build *~

build:
	mkdir -p build

build/%.html: %.bs Makefile build
	bikeshed --die-on=warning spec $< $@

remote: index.bs Makefile build
	@ (HTTP_STATUS=$$(curl https://api.csswg.org/bikeshed/ \
	                       --output build/index.html \
	                       --write-out "%{http_code}" \
	                       --header "Accept: text/plain, text/html" \
	                       -F die-on=warning \
	                       -F file=@index.bs) && \
	test "$$HTTP_STATUS" -eq "200" ) || ( \
		echo ""; cat build/index.html; echo ""; \
		rm -f build/index.html; \
		exit 22 \
	);
