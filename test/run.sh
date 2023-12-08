#!/usr/bin/env bash

set -e

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
cd "$ROOT"

# Clean previous builds and prepare the test environment.
rm -f "$ROOT/out/test-results.txt"
make clean
sed -i 's/RUN_TESTS = 0/RUN_TESTS = 1/g' $ROOT/test/defines.s

# Github Actions do not allow GUI programs to be run. This means that the code
# below will always fail (fceux won't be able to run). There is a way to emulate
# an X server with tools like xvfb-run or xvncserver, but so far I've had no
# luck on this front.
if [ -n "${GITHUB_ACTION}" ]; then
    exit 0
fi

# Run all the tests that we have on Lua.
for name in $(seq 2); do
    DEBUG=1 make out/$name.nes
    fceux --loadlua "$ROOT/test/$name.lua" "$ROOT/out/$name.nes"
done

# Show the results.
cat "$ROOT/out/test-results.txt"
n=$(cat "$ROOT/out/test-results.txt" | grep FAIL | wc -l)
echo ""
case $n in
    0)
        echo "All tests passed!"
        exit 0
        ;;
    1)
        echo "1 test failed!"
        exit 1
        ;;
    *)
        echo "$n tests failed!"
        exit 1
        ;;
esac
