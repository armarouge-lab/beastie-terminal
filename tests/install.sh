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
testAssertContains "install.sh downloads st from suckless.org" \
    'dl.suckless.org/st' "$installContents"
testAssertContains "install.sh tolerates apt update partial failure" \
    'apt update reported errors' "$installContents"
testAssertContains "install.sh installs picom for transparency" \
    'picom' "$installContents"
testAssertContains "install.sh installs libxrender-dev for alpha" \
    'libxrender-dev' "$installContents"
testAssertContains "install.sh installs xrdb dependency" \
    'x11-xserver-utils' "$installContents"
testAssertContains "install.sh installs ncurses for tic" \
    'ncurses-bin' "$installContents"
testAssertNotContains "install.sh no longer installs tmux (tabs feature removed)" \
    'tmux' "$installContents"
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
testAssertContains "install.sh guards on HISTSIZE 5000 in st.c" \
    'grep -q '"'"'^#define HISTSIZE[[:space:]][[:space:]]*5000'"'"' "${ST_SOURCE_DIR}/st.c"' \
    "$installContents"
testAssertContains "install.sh defines applyAlphaPatch" \
    'applyAlphaPatch()' "$installContents"
testAssertContains "install.sh invokes applyAlphaPatch before applyXresourcesPatch" \
    'applyAlphaPatch
    applyXresourcesPatch' "$installContents"
testAssertContains "install.sh downloads alpha patch" \
    'st-alpha-20220206-0.8.5.diff' "$installContents"
testAssertContains "install.sh seds alpha to 0.95 in config.def.h without static" \
    's/^float alpha = [0-9][0-9]*\.[0-9][0-9]*;/float alpha = 0.95;/' \
    "$installContents"
testAssertContains "install.sh has alpha fallback for rejected xinit hunk" \
    'alpha patch hunk for xinit() was rejected' "$installContents"
testAssertContains "install.sh defines applyXresourcesPatch" \
    'applyXresourcesPatch()' "$installContents"
testAssertContains "install.sh invokes applyXresourcesPatch before applySpawnFunction" \
    'applyXresourcesPatch
    applySpawnFunction' "$installContents"
testAssertContains "install.sh downloads xresources patch" \
    'st-xresources-20200604-9ba7ecf.diff' "$installContents"
testAssertContains "install.sh fails cleanly on xresources rejection" \
    'xresources patch rejected one or more hunks' "$installContents"
testAssertContains "install.sh saves xresources rejects to dedicated dir" \
    'xresources-rej' "$installContents"
testAssertContains "install.sh guards on resources[] in config.def.h" \
    'grep -q '"'"'resources\[\]'"'"' "${ST_SOURCE_DIR}/config.def.h"' \
    "$installContents"
testAssertContains "install.sh guards on Xrm API in x.c" \
    'grep -q '"'"'XrmGetStringDatabase\|XResourceManagerString\|XrmInitialize'"'"' "${ST_SOURCE_DIR}/x.c"' \
    "$installContents"
testAssertContains "install.sh guards on xresources background mapping to colorname[256]" \
    'grep -q '"'"'{ "background",.*colorname\[256\]'"'"' "${ST_SOURCE_DIR}/config.def.h"' \
    "$installContents"
testAssertContains "install.sh defines applySpawnFunction" \
    'applySpawnFunction()' "$installContents"
testAssertContains "install.sh invokes applySpawnFunction before applyWindowTitle" \
    'applySpawnFunction
    applyWindowTitle' "$installContents"
testAssertContains "install.sh anchors spawn injection on ttynew" \
    'ttynew anchor not found in st.c' "$installContents"
testAssertContains "install.sh uses lookahead line-array for spawn injection" \
    'lines[i+1] ~ /^ttynew\(/' "$installContents"
testAssertContains "install.sh re-prints original prefix after spawn injection" \
    'print lines[i]' "$installContents"
testAssertContains "install.sh injects setsid before execvp in spawn" \
    'setsid();' "$installContents"
testAssertContains "install.sh guards on setsid in spawn" \
    'grep -q '"'"'setsid();'"'"' "${ST_SOURCE_DIR}/st.c"' \
    "$installContents"
testAssertContains "install.sh injects fork+execvp spawn function" \
    'execvp(((char \*\*)arg->v)\[0\]' "$installContents"
testAssertContains "install.sh guards on preserved prefix before ttynew" \
    'original ttynew return type' "$installContents"
testAssertContains "install.sh injects spawn prototype into st.h" \
    'spawn prototype injected into st.h' "$installContents"
testAssertContains "install.sh guards on Arg union anchor in st.h" \
    'Arg union anchor not found in st.h' "$installContents"
testAssertContains "install.sh guards on spawn prototype in st.h after injection" \
    'spawn prototype not present after injection' "$installContents"
testAssertContains "install.sh defines applyWindowTitle" \
    'applyWindowTitle()' "$installContents"
testAssertContains "install.sh invokes applyWindowTitle before applyConfigHeader" \
    'applyWindowTitle
    applyConfigHeader' "$installContents"
testAssertContains "install.sh attempts x.c ternary title substitution" \
    'opt_title ? opt_title : "Beastie"' "$installContents"
testAssertContains "install.sh attempts st.c opt_title default substitution" \
    's/opt_title = "st"/opt_title = "Beastie"/g' "$installContents"
testAssertContains "install.sh warns if title anchor not found" \
    'window title anchor not found' "$installContents"
testAssertNotContains "install.sh does not abort build on title anchor miss" \
    'failAndExit "default title anchor' "$installContents"
testAssertContains "install.sh defines installBinary" \
    'installBinary()' "$installContents"
testAssertContains "install.sh invokes installBinary before installTerminfo" \
    'installBinary
    installTerminfo' "$installContents"
testAssertContains "install.sh runs make install with PREFIX" \
    '"$BUILD_TOOL" install PREFIX="$ST_INSTALL_PREFIX"' "$installContents"
testAssertContains "install.sh guards on installed st binary" \
    'st not installed at expected path' "$installContents"
testAssertContains "install.sh defines installTerminfo" \
    'installTerminfo()' "$installContents"
testAssertContains "install.sh invokes installTerminfo before installWrapper" \
    'installTerminfo
    installWrapper' "$installContents"
testAssertContains "install.sh renames st-256color to beastie-256color in st.info" \
    "sed 's/^st-256color|/beastie-256color|/'" "$installContents"
testAssertContains "install.sh runs tic -x -o TERMINFO_DIR" \
    'tic -x -o "$TERMINFO_DIR"' "$installContents"
testAssertContains "install.sh guards on terminfo registration via infocmp" \
    'infocmp -A "$TERMINFO_DIR" beastie-256color' "$installContents"
testAssertContains "install.sh defines installWrapper" \
    'installWrapper()' "$installContents"
testAssertContains "install.sh invokes installWrapper before installXresources" \
    'installWrapper
    installXresources' "$installContents"
testAssertContains "install.sh writes wrapper with TERM=beastie-256color" \
    'export TERM=beastie-256color' "$installContents"
testAssertContains "install.sh writes wrapper with -t Beastie" \
    '-t "Beastie"' "$installContents"
testAssertContains "install.sh writes wrapper with -f Iosevka" \
    '-f "Iosevka Term:size=13"' "$installContents"
testAssertContains "install.sh writes wrapper with -g 100x30" \
    '-g 100x30' "$installContents"
testAssertContains "install.sh writes wrapper with --version handler" \
    '= "--version"' "$installContents"
testAssertContains "install.sh writes wrapper with --selftest handler" \
    '= "--selftest"' "$installContents"
testAssertContains "install.sh guards on wrapper --version output" \
    'wrapper --version returned unexpected output' "$installContents"
testAssertContains "install.sh defines installXresources" \
    'installXresources()' "$installContents"
testAssertContains "install.sh runs installXresources after installWrapper" \
    'installWrapper
    installXresources' "$installContents"
testAssertContains "install.sh ensures trailing newline in Xresources" \
    'tail -c 1 "$xresourcesFile"' "$installContents"
testAssertContains "install.sh removes previous st.* properties" \
    'grep -v '"'"'^st\.'"'"' "$xresourcesFile"' "$installContents"
testAssertContains "install.sh writes st.background property" \
    'st.background: #0a0a0a' "$installContents"
testAssertContains "install.sh writes st.foreground property" \
    'st.foreground: #e0e0e0' "$installContents"
testAssertContains "install.sh writes st.cursorColor property" \
    'st.cursorColor: #ff6600' "$installContents"
testAssertContains "install.sh writes st.font property" \
    'st.font: Iosevka Term:size=13' "$installContents"
testAssertContains "install.sh logs xrdb-loaded properties on failure" \
    'xrdb loaded: [${xrdbDebug}]' "$installContents"
testAssertContains "install.sh runs xrdb -merge" \
    'xrdb -merge "$xresourcesFile"' "$installContents"
testAssertContains "install.sh guards on xrdb query result" \
    'xrdb -query 2>/dev/null | grep -q '"'"'^st\.background:'"'"'' \
    "$installContents"
testAssertContains "install.sh documents restart-to-apply for Xresources" \
    'restart st to apply' "$installContents"
testAssertNotContains "install.sh no longer promises SIGUSR1 runtime reload" \
    'kill -USR1' "$installContents"
testAssertContains "install.sh defines applyConfigHeader" \
    'applyConfigHeader()' "$installContents"
testAssertContains "install.sh invokes applyConfigHeader before buildSource" \
    'applyConfigHeader
    buildSource' "$installContents"
testAssertContains "install.sh sed-replaces font with Iosevka Term" \
    'Iosevka Term:size=13:antialias=true:autohint=true' "$installContents"
testAssertContains "install.sh sed forces Ctrl+Shift+C" \
    '{ ControlMask|ShiftMask, XK_C, clipcopy,' "$installContents"
testAssertContains "install.sh sed forces Ctrl+Shift+V" \
    '{ ControlMask|ShiftMask, XK_V, clippaste,' "$installContents"
testAssertContains "install.sh awk-replaces colorname array" \
    'colorname' "$installContents"
testAssertContains "install.sh awk writes background first in extra[]" \
    'extra[0] = "#0a0a0a"; extra[1] = "#e0e0e0"; extra[2] = "#ff6600"; extra[3] = "#555555"' \
    "$installContents"
testAssertContains "install.sh forces defaultbg to 256" \
    's/^unsigned int defaultbg = [0-9][0-9]*;/unsigned int defaultbg = 256;/' \
    "$installContents"
testAssertContains "install.sh forces defaultfg to 257" \
    's/^unsigned int defaultfg = [0-9][0-9]*;/unsigned int defaultfg = 257;/' \
    "$installContents"
testAssertContains "install.sh forces defaultcs to 258" \
    's/^unsigned int defaultcs = [0-9][0-9]*;/unsigned int defaultcs = 258;/' \
    "$installContents"
testAssertContains "install.sh forces defaultrcs to 259" \
    's/^unsigned int defaultrcs = [0-9][0-9]*;/unsigned int defaultrcs = 259;/' \
    "$installContents"
testAssertContains "install.sh injects Ctrl+Shift+N spawn beastie" \
    'XK_N, spawn, {.v = (char \*\[\]){ "beastie", NULL } }' "$installContents"
testAssertNotContains "install.sh no longer injects Ctrl+Shift+T spawn tmux" \
    'XK_T, spawn, {.v = (char \*\[\]){ "tmux"' "$installContents"
testAssertContains "install.sh injects Ctrl+Shift+D spawn devil ." \
    'XK_D, spawn, {.v = (char \*\[\]){ "devil", ".", NULL } }' "$installContents"
testAssertContains "install.sh injects Ctrl+Shift+F spawn nid ." \
    'XK_F, spawn, {.v = (char \*\[\]){ "nid", ".", NULL } }' "$installContents"
testAssertContains "install.sh guards on Redhot cursor color" \
    'grep -q '"'"'"#ff6600"'"'"'' "$installContents"
testAssertContains "install.sh guards on resources[] after apply" \
    'grep -q '"'"'resources\[\]'"'"' "$targetConfig"' \
    "$installContents"
testAssertContains "install.sh guards on defaultbg 256 in config.h" \
    'grep -q '"'"'unsigned int defaultbg = 256;'"'"' "$targetConfig"' \
    "$installContents"
testAssertContains "install.sh guards on defaultfg 257 in config.h" \
    'grep -q '"'"'unsigned int defaultfg = 257;'"'"' "$targetConfig"' \
    "$installContents"
testAssertContains "install.sh guards on defaultcs 258 in config.h" \
    'grep -q '"'"'unsigned int defaultcs = 258;'"'"' "$targetConfig"' \
    "$installContents"
testAssertContains "install.sh guards on Ctrl+Shift+N spawn after apply" \
    'grep -q '"'"'XK_N, spawn, {.v = (char \*\[\]){ "beastie", NULL } }'"'"' "$targetConfig"' \
    "$installContents"
testAssertNotContains "install.sh no longer guards on Ctrl+Shift+T spawn after apply" \
    'grep -q '"'"'XK_T, spawn' "$installContents"
testAssertContains "install.sh keeps patch tool available" \
    'patch \' "$installContents"

if [ "$TEST_FAIL" -gt 0 ]; then
    printf '[FAIL] %s passed, %s failed\n' "$TEST_PASS" "$TEST_FAIL" >&2
    exit 1
fi
printf '[ OK ] %s assertions passed, 0 failed\n' "$TEST_PASS"