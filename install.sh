#!/bin/sh
set -eu

BEASTIE_ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${BEASTIE_ROOT}/.build"
ST_VERSION="0.9.3"
ST_TARBALL="st-${ST_VERSION}.tar.gz"
ST_URL="https://dl.suckless.org/st/${ST_TARBALL}"
SCROLLBACK_PATCH_URL="https://st.suckless.org/patches/scrollback/st-scrollback-0.9.2.diff"
SCROLLBACK_PATCH_FILE="${BUILD_DIR}/st-scrollback.diff"
ALPHA_PATCH_URL="https://st.suckless.org/patches/alpha/st-alpha-20220206-0.8.5.diff"
ALPHA_PATCH_FILE="${BUILD_DIR}/st-alpha.diff"
ST_SOURCE_DIR="${BUILD_DIR}/st-${ST_VERSION}"
BUILD_LOG="${BUILD_DIR}/build.log"
FONT_SOURCE_DIR="${BEASTIE_ROOT}/fonts/iosevka"
FONT_TARGET_DIR="${HOME}/.local/share/fonts/iosevka"
FONT_FAMILY="Iosevka Term"

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
                libxrender-dev \
                libfontconfig1-dev \
                libfreetype6-dev \
                pkg-config \
                patch \
                fontconfig \
                unzip \
                picom \
                || failAndExit "apt install failed" "apt" \
                                "check network connectivity and mirror availability"
            ;;
        dnf)
            logInfo "installing dependencies via dnf"
            dnf install -y \
                gcc make patch unzip \
                libX11-devel libXft-devel libXrender-devel \
                fontconfig-devel freetype-devel \
                pkgconf-pkg-config \
                picom \
                || failAndExit "dnf install failed" "dnf" \
                                "check network and repository availability"
            ;;
        pacman)
            logInfo "installing dependencies via pacman"
            pacman -Syu --noconfirm \
                base-devel libx11 libxft libxrender \
                fontconfig freetype2 pkgconf patch unzip \
                picom \
                || failAndExit "pacman install failed" "pacman" \
                                "check network and mirror availability"
            ;;
        pkg)
            logInfo "installing dependencies via pkg"
            pkg install -y \
                gcc gmake libX11 libXft libXrender \
                fontconfig freetype2 pkgconf patch unzip \
                picom \
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

installFonts() {
    [ -d "$FONT_SOURCE_DIR" ] \
        || failAndExit "bundled font directory missing" "$FONT_SOURCE_DIR" \
                        "add Iosevka Term TTF files plus OFL.txt to fonts/iosevka/"
    fontFileCount=$(find "$FONT_SOURCE_DIR" -maxdepth 1 -name '*.ttf' -type f | wc -l | tr -d ' ')
    [ "$fontFileCount" -gt 0 ] \
        || failAndExit "no TTF files in bundled font directory" "$FONT_SOURCE_DIR" \
                        "the repository must ship fonts/iosevka/*.ttf"
    mkdir -p "$FONT_TARGET_DIR"
    cp "$FONT_SOURCE_DIR"/*.ttf "$FONT_TARGET_DIR"/
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 \
            || failAndExit "fc-cache failed" "$FONT_TARGET_DIR" \
                            "check fontconfig installation"
    else
        failAndExit "fc-cache not found" "PATH=$PATH" \
                    "install fontconfig"
    fi
    if ! fc-list : family 2>/dev/null | grep -qi "$FONT_FAMILY"; then
        failAndExit "fontconfig cannot see the installed font" "$FONT_TARGET_DIR" \
                    "run fc-list | grep -i 'Iosevka' and check the family name"
    fi
    logOk "Iosevka Term installed under ${FONT_TARGET_DIR} and cached by fontconfig"
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

applyScrollbackPatch() {
    logInfo "downloading scrollback patch from ${SCROLLBACK_PATCH_URL}"
    if [ -f "$SCROLLBACK_PATCH_FILE" ]; then
        logInfo "patch already cached at ${SCROLLBACK_PATCH_FILE}"
    else
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$SCROLLBACK_PATCH_FILE" "$SCROLLBACK_PATCH_URL" \
                || failAndExit "scrollback patch download failed" "$SCROLLBACK_PATCH_URL" \
                                "check network connectivity"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$SCROLLBACK_PATCH_FILE" "$SCROLLBACK_PATCH_URL" \
                || failAndExit "scrollback patch download failed" "$SCROLLBACK_PATCH_URL" \
                                "check network connectivity"
        else
            failAndExit "neither curl nor wget available" "PATH=$PATH" \
                        "install curl or wget"
        fi
    fi
    (
        cd "$ST_SOURCE_DIR" || exit 1
        patch -p1 --forward < "$SCROLLBACK_PATCH_FILE" \
            || failAndExit "scrollback patch application failed" "$ST_SOURCE_DIR" \
                            "patch may not match st 0.9.3; check ${SCROLLBACK_PATCH_FILE}"
    )
    logOk "scrollback patch applied"

    grep -q '#define[[:space:]][[:space:]]*HISTSIZE' "${ST_SOURCE_DIR}/st.c" \
        || failAndExit "HISTSIZE define not found in st.c after patch" \
                        "${ST_SOURCE_DIR}/st.c" \
                        "patch may not have applied to st.c"

    sed -i.bak 's/^#define[[:space:]][[:space:]]*HISTSIZE[[:space:]][[:space:]]*[0-9][0-9]*/#define HISTSIZE 5000/' \
        "${ST_SOURCE_DIR}/st.c" \
        || failAndExit "sed HISTSIZE replacement failed" "${ST_SOURCE_DIR}/st.c" \
                        "st.c layout changed"

    grep -q '^#define HISTSIZE[[:space:]][[:space:]]*5000' "${ST_SOURCE_DIR}/st.c" \
        || failAndExit "HISTSIZE not set to 5000 in st.c" "${ST_SOURCE_DIR}/st.c" \
                        "sed replacement failed"

    logOk "scrollback set to 5000 lines (HISTSIZE in st.c)"
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

applyAlphaPatch() {
    if grep -q '^float alpha = ' "${ST_SOURCE_DIR}/config.def.h" 2>/dev/null; then
        logInfo "alpha support already present; skipping patch"
    else
        logInfo "downloading alpha patch from ${ALPHA_PATCH_URL}"
        if [ -f "$ALPHA_PATCH_FILE" ]; then
            logInfo "patch already cached at ${ALPHA_PATCH_FILE}"
        else
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL -o "$ALPHA_PATCH_FILE" "$ALPHA_PATCH_URL" \
                    || failAndExit "alpha patch download failed" "$ALPHA_PATCH_URL" \
                                    "check network connectivity"
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$ALPHA_PATCH_FILE" "$ALPHA_PATCH_URL" \
                    || failAndExit "alpha patch download failed" "$ALPHA_PATCH_URL" \
                                    "check network connectivity"
            else
                failAndExit "neither curl nor wget available" "PATH=$PATH" \
                            "install curl or wget"
            fi
        fi
        (
            cd "$ST_SOURCE_DIR" || exit 1
            patch -p1 --forward < "$ALPHA_PATCH_FILE" || true
        )

        if [ -f "${ST_SOURCE_DIR}/x.c.rej" ]; then
            if grep -q '@@.*xinit(int cols, int rows)' "${ST_SOURCE_DIR}/x.c.rej"; then
                logWarn "alpha patch hunk for xinit() was rejected (known st 0.9.3 incompatibility); applying manual fallback"
                rm -f "${ST_SOURCE_DIR}/x.c.rej"
                sed -i.bak2 \
                    -e 's/XDefaultDepth(xw\.dpy, xw\.scr)/xw.depth/g' \
                    -e 's/DefaultDepth(xw\.dpy, xw\.scr)/xw.depth/g' \
                    "${ST_SOURCE_DIR}/x.c" \
                    || failAndExit "sed alpha fallback failed" "${ST_SOURCE_DIR}/x.c" \
                                    "x.c layout changed"
                if grep -q 'XDefaultDepth\|DefaultDepth(xw\.dpy' "${ST_SOURCE_DIR}/x.c"; then
                    failAndExit "DefaultDepth still present in x.c after fallback" \
                                "${ST_SOURCE_DIR}/x.c" \
                                "sed replacement incomplete"
                fi
                logOk "alpha hunk 7 manually applied (xw.depth for window and pixmap)"
            else
                failAndExit "alpha patch rejected an unknown hunk" \
                            "${ST_SOURCE_DIR}/x.c.rej" \
                            "patch is incompatible with st 0.9.3; inspect the .rej file"
            fi
        fi
        logOk "alpha patch applied"
    fi

    grep -q '^float alpha = [0-9]' "${ST_SOURCE_DIR}/config.def.h" \
        || failAndExit "alpha field not found in config.def.h after patch" \
                        "${ST_SOURCE_DIR}/config.def.h" \
                        "patch may not have added the alpha field"

    sed -i.bak 's/^float alpha = [0-9][0-9]*\.[0-9][0-9]*;/float alpha = 0.95;/' \
        "${ST_SOURCE_DIR}/config.def.h" \
        || failAndExit "sed alpha replacement failed" "${ST_SOURCE_DIR}/config.def.h" \
                        "config.def.h layout changed"

    grep -q '^float alpha = 0.95;' "${ST_SOURCE_DIR}/config.def.h" \
        || failAndExit "alpha not set to 0.95 in config.def.h" "${ST_SOURCE_DIR}/config.def.h" \
                        "sed replacement failed"

    if ! grep -q -- '-lXrender' "${ST_SOURCE_DIR}/config.mk"; then
        sed -i.bak 's/-lXft/-lXft -lXrender/' "${ST_SOURCE_DIR}/config.mk" \
            || failAndExit "sed -lXrender injection failed" "${ST_SOURCE_DIR}/config.mk" \
                            "config.mk layout changed"
    fi

    grep -q -- '-lXrender' "${ST_SOURCE_DIR}/config.mk" \
        || failAndExit "-lXrender missing from config.mk after sed" \
                        "${ST_SOURCE_DIR}/config.mk" \
                        "sed injection failed"

    logOk "alpha = 0.95 set in config.def.h and -lXrender added to config.mk"
}

applyConfigHeader() {
    stockConfig="${ST_SOURCE_DIR}/config.def.h"
    targetConfig="${ST_SOURCE_DIR}/config.h"
    [ -f "$stockConfig" ] \
        || failAndExit "stock config.def.h missing" "$stockConfig" \
                        "upstream tarball layout changed"

    sed -e 's#^static char \*font = ".*";#static char *font = "Iosevka Term:size=13:antialias=true:autohint=true";#' \
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

    grep -q 'Iosevka Term:size=13:antialias=true:autohint=true' "$targetConfig" \
        || failAndExit "Iosevka font not applied to config.h" "$targetConfig" \
                        "sed font replacement failed"
    grep -q '"#ff6600"' "$targetConfig" \
        || failAndExit "redhot cursor color missing from config.h" "$targetConfig" \
                        "awk pattern may need adjustment"
    grep -q 'ControlMask|ShiftMask, XK_C, clipcopy' "$targetConfig" \
        || failAndExit "Ctrl+Shift+C keybinding missing from config.h" "$targetConfig" \
                        "sed mask replacement failed"
    grep -q 'ControlMask|ShiftMask, XK_V, clippaste' "$targetConfig" \
        || failAndExit "Ctrl+Shift+V keybinding missing from config.h" "$targetConfig" \
                        "sed mask replacement failed"
    grep -q '^float alpha = 0.95;' "$targetConfig" \
        || failAndExit "alpha = 0.95 missing from config.h" "$targetConfig" \
                        "alpha field may have been clobbered"

    logOk "config.h themed with Redhot palette, Iosevka Term, Ctrl+Shift+C/V, and alpha 0.95"
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
    logInfo "next step 1: run ${stBinaryPath} -e sh -c 'echo TERM=\$TERM; read x' (compositor should already be active on this desktop)"
    logInfo "next step 2: confirm dark background (#0a0a0a) with subtle transparency, light foreground (#e0e0e0), orange cursor (#ff6600), Iosevka Term glyphs"
    logInfo "next step 3: run seq 1 200 and press Shift+PgUp to scroll back"
    logInfo "next step 4: select text, press Ctrl+Shift+C, open another X11 app, press Ctrl+V"
    logInfo "next step 5: run ${BEASTIE_ROOT}/tests/detect-os.sh and ${BEASTIE_ROOT}/tests/install.sh"
}

main() {
    ensureExecutableBits
    detectEnvironment
    installDependencies
    installFonts
    downloadSource
    applyScrollbackPatch
    patchConfigMk
    applyAlphaPatch
    applyConfigHeader
    buildSource
    reportNextSteps
    logOk "install.sh finished successfully"
}

main "$@"