#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d /tmp/beastie-test-XXXXXX)
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT INT TERM

INSTALL_PATH="${INSTALL_PATH:-./install.sh}"
if [ ! -f "$INSTALL_PATH" ]; then
    printf '[FAIL] install.sh missing at %s — run tests from the repo root\n' "$INSTALL_PATH" >&2
    exit 1
fi

TEST_PASS=0
TEST_FAIL=0

testAssertContains() {
    description=$1
    needle=$2
    haystack=$3
    case "$haystack" in
        *"$needle"*)
            TEST_PASS=$((TEST_PASS + 1))
            printf '[ OK ] %s\n' "$description"
            ;;
        *)
            TEST_FAIL=$((TEST_FAIL + 1))
            printf '[FAIL] %s: [%s] not found\n' "$description" "$needle" >&2
            ;;
    esac
}

if sh -n "$INSTALL_PATH" 2>"$TEST_ROOT/syntax.err"; then
    TEST_PASS=$((TEST_PASS + 1))
    printf '[ OK ] install.sh has valid POSIX shell syntax\n'
else
    TEST_FAIL=$((TEST_FAIL + 1))
    printf '[FAIL] install.sh has a syntax error:\n' >&2
    cat "$TEST_ROOT/syntax.err" >&2
fi

installContents=$(cat "$INSTALL_PATH")

testAssertContains "install.sh invokes detect-os.sh --print" \
    'detectorPath" --print' "$installContents"

testAssertContains "install.sh ensures executable bits (regression: bit-x bug)" \
    'chmod 0755' "$installContents"

testAssertContains "install.sh uses BUILD_DIR for artifacts" \
    'BUILD_DIR=' "$installContents"

testAssertContains "install.sh runs clean before build" \
    '"$BUILD_TOOL" clean' "$installContents"

testAssertContains "install.sh downloads from suckless.org" \
    'dl.suckless.org/st' "$installContents"

testAssertContains "install.sh tolerates apt update partial failure" \
    'apt update reported errors' "$installContents"

if [ "$TEST_FAIL" -gt 0 ]; then
    printf '[FAIL] %s passed, %s failed\n' "$TEST_PASS" "$TEST_FAIL" >&2
    exit 1
fi
printf '[ OK ] %s assertions passed, 0 failed\n' "$TEST_PASS"