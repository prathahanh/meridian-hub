#!/bin/sh
# Both gates, before the executor ever sees the file.
#
# luau-analyze finds unknown globals, shadowing and dead code. It does NOT find
# "Out of local registers", which is the error this codebase hits most: Build is
# one function against Luau's 200 register limit.
#
# luau-compile does find it. That is worth knowing, because every previous
# encounter with that error cost a round trip through a live Roblox client.
set -e
for f in "$@"; do
	luau-analyze "$f" 2>&1 | grep -vE "Unknown global|Unknown type 'Instance'" | grep . && echo "analyze: problems in $f" && exit 1 || true
	luau-compile --binary "$f" > /dev/null || { echo "compile: FAILED $f"; luau-compile --binary "$f" 2>&1 | head -3; exit 1; }
	echo "ok $f"
done
