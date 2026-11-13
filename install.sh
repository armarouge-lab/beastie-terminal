#!/bin/sh
set -eu

BEASTIE_ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${BEASTIE_ROOT}/.build"
ST_VERSION="0.9.3"
ST_TARBALL="st-${ST_VERSION}.tar.gz"
ST_URL="https://dl.suckless.org/st/${ST_TARBALL}"
ST_SOURCE_DIR="${BUILD_DIR}/st-${ST_VERSION}"
BUILD_LOG="${BUILD_DIR}/build.log"

logInfo() { printf '[info] %s\n' "$1" >&2; }
logOk()   { printf '[ OK ] %s\n' "$1" >&2; }
logWarn() { printf '[warn] %s\n' "$1" >&2; }
logFail() { printf '[FAIL] %s at %s — %s\n' "$1" "$2" "$3" >&2; }

failAndExit() { logFail "$1" "$2" "$3"; exit 1; }

ensureExecutableBits() {
    detectPath="${BEASTIE_ROOT}/detect-os.sh"
    testPath="${BEASTIE_ROOT}/tests/detect-os.sh"
    for scriptPath in "$detectPath" "$testPath"; do
        if [ -f "$scriptPath" ]; then
            chmod 0755 "$scriptPath"
        fi
    done
    logOk "executable bits ensured on detect-os.sh and tests/detect-os.sh"
}

detectEnvironment() {
    detectorPath="${BEASTIE_ROOT}/detect-os.sh"
    [ -x "$detectorPath" ] \
        || failAndExit "detect-os.sh not executable" "$detectorPath" \
                        "run chmod 0755 on it"
    if ! detectorOutput=$("$detectorPath" --print); then
        failAndExit "detect-os.sh failed" "$detectorPath" \
                    "run it manually to see the error"
    fi
    eval "$detectorOutput"
    export OS PKG BUILD_TOOL X11_PREFIX TERMINFO_DIR
    logOk "detected OS=${OS} PKG=${PKG} BUILD_TOOL=${BUILD_TOOL}"
}

installDependencies() {
    case "$PKG" in
        apt)
            logInfo "installing dependencies via apt"
            if ! apt update; then
                logWarn "apt update reported errors (often a broken third-party repository); continuing to install"
            fi
            DEBIAN_FRONTEND=noninteractive apt install -y \
                build-essential \
                libx11-dev \
                libxft-dev \
                libfontconfig1-dev \
                libfreetype6-dev \
                pkg-config \
                || failAndExit "apt install failed" "apt" \
                                "check network connectivity and mirror availability"
            ;;
        dnf)
            logInfo "installing dependencies via dnf"
            dnf install -y \
                gcc make \
                libX11-devel libXft-devel \
                fontconfig-devel freetype-devel \
                pkgconf-pkg-config \
                || failAndExit "dnf install failed" "dnf" \
                                "check network and repository availability"
            ;;
        pacman)
            logInfo "installing dependencies via pacman"
            pacman -Syu --noconfirm \
                base-devel libx11 libxft \
                fontconfig freetype2 pkgconf \
                || failAndExit "pacman install failed" "pacman" \
                                "check network and mirror availability"
            ;;
        pkg)
            logInfo "installing dependencies via pkg"
            pkg install -y \
                gcc gmake libX11 libXft \
                fontconfig freetype2 pkgconf \
                || failAndExit "pkg install failed" "pkg" \
                                "check network and repository availability"
            ;;
        *)
            failAndExit "unsupported package manager" "$PKG" \
                        "extend install.sh with a case branch for this PKG"
            ;;
    esac
    logOk "dependencies installed via ${PKG}"
}

downloadSource() {
    mkdir -p "$BUILD_DIR"
    tarballPath="${BUILD_DIR}/${ST_TARBALL}"
    if [ -f "$tarballPath" ]; then
        logInfo "tarball already cached at ${tarballPath}"
    else
        logInfo "downloading ${ST_URL}"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tarballPath" "$ST_URL" \
                || failAndExit "download failed" "$ST_URL" \
                                "check network connectivity"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$tarballPath" "$ST_URL" \
                || failAndExit "download failed" "$ST_URL" \
                                "check network connectivity"
        else
            failAndExit "neither curl nor wget available" "PATH=$PATH" \
                        "install curl or wget"
        fi
    fi
    rm -rf "$ST_SOURCE_DIR"
    tar -xzf "$tarballPath" -C "$BUILD_DIR" \
        || failAndExit "extraction failed" "$tarballPath" \
                        "delete the tarball and rerun install.sh"
    [ -d "$ST_SOURCE_DIR" ] \
        || failAndExit "extracted directory missing" "$ST_SOURCE_DIR" \
                        "upstream tarball layout changed"
    logOk "source extracted to ${ST_SOURCE_DIR}"
}

patchConfigMk() {
    configMkPath="${ST_SOURCE_DIR}/config.mk"
    [ -f "$configMkPath" ] \
        || failAndExit "config.mk missing" "$configMkPath" \
                        "upstream tarball layout changed"
    case "$OS" in
        Linux)
            logInfo "config.mk: Linux uses upstream defaults (no patch needed)"
            ;;
        FreeBSD)
            logInfo "config.mk: applying FreeBSD paths and removing -lrt"
            sed -i.bak \
                -e 's|^X11INC = .*|X11INC = /usr/local/include|' \
                -e 's|^X11LIB = .*|X11LIB = /usr/local/lib|' \
                "$configMkPath"
            sed -i.bak 's| -lrt||g' "$configMkPath"
            ;;
        *)
            failAndExit "unknown OS in config.mk patch" "$OS" \
                        "detect-os.sh should have caught this"
            ;;
    esac
    logOk "config.mk prepared for ${OS}"
}

buildSource() {
    logInfo "building st ${ST_VERSION} with ${BUILD_TOOL}"
    (
        cd "$ST_SOURCE_DIR" || exit 1
        "$BUILD_TOOL" clean >/dev/null 2>&1 || true
        if ! "$BUILD_TOOL" > "$BUILD_LOG" 2>&1; then
            failAndExit "build failed" "$ST_SOURCE_DIR" \
                        "see ${BUILD_LOG} for the compiler error"
        fi
    )
    stBinaryPath="${ST_SOURCE_DIR}/st"
    [ -x "$stBinaryPath" ] \
        || failAndExit "st binary missing after build" "$stBinaryPath" \
                        "see ${BUILD_LOG}"
    warningCount=0
    if grep -qi 'warning:' "$BUILD_LOG"; then
        warningCount=$(grep -ci 'warning:' "$BUILD_LOG" || printf '0')
    fi
    if [ "$warningCount" -gt 0 ]; then
        logWarn "${warningCount} warning(s) in build log (upstream st, not our code)"
    else
        logOk "build clean (0 warnings)"
    fi
    logOk "st ${ST_VERSION} built at ${stBinaryPath}"
}

reportNextSteps() {
    stBinaryPath="${ST_SOURCE_DIR}/st"
    logInfo "next step 1: open an X11 session and run ${stBinaryPath} -e sh -c 'echo TERM=\$TERM; read x'"
    logInfo "next step 2: confirm output shows TERM=st-256color, then press Enter to close"
    logInfo "next step 3: run ${BEASTIE_ROOT}/tests/detect-os.sh to confirm the regression suite is still green"
}

main() {
    ensureExecutableBits
    detectEnvironment
    installDependencies
    downloadSource
    patchConfigMk
    buildSource
    reportNextSteps
    logOk "install.sh finished successfully"
}

main "$@"