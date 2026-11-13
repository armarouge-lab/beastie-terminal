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

testAssertNotContains() {
    description=$1
    needle=$2
    haystack=$3
    case "$haystack" in
        *"$needle"*)
            TEST_FAIL=$((TEST_FAIL + 1))
            printf '[FAIL] %s: [%s] should NOT be present\n' "$description" "$needle" >&2
            ;;
        *)
            TEST_PASS=$((TEST_PASS + 1))
            printf '[ OK ] %s\n' "$description"
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
testAssertContains "install.sh ensures executable bits" \
    'chmod 0755' "$installContents"
testAssertContains "install.sh uses BUILD_DIR for artifacts" \
    'BUILD_DIR=' "$installContents"
testAssertContains "install.sh runs clean before build" \
    '"$BUILD_TOOL" clean' "$installContents"
testAssertContains "install.sh downloads from suckless.org" \
    'dl.suckless.org/st' "$installContents"
testAssertContains "install.sh tolerates apt update partial failure" \
    'apt update reported errors' "$installContents"
testAssertContains "install.sh defines installFonts" \
    'installFonts()' "$installContents"
testAssertContains "install.sh invokes installFonts before buildSource" \
    'installFonts
    downloadSource' "$installContents"
testAssertContains "install.sh copies bundled TTF files" \
    'cp "$FONT_SOURCE_DIR"/*.ttf' "$installContents"
testAssertContains "install.sh runs fc-cache" \
    'fc-cache -f' "$installContents"
testAssertContains "install.sh verifies fontconfig sees Iosevka Term" \
    'grep -qi "$FONT_FAMILY"' "$installContents"
testAssertContains "install.sh defines applyConfigHeader" \
    'applyConfigHeader()' "$installContents"
testAssertContains "install.sh invokes applyConfigHeader before buildSource" \
    'applyConfigHeader
    buildSource' "$installContents"
testAssertContains "install.sh sed-replaces font with Iosevka Term" \
    'Iosevka Term:size=13:antialias=true:autohint=true' "$installContents"
testAssertContains "install.sh sed has three # delimiters on Ctrl+Shift+C line" \
    's#{ TERMMOD, *XK_C, *clipcopy,#{ ControlMask|ShiftMask, XK_C, clipcopy,#' \
    "$installContents"
testAssertContains "install.sh sed has three # delimiters on Ctrl+Shift+V line" \
    's#{ TERMMOD, *XK_V, *clippaste,#{ ControlMask|ShiftMask, XK_V, clippaste,#' \
    "$installContents"
testAssertContains "install.sh sed forces Ctrl+Shift+C" \
    '{ ControlMask|ShiftMask, XK_C, clipcopy,' "$installContents"
testAssertContains "install.sh sed forces Ctrl+Shift+V" \
    '{ ControlMask|ShiftMask, XK_V, clippaste,' "$installContents"
testAssertContains "install.sh awk-replaces colorname array" \
    'colorname' "$installContents"
testAssertContains "install.sh guards on empty config.h after sed" \
    '[ -s "$targetConfig" ]' "$installContents"
testAssertContains "install.sh guards on Redhot cursor color" \
    'grep -q '"'"'"#ff6600"'"'"'' "$installContents"
testAssertContains "install.sh guards on Iosevka font after apply" \
    'grep -q '"'"'Iosevka Term:size=13:antialias=true:autohint=true'"'"'' "$installContents"
testAssertContains "install.sh guards on Ctrl+Shift+C after apply" \
    'grep -q '"'"'ControlMask|ShiftMask, XK_C, clipcopy'"'"'' "$installContents"
testAssertContains "install.sh guards on Ctrl+Shift+V after apply" \
    'grep -q '"'"'ControlMask|ShiftMask, XK_V, clippaste'"'"'' "$installContents"
testAssertContains "install.sh keeps patch tool available for future patches" \
    'patch \' "$installContents"

if [ "$TEST_FAIL" -gt 0 ]; then
    printf '[FAIL] %s passed, %s failed\n' "$TEST_PASS" "$TEST_FAIL" >&2
    exit 1
fi
printf '[ OK ] %s assertions passed, 0 failed\n' "$TEST_PASS"