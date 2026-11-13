#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d /tmp/beastie-test-XXXXXX)
cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

SCRIPT_PATH="${SCRIPT_PATH:-./detect-os.sh}"
if [ ! -x "$SCRIPT_PATH" ]; then
    printf '[FAIL] script not executable at %s — run chmod 0755 on it\n' "$SCRIPT_PATH" >&2
    exit 1
fi

TEST_PASS=0
TEST_FAIL=0

testAssertEquals() {
    description=$1
    expected=$2
    actual=$3
    if [ "$expected" = "$actual" ]; then
        TEST_PASS=$((TEST_PASS + 1))
        printf '[ OK ] %s\n' "$description"
    else
        TEST_FAIL=$((TEST_FAIL + 1))
        printf '[FAIL] %s: expected=[%s] actual=[%s]\n' \
            "$description" "$expected" "$actual" >&2
    fi
}

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
            printf '[FAIL] %s: [%s] not found in [%s]\n' \
                "$description" "$needle" "$haystack" >&2
            ;;
    esac
}

createFixture() {
    fixtureDirectory=$1
    shift
    mkdir -p "$fixtureDirectory"
    for item in "$@"; do
        case "$item" in
            uname:*)
                operatingSystemName=${item#uname:}
                cat > "$fixtureDirectory/uname" <<EOF
#!/bin/sh
printf '%s\n' '$operatingSystemName'
EOF
                chmod 0755 "$fixtureDirectory/uname"
                ;;
            stub:*)
                packageManagerName=${item#stub:}
                cat > "$fixtureDirectory/$packageManagerName" <<'STUB'
#!/bin/sh
exit 0
STUB
                chmod 0755 "$fixtureDirectory/$packageManagerName"
                ;;
        esac
    done
}

printKeyValue() {
    key=$1
    printf '%s\n' "$2" | sed -n "s/^${key}=//p"
}

runDetectWithFixture() {
    fixtureDirectory=$1
    shift
    HOME=/test-home PATH="$fixtureDirectory" "$SCRIPT_PATH" "$@"
}

captureOutput() {
    captureStdoutFile=$1
    captureStderrFile=$2
    shift 2
    capturedStatus=0
    "$@" >"$captureStdoutFile" 2>"$captureStderrFile" || capturedStatus=$?
    printf '%s' "$capturedStatus"
}

linuxDebianFixture="$TEST_ROOT/linux-debian"
createFixture "$linuxDebianFixture" "uname:Linux" "stub:apt"
output=$(runDetectWithFixture "$linuxDebianFixture" --print)
testAssertEquals "linux-debian OS"           "Linux"                 "$(printKeyValue OS "$output")"
testAssertEquals "linux-debian PKG"          "apt"                   "$(printKeyValue PKG "$output")"
testAssertEquals "linux-debian BUILD_TOOL"   "make"                  "$(printKeyValue BUILD_TOOL "$output")"
testAssertEquals "linux-debian X11_PREFIX"   "/usr"                  "$(printKeyValue X11_PREFIX "$output")"
testAssertEquals "linux-debian TERMINFO_DIR" "/test-home/.terminfo"  "$(printKeyValue TERMINFO_DIR "$output")"

linuxFedoraFixture="$TEST_ROOT/linux-fedora"
createFixture "$linuxFedoraFixture" "uname:Linux" "stub:dnf"
output=$(runDetectWithFixture "$linuxFedoraFixture" --print)
testAssertEquals "linux-fedora PKG"        "dnf"  "$(printKeyValue PKG "$output")"
testAssertEquals "linux-fedora BUILD_TOOL" "make" "$(printKeyValue BUILD_TOOL "$output")"

linuxArchFixture="$TEST_ROOT/linux-arch"
createFixture "$linuxArchFixture" "uname:Linux" "stub:pacman"
output=$(runDetectWithFixture "$linuxArchFixture" --print)
testAssertEquals "linux-arch PKG" "pacman" "$(printKeyValue PKG "$output")"

freebsdFixture="$TEST_ROOT/freebsd"
createFixture "$freebsdFixture" "uname:FreeBSD" "stub:pkg"
output=$(runDetectWithFixture "$freebsdFixture" --print)
testAssertEquals "freebsd OS"           "FreeBSD"                  "$(printKeyValue OS "$output")"
testAssertEquals "freebsd PKG"          "pkg"                      "$(printKeyValue PKG "$output")"
testAssertEquals "freebsd BUILD_TOOL"   "gmake"                    "$(printKeyValue BUILD_TOOL "$output")"
testAssertEquals "freebsd X11_PREFIX"   "/usr/local"               "$(printKeyValue X11_PREFIX "$output")"
testAssertEquals "freebsd TERMINFO_DIR" "/usr/local/share/misc"    "$(printKeyValue TERMINFO_DIR "$output")"

stdoutFile="$TEST_ROOT/stdout.txt"
stderrFile="$TEST_ROOT/stderr.txt"

unknownOsFixture="$TEST_ROOT/unknown-os"
createFixture "$unknownOsFixture" "uname:Haiku"
actualStatus=$(captureOutput "$stdoutFile" "$stderrFile" \
    runDetectWithFixture "$unknownOsFixture" --print)
testAssertEquals "unknown-os exit code"           "1" "$actualStatus"
testAssertEquals "unknown-os stdout empty"        ""  "$(cat "$stdoutFile")"
testAssertContains "unknown-os stderr has FAIL"   "[FAIL]" "$(cat "$stderrFile")"
testAssertContains "unknown-os stderr mentions OS" "Haiku" "$(cat "$stderrFile")"

noPackageManagerFixture="$TEST_ROOT/no-pm"
createFixture "$noPackageManagerFixture" "uname:Linux"
actualStatus=$(captureOutput "$stdoutFile" "$stderrFile" \
    runDetectWithFixture "$noPackageManagerFixture" --print)
testAssertEquals "no-pm exit code"                  "1" "$actualStatus"
testAssertContains "no-pm stderr has FAIL"          "[FAIL]"        "$(cat "$stderrFile")"
testAssertContains "no-pm stderr mentions install"  "install apt"   "$(cat "$stderrFile")"

actualStatus=$(captureOutput "$stdoutFile" "$stderrFile" \
    runDetectWithFixture "$linuxDebianFixture" --help)
testAssertEquals "--help exit code" "0" "$actualStatus"

actualStatus=$(captureOutput "$stdoutFile" "$stderrFile" \
    runDetectWithFixture "$linuxDebianFixture" --bogus)
testAssertEquals "--bogus exit code"        "1"       "$actualStatus"
testAssertContains "--bogus stderr has FAIL" "[FAIL]"  "$(cat "$stderrFile")"

actualStatus=$(captureOutput "$stdoutFile" "$stderrFile" \
    runDetectWithFixture "$linuxDebianFixture")
testAssertEquals "no-argument exit code" "2" "$actualStatus"

if [ "$TEST_FAIL" -gt 0 ]; then
    printf '[FAIL] %s passed, %s failed\n' "$TEST_PASS" "$TEST_FAIL" >&2
    exit 1
fi
printf '[ OK ] %s assertions passed, 0 failed\n' "$TEST_PASS"