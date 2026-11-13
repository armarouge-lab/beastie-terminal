#!/bin/sh
set -eu

BEASTIE_ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${BEASTIE_ROOT}/.build"
ST_VERSION="0.9.3"
ST_TARBALL="st-${ST_VERSION}.tar.gz"
ST_URL="https://dl.suckless.org/st/${ST_TARBALL}"
CLIPBOARD_PATCH_URL="https://st.suckless.org/patches/clipboard/st-clipboard-0.8.3.diff"
CLIPBOARD_PATCH_FILE="${BUILD_DIR}/st-one-clipboard.diff"
ST_SOURCE_DIR="${BUILD_DIR}/st-${ST_VERSION}"
BUILD_LOG="${BUILD_DIR}/build.log"

logInfo() { printf '[info] %s\n' "$1" >&2; }
logOk()   { printf '[ OK ] %s\n' "$1" >&2; }
logWarn() { printf '[warn] %s\n' "$1" >&2; }
logFail() { printf '[FAIL] %s at %s — %s\n' "$1" "$2" "$3" >&2; }

failAndExit() { logFail "$1" "$2" "$3"; exit 1; }

ensureExecutableBits() {
    detectPath="${BEASTIE_ROOT}/detect-os.sh"
    detectTestPath="${BEASTIE_ROOT}/tests/detect-os.sh"
    installTestPath="${BEASTIE_ROOT}/tests/install.sh"
    for scriptPath in "$detectPath" "$detectTestPath" "$installTestPath"; do
        if [ -f "$scriptPath" ]; then
            chmod 0755 "$scriptPath"
        fi
    done
    logOk "executable bits ensured on shell scripts"
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
                patch \
                || failAndExit "apt install failed" "apt" \
                                "check network connectivity and mirror availability"
            ;;
        dnf)
            logInfo "installing dependencies via dnf"
            dnf install -y \
                gcc make patch \
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
                fontconfig freetype2 pkgconf patch \
                || failAndExit "pacman install failed" "pacman" \
                                "check network and mirror availability"
            ;;
        pkg)
            logInfo "installing dependencies via pkg"
            pkg install -y \
                gcc gmake libX11 libXft \
                fontconfig freetype2 pkgconf patch \
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

applyOneClipboardPatch() {
    if grep -q 'XSetSelectionOwner(xw.dpy, clipboard' "${ST_SOURCE_DIR}/x.c" 2>/dev/null; then
        logInfo "one clipboard support already present; skipping patch"
        return 0
    fi
    logInfo "downloading one clipboard patch from ${CLIPBOARD_PATCH_URL}"
    if [ -f "$CLIPBOARD_PATCH_FILE" ]; then
        logInfo "patch already cached at ${CLIPBOARD_PATCH_FILE}"
    else
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$CLIPBOARD_PATCH_FILE" "$CLIPBOARD_PATCH_URL" \
                || failAndExit "one clipboard patch download failed" "$CLIPBOARD_PATCH_URL" \
                                "check network connectivity"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$CLIPBOARD_PATCH_FILE" "$CLIPBOARD_PATCH_URL" \
                || failAndExit "one clipboard patch download failed" "$CLIPBOARD_PATCH_URL" \
                                "check network connectivity"
        else
            failAndExit "neither curl nor wget available" "PATH=$PATH" \
                        "install curl or wget"
        fi
    fi
    (
        cd "$ST_SOURCE_DIR" || exit 1
        patch -p1 --forward < "$CLIPBOARD_PATCH_FILE" \
            || failAndExit "one clipboard patch application failed" "$ST_SOURCE_DIR" \
                            "patch may not match st 0.9.3; check ${CLIPBOARD_PATCH_FILE}"
    )
    logOk "one clipboard patch applied (st now sets CLIPBOARD on selection)"
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

applyConfigHeader() {
    stockConfig="${ST_SOURCE_DIR}/config.def.h"
    targetConfig="${ST_SOURCE_DIR}/config.h"
    [ -f "$stockConfig" ] \
        || failAndExit "stock config.def.h missing" "$stockConfig" \
                        "upstream tarball layout changed"

    sed -e 's#^static char \*font = ".*";#static char *font = "monospace:pixelsize=13:antialias=true:autohint=true";#' \
        -e 's#{ TERMMOD, *XK_C, *clipcopy,#{ ControlMask|ShiftMask, XK_C, clipcopy,#' \
        -e 's#{ TERMMOD, *XK_V, *clippaste,#{ ControlMask|ShiftMask, XK_V, clippaste,#' \
        "$stockConfig" > "$targetConfig" \
        || failAndExit "sed config generation failed" "$targetConfig" \
                        "stock config.def.h layout changed"
    [ -s "$targetConfig" ] \
        || failAndExit "config.h is empty after sed" "$targetConfig" \
                        "one of the sed expressions produced no output"

    awk '
    BEGIN {
        normal[0] = "#0a0a0a"; normal[1] = "#e64132"; normal[2] = "#a8c977"; normal[3] = "#f0a843"
        normal[4] = "#5b9dd9"; normal[5] = "#d97ea3"; normal[6] = "#7ec9c9"; normal[7] = "#e0e0e0"
        bright[0] = "#7a7a7a"; bright[1] = "#ff6b4a"; bright[2] = "#c3e88d"; bright[3] = "#ffd166"
        bright[4] = "#82aaff"; bright[5] = "#f78ca2"; bright[6] = "#89ddff"; bright[7] = "#ffffff"
        extra[0] = "#ff6600"; extra[1] = "#555555"; extra[2] = "#e0e0e0"; extra[3] = "#0a0a0a"
    }
    /^static const char \*colorname/ {
        inArray = 1
        print
        print "\t/* 8 normal colors */"
        for (i = 0; i < 8; i++) print "\t\"" normal[i] "\","
        print ""
        print "\t/* 8 bright colors */"
        for (i = 0; i < 8; i++) print "\t\"" bright[i] "\","
        print ""
        print "\t[255] = 0,"
        print ""
        print "\t/* more colors can be added after 255 to use with DefaultXX */"
        for (i = 0; i < 4; i++) print "\t\"" extra[i] "\","
        print "};"
        next
    }
    inArray && /^}/ {
        inArray = 0
        next
    }
    inArray { next }
    { print }
    ' "$targetConfig" > "$targetConfig.tmp" \
        || failAndExit "awk color array replacement failed" "$targetConfig" \
                        "stock config.def.h layout changed"
    mv "$targetConfig.tmp" "$targetConfig"

    grep -q 'monospace:pixelsize=13:antialias=true:autohint=true' "$targetConfig" \
        || failAndExit "font not applied to config.h" "$targetConfig" \
                        "sed pattern may need adjustment"
    grep -q '"#ff6600"' "$targetConfig" \
        || failAndExit "redhot cursor color missing from config.h" "$targetConfig" \
                        "awk pattern may need adjustment"
    grep -q 'ControlMask|ShiftMask, XK_C, clipcopy' "$targetConfig" \
        || failAndExit "Ctrl+Shift+C keybinding missing from config.h" "$targetConfig" \
                        "sed mask replacement failed"
    grep -q 'ControlMask|ShiftMask, XK_V, clippaste' "$targetConfig" \
        || failAndExit "Ctrl+Shift+V keybinding missing from config.h" "$targetConfig" \
                        "sed mask replacement failed"

    logOk "config.h themed with Redhot palette, monospace font, and Ctrl+Shift+C/V"
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
    logInfo "next step 2: confirm dark background (#0a0a0a), light foreground (#e0e0e0), orange cursor (#ff6600)"
    logInfo "next step 3: select text, press Ctrl+Shift+C, open another X11 app (xterm, browser), press Ctrl+V"
    logInfo "next step 4: run ${BEASTIE_ROOT}/tests/detect-os.sh and ${BEASTIE_ROOT}/tests/install.sh"
}

main() {
    ensureExecutableBits
    detectEnvironment
    installDependencies
    downloadSource
    applyOneClipboardPatch
    patchConfigMk
    applyConfigHeader
    buildSource
    reportNextSteps
    logOk "install.sh finished successfully"
}

main "$@"