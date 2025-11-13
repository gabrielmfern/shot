#!/bin/sh
zig build -freference-trace=8 run -- "$@" --debug --path ./test_tries
