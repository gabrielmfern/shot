#!/bin/sh
zig build -freference-trace=8 run -- "$@" --path ./test_tries
