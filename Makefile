#
# QuickJS Javascript Engine
#
# Copyright (c) 2017-2024 Fabrice Bellard
# Copyright (c) 2017-2024 Charlie Gordon
# Copyright (c) 2023-2025 Ben Noordhuis
# Copyright (c) 2023-2025 Saúl Ibarra Corretgé
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

BUILD_DIR=build
BUILD_TYPE?=Release
INSTALL_PREFIX?=/usr/local

BUILD_BACKEND?=cmake

QJS=$(BUILD_DIR)/qjs
QJSC=$(BUILD_DIR)/qjsc
RUN262=$(BUILD_DIR)/run-test262

JOBS?=$(shell getconf _NPROCESSORS_ONLN)
ifeq ($(JOBS),)
JOBS := $(shell sysctl -n hw.ncpu)
endif
ifeq ($(JOBS),)
JOBS := $(shell nproc)
endif
ifeq ($(JOBS),)
JOBS := 4
endif

ifeq ($(BUILD_BACKEND),meson)
ifeq ($(BUILD_TYPE),Release)
BUILD_TYPE=release
endif
ifeq ($(BUILD_TYPE),Debug)
BUILD_TYPE=debug
endif
ifeq ($(BUILD_TYPE),RelWithDebInfo)
BUILD_TYPE=debugoptimized
endif
ifeq ($(BUILD_TYPE),MinSizeRel)
BUILD_TYPE=minsize
endif
endif

all: $(QJS)

fuzz:
	clang -g -O1 -fsanitize=address,undefined,fuzzer -o fuzz fuzz.c
	./fuzz

$(BUILD_DIR):
ifeq ($(BUILD_BACKEND),cmake)
	cmake -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=$(BUILD_TYPE) -DCMAKE_INSTALL_PREFIX=$(INSTALL_PREFIX)
else
ifeq ($(BUILD_BACKEND),meson)
	meson setup $(BUILD_DIR) --buildtype=$(BUILD_TYPE) --prefix=$(INSTALL_PREFIX)
else
	false
endif
endif

$(QJS): $(BUILD_DIR)
	test -f $(BUILD_DIR)/meson-private/coredata.dat || cmake --build $(BUILD_DIR) -j $(JOBS)
	test -f $(BUILD_DIR)/CMakeCache.txt || meson compile -C $(BUILD_DIR) -j $(JOBS)

$(QJSC): $(BUILD_DIR)
	test -f $(BUILD_DIR)/meson-private/coredata.dat || cmake --build $(BUILD_DIR) --target qjsc -j $(JOBS)
	test -f $(BUILD_DIR)/CMakeCache.txt || meson compile -C $(BUILD_DIR) -j $(JOBS) qjsc

install: $(QJS) $(QJSC)
	test -f $(BUILD_DIR)/meson-private/coredata.dat || cmake --build $(BUILD_DIR) --target install
	test -f $(BUILD_DIR)/CMakeCache.txt || meson install -C $(BUILD_DIR)

clean:
	test -f $(BUILD_DIR)/meson-private/coredata.dat || cmake --build $(BUILD_DIR) --target clean
	test -f $(BUILD_DIR)/CMakeCache.txt || meson compile -C $(BUILD_DIR) --clean

codegen: $(QJSC)
	$(QJSC) -ss -o gen/repl.c -m repl.js
	$(QJSC) -ss -o gen/standalone.c -m standalone.js
	$(QJSC) -e -o gen/function_source.c tests/function_source.js
	$(QJSC) -e -o gen/hello.c examples/hello.js
	$(QJSC) -e -o gen/hello_module.c -m examples/hello_module.js
	$(QJSC) -e -o gen/test_fib.c -M examples/fib.so,fib -m examples/test_fib.js

debug:
	BUILD_TYPE=Debug $(MAKE)

distclean:
	@rm -rf $(BUILD_DIR)

stats: $(QJS)
	$(QJS) -qd

# effectively .PHONY because it doesn't generate output
ctest: CFLAGS=-std=c11 -fsyntax-only -Wall -Wextra -Werror -pedantic
ctest: ctest.c quickjs.h
	$(CC) $(CFLAGS) -DJS_NAN_BOXING=0 $<
	$(CC) $(CFLAGS) -DJS_NAN_BOXING=1 $<

# effectively .PHONY because it doesn't generate output
cxxtest: CXXFLAGS=-std=c++11 -fsyntax-only -Wall -Wextra -Werror -pedantic
cxxtest: cxxtest.cc quickjs.h
	$(CXX) $(CXXFLAGS) -DJS_NAN_BOXING=0 $<
	$(CXX) $(CXXFLAGS) -DJS_NAN_BOXING=1 $<

test: $(QJS)
	$(RUN262) -c tests.conf

test262: $(QJS)
	$(RUN262) -m -c test262.conf -a

test262-fast: $(QJS)
	$(RUN262) -m -c test262.conf -c test262-fast.conf -a

test262-update: $(QJS)
	$(RUN262) -u -c test262.conf -a -t 1

test262-check: $(QJS)
	$(RUN262) -m -c test262.conf -E -a

microbench: $(QJS)
	$(QJS) tests/microbench.js

unicode_gen: $(BUILD_DIR)
	test -f $(BUILD_DIR)/meson-private/coredata.dat || cmake --build $(BUILD_DIR) --target unicode_gen -j $(JOBS) 
	test -f $(BUILD_DIR)/CMakeCache.txt || meson compile -C $(BUILD_DIR) -j $(JOBS) unicode_gen

libunicode-table.h: unicode_gen
	$(BUILD_DIR)/unicode_gen unicode $@

.PHONY: all ctest cxxtest debug fuzz install clean codegen distclean stats test test262 test262-update test262-check microbench unicode_gen $(QJS) $(QJSC)
