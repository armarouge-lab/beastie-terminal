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
testAssertContains "install.sh ensures executable bits" \
    'chmod 0755' "$installContents"
testAssertContains "install.sh uses BUILD_DIR for artifacts" \
    'BUILD_DIR=' "$installContents"
testAssertContains "install.sh runs clean before build" \
    '"$BUILD_TOOL" clean' "$installContents"
testAssertContains "install.sh downloads st from suckless.org" \
    'dl.suckless.org/st' "$installContents"
testAssertContains "install.sh tolerates apt update partial failure" \
    'apt update reported errors' "$installContents"
testAssertContains "install.sh installs picom for transparency" \
    'picom' "$installContents"
testAssertContains "install.sh installs libxrender-dev for alpha" \
    'libxrender-dev' "$installContents"
testAssertContains "install.sh defines installFonts" \
    'installFonts()' "$installContents"
testAssertContains "install.sh invokes installFonts before downloadSource" \
    'installFonts
    downloadSource' "$installContents"
testAssertContains "install.sh copies bundled TTF files" \
    'cp "$FONT_SOURCE_DIR"/*.ttf' "$installContents"
testAssertContains "install.sh runs fc-cache" \
    'fc-cache -f' "$installContents"
testAssertContains "install.sh verifies fontconfig sees Iosevka Term" \
    'grep -qi "$FONT_FAMILY"' "$installContents"
testAssertContains "install.sh defines applyScrollbackPatch" \
    'applyScrollbackPatch()' "$installContents"
testAssertContains "install.sh invokes applyScrollbackPatch before patchConfigMk" \
    'applyScrollbackPatch
    patchConfigMk' "$installContents"
testAssertContains "install.sh downloads scrollback patch 0.9.2" \
    'st-scrollback-0.9.2.diff' "$installContents"
testAssertContains "install.sh applies scrollback patch with patch -p1" \
    'patch -p1' "$installContents"
testAssertContains "install.sh seds HISTSIZE in st.c with flexible whitespace" \
    's/^#define[[:space:]][[:space:]]*HISTSIZE[[:space:]][[:space:]]*[0-9][0-9]*/#define HISTSIZE 5000/' \
    "$installContents"
testAssertContains "install.sh guards on HISTSIZE presence in st.c" \
    'grep -q '"'"'#define[[:space:]][[:space:]]*HISTSIZE'"'"' "${ST_SOURCE_DIR}/st.c"' \
    "$installContents"
testAssertContains "install.sh guards on HISTSIZE 5000 in st.c" \
    'grep -q '"'"'^#define HISTSIZE[[:space:]][[:space:]]*5000'"'"' "${ST_SOURCE_DIR}/st.c"' \
    "$installContents"
testAssertContains "install.sh defines applyAlphaPatch" \
    'applyAlphaPatch()' "$installContents"
testAssertContains "install.sh invokes applyAlphaPatch before applyConfigHeader" \
    'applyAlphaPatch
    applyConfigHeader' "$installContents"
testAssertContains "install.sh downloads alpha patch" \
    'st-alpha-20220206-0.8.5.diff' "$installContents"
testAssertContains "install.sh seds alpha to 0.95 in config.def.h without static" \
    's/^float alpha = [0-9][0-9]*\.[0-9][0-9]*;/float alpha = 0.95;/' \
    "$installContents"
testAssertContains "install.sh injects -lXrender into config.mk" \
    's/-lXft/-lXft -lXrender/' "$installContents"
testAssertContains "install.sh has fallback for rejected alpha hunk" \
    'alpha patch hunk for xinit() was rejected' "$installContents"
testAssertContains "install.sh fallback seds XDefaultDepth to xw.depth" \
    's/XDefaultDepth(xw\.dpy, xw\.scr)/xw.depth/g' "$installContents"
testAssertContains "install.sh fallback seds DefaultDepth to xw.depth" \
    's/DefaultDepth(xw\.dpy, xw\.scr)/xw.depth/g' "$installContents"
testAssertContains "install.sh guards on alpha in config.def.h after patch" \
    'grep -q '"'"'^float alpha = [0-9]'"'"' "${ST_SOURCE_DIR}/config.def.h"' \
    "$installContents"
testAssertContains "install.sh guards on alpha 0.95 in config.def.h" \
    'grep -q '"'"'^float alpha = 0.95;'"'"' "${ST_SOURCE_DIR}/config.def.h"' \
    "$installContents"
testAssertContains "install.sh guards on -lXrender in config.mk" \
    'grep -q -- '"'"'-lXrender'"'"' "${ST_SOURCE_DIR}/config.mk"' \
    "$installContents"
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
testAssertContains "install.sh guards on alpha 0.95 in config.h after apply" \
    'grep -q '"'"'^float alpha = 0.95;'"'"' "$targetConfig"' \
    "$installContents"
testAssertContains "install.sh keeps patch tool available" \
    'patch \' "$installContents"

if [ "$TEST_FAIL" -gt 0 ]; then
    printf '[FAIL] %s passed, %s failed\n' "$TEST_PASS" "$TEST_FAIL" >&2
    exit 1
fi
printf '[ OK ] %s assertions passed, 0 failed\n' "$TEST_PASS"