#!/bin/sh
set -eu

BEASTIE_ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${BEASTIE_ROOT}/.build"
ST_VERSION="0.9.3"
BEASTIE_VERSION="1.0.0"
ST_TARBALL="st-${ST_VERSION}.tar.gz"
ST_URL="https://dl.suckless.org/st/${ST_TARBALL}"
SCROLLBACK_PATCH_URL="https://st.suckless.org/patches/scrollback/st-scrollback-0.9.2.diff"
SCROLLBACK_PATCH_FILE="${BUILD_DIR}/st-scrollback.diff"
ALPHA_PATCH_URL="https://st.suckless.org/patches/alpha/st-alpha-20220206-0.8.5.diff"
ALPHA_PATCH_FILE="${BUILD_DIR}/st-alpha.diff"
XRESOURCES_PATCH_URL="https://st.suckless.org/patches/xresources/st-xresources-20200604-9ba7ecf.diff"
XRESOURCES_PATCH_FILE="${BUILD_DIR}/st-xresources.diff"
ST_SOURCE_DIR="${BUILD_DIR}/st-${ST_VERSION}"
BUILD_LOG="${BUILD_DIR}/build.log"
FONT_SOURCE_DIR="${BEASTIE_ROOT}/fonts/iosevka"
FONT_TARGET_DIR="${HOME}/.local/share/fonts/iosevka"
FONT_FAMILY="Iosevka Term"
ST_INSTALL_PREFIX="/usr/local"
WRAPPER_PATH="${ST_INSTALL_PREFIX}/bin/beastie"
MANPAGE_SOURCE="${BEASTIE_ROOT}/beastie.1"

logInfo() { printf '[info] %s\n' "$1" >&2; }
logOk()   { printf '[ OK ] %s\n' "$1" >&2; }
logWarn() { printf '[warn] %s\n' "$1" >&2; }
logFail() { printf '[FAIL] %s at %s, %s\n' "$1" "$2" "$3" >&2; }

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
                logWarn "apt update reported errors, often a broken third-party repository; continuing to install"
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
                x11-xserver-utils \
                ncurses-bin \
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
                xorg-x11-xrdb \
                ncurses \
                || failAndExit "dnf install failed" "dnf" \
                                "check network and repository availability"
            ;;
        pacman)
            logInfo "installing dependencies via pacman"
            pacman -Syu --noconfirm \
                base-devel libx11 libxft libxrender \
                fontconfig freetype2 pkgconf patch unzip \
                picom \
                xorg-xrdb \
                ncurses \
                || failAndExit "pacman install failed" "pacman" \
                                "check network and mirror availability"
            ;;
        pkg)
            logInfo "installing dependencies via pkg"
            pkg install -y \
                gcc gmake libX11 libXft libXrender \
                fontconfig freetype2 pkgconf patch unzip \
                picom \
                xrdb \
                ncurses \
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
                    "run fc-list | grep -i Iosevka and check the family name"
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
                            "patch may not match st 0.9.3, check ${SCROLLBACK_PATCH_FILE}"
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

    logOk "scrollback set to 5000 lines, HISTSIZE in st.c"
}

patchConfigMk() {
    configMkPath="${ST_SOURCE_DIR}/config.mk"
    [ -f "$configMkPath" ] \
        || failAndExit "config.mk missing" "$configMkPath" \
                        "upstream tarball layout changed"
    case "$OS" in
        Linux)
            logInfo "config.mk: Linux uses upstream defaults, no patch needed"
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
        logInfo "alpha support already present, skipping patch"
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
                logWarn "alpha patch hunk for xinit was rejected, known st 0.9.3 incompatibility, applying manual fallback"
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
                logOk "alpha hunk 7 manually applied, xw.depth for window and pixmap"
            else
                failAndExit "alpha patch rejected an unknown hunk" \
                            "${ST_SOURCE_DIR}/x.c.rej" \
                            "patch is incompatible with st 0.9.3, inspect the rej file"
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

    logOk "alpha set to 0.95 in config.def.h and -lXrender added to config.mk"
}

applyXresourcesPatch() {
    if grep -q 'resources\[\]' "${ST_SOURCE_DIR}/config.def.h" 2>/dev/null; then
        logInfo "xresources support already present, skipping patch"
    else
        logInfo "downloading xresources patch from ${XRESOURCES_PATCH_URL}"
        if [ -f "$XRESOURCES_PATCH_FILE" ]; then
            logInfo "patch already cached at ${XRESOURCES_PATCH_FILE}"
        else
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL -o "$XRESOURCES_PATCH_FILE" "$XRESOURCES_PATCH_URL" \
                    || failAndExit "xresources patch download failed" "$XRESOURCES_PATCH_URL" \
                                    "check network connectivity"
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$XRESOURCES_PATCH_FILE" "$XRESOURCES_PATCH_URL" \
                    || failAndExit "xresources patch download failed" "$XRESOURCES_PATCH_URL" \
                                    "check network connectivity"
            else
                failAndExit "neither curl nor wget available" "PATH=$PATH" \
                            "install curl or wget"
            fi
        fi
        (
            cd "$ST_SOURCE_DIR" || exit 1
            patch -p1 --forward < "$XRESOURCES_PATCH_FILE" || true
        )

        rejDir="${BUILD_DIR}/xresources-rej"
        if [ -f "${ST_SOURCE_DIR}/x.c.rej" ] || [ -f "${ST_SOURCE_DIR}/config.def.h.rej" ]; then
            mkdir -p "$rejDir"
            cp "${ST_SOURCE_DIR}"/*.rej "$rejDir/" 2>/dev/null || true
            logWarn "xresources patch had rejections, copies saved to ${rejDir}"
            failAndExit "xresources patch rejected one or more hunks" \
                        "${rejDir}" \
                        "inspect the rej files and report to get a manual fallback"
        fi
        logOk "xresources patch applied"
    fi

    grep -q 'resources\[\]' "${ST_SOURCE_DIR}/config.def.h" \
        || failAndExit "resources not found in config.def.h" \
                        "${ST_SOURCE_DIR}/config.def.h" \
                        "patch may have failed"

    grep -q 'XrmGetStringDatabase\|XResourceManagerString\|XrmInitialize' "${ST_SOURCE_DIR}/x.c" \
        || failAndExit "Xrm API not found in x.c after xresources patch" \
                        "${ST_SOURCE_DIR}/x.c" \
                        "patch may not have applied to x.c"

    grep -q '{ "background",.*colorname\[256\]' "${ST_SOURCE_DIR}/config.def.h" \
        || failAndExit "xresources patch no longer maps background to colorname 256" \
                        "${ST_SOURCE_DIR}/config.def.h" \
                        "patch version changed, verify resources indices before updating defaults"

    logOk "xresources wired into config.def.h and x.c"
}

applySpawnFunction() {
    if grep -q '^spawn(const Arg \*arg)' "${ST_SOURCE_DIR}/st.c" 2>/dev/null; then
        logInfo "spawn function already present in st.c, skipping injection"
    else
        grep -q '^ttynew(' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "ttynew anchor not found in st.c" "${ST_SOURCE_DIR}/st.c" \
                            "upstream st.c layout changed"

        awk '
        BEGIN { total = 0; injected = 0 }
        { lines[total++] = $0 }
        END {
            for (i = 0; i < total; i++) {
                if (!injected && i + 1 < total \
                    && lines[i] ~ /^(void|int)[[:space:]]*$/ \
                    && lines[i+1] ~ /^ttynew\(/) {
                    print "void"
                    print "spawn(const Arg *arg)"
                    print "{"
                    print "\tif (fork() == 0) {"
                    print "\t\tsetsid();"
                    print "\t\texecvp(((char **)arg->v)[0], (char **)arg->v);"
                    print "\t\tdie(\"st: execvp %s failed: %s\\n\", ((char **)arg->v)[0], strerror(errno));"
                    print "\t}"
                    print "}"
                    print ""
                    print lines[i]
                    injected = 1
                    continue
                }
                print lines[i]
            }
            if (!injected) {
                exit 1
            }
        }
        ' "${ST_SOURCE_DIR}/st.c" > "${ST_SOURCE_DIR}/st.c.tmp" \
            || failAndExit "awk spawn injection failed" "${ST_SOURCE_DIR}/st.c" \
                            "st.c layout changed, ttynew is not preceded by int or void"

        if [ ! -s "${ST_SOURCE_DIR}/st.c.tmp" ]; then
            rm -f "${ST_SOURCE_DIR}/st.c.tmp"
            failAndExit "awk produced empty output" "${ST_SOURCE_DIR}/st.c" \
                        "check st.c integrity"
        fi

        mv "${ST_SOURCE_DIR}/st.c.tmp" "${ST_SOURCE_DIR}/st.c"

        grep -q '^spawn(const Arg \*arg)' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "spawn function not present after injection" \
                            "${ST_SOURCE_DIR}/st.c" \
                            "awk injection failed"

        grep -q 'setsid();' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "setsid call missing in spawn function" \
                            "${ST_SOURCE_DIR}/st.c" \
                            "awk injection incomplete"

        grep -q 'execvp(((char \*\*)arg->v)\[0\]' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "execvp call missing in spawn function" \
                            "${ST_SOURCE_DIR}/st.c" \
                            "awk injection incomplete"

        prefixBeforeTtynew=$(grep -B1 '^ttynew(' "${ST_SOURCE_DIR}/st.c" | head -1 | tr -d '[:space:]')
        case "$prefixBeforeTtynew" in
            int|void) logOk "original ttynew return type ${prefixBeforeTtynew} preserved" ;;
            *) failAndExit "unexpected prefix before ttynew after injection" \
                           "$prefixBeforeTtynew" \
                           "awk injection corrupted the return type" ;;
        esac

        logOk "spawn function injected into st.c, setsid plus fork plus execvp on Arg.v"
    fi

    if grep -q '^void spawn(const Arg \*);' "${ST_SOURCE_DIR}/st.h" 2>/dev/null; then
        logInfo "spawn prototype already present in st.h, skipping injection"
    else
        grep -q '^} Arg;' "${ST_SOURCE_DIR}/st.h" \
            || failAndExit "Arg union anchor not found in st.h" "${ST_SOURCE_DIR}/st.h" \
                            "upstream st.h layout changed"

        awk '
        BEGIN { injected = 0 }
        /^} Arg;$/ && !injected {
            print
            print ""
            print "void spawn(const Arg *);"
            injected = 1
            next
        }
        { print }
        END { if (!injected) exit 1 }
        ' "${ST_SOURCE_DIR}/st.h" > "${ST_SOURCE_DIR}/st.h.tmp" \
            || failAndExit "awk spawn prototype injection failed" "${ST_SOURCE_DIR}/st.h" \
                            "st.h layout changed"

        mv "${ST_SOURCE_DIR}/st.h.tmp" "${ST_SOURCE_DIR}/st.h"

        grep -q '^void spawn(const Arg \*);' "${ST_SOURCE_DIR}/st.h" \
            || failAndExit "spawn prototype not present after injection" \
                            "${ST_SOURCE_DIR}/st.h" \
                            "awk injection failed"

        logOk "spawn prototype injected into st.h, visible to x.c and st.c"
    fi
}

applyQuitFunction() {
    if grep -q '^quit(const Arg \*arg)' "${ST_SOURCE_DIR}/st.c" 2>/dev/null; then
        logInfo "quit function already present in st.c, skipping injection"
    else
        grep -q '^ttynew(' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "ttynew anchor not found in st.c" "${ST_SOURCE_DIR}/st.c" \
                            "upstream st.c layout changed"

        awk '
        BEGIN { total = 0; injected = 0 }
        { lines[total++] = $0 }
        END {
            for (i = 0; i < total; i++) {
                if (!injected && i + 1 < total \
                    && lines[i] ~ /^(void|int)[[:space:]]*$/ \
                    && lines[i+1] ~ /^ttynew\(/) {
                    print "void"
                    print "quit(const Arg *arg)"
                    print "{"
                    print "\texit(0);"
                    print "}"
                    print ""
                    print lines[i]
                    injected = 1
                    continue
                }
                print lines[i]
            }
            if (!injected) {
                exit 1
            }
        }
        ' "${ST_SOURCE_DIR}/st.c" > "${ST_SOURCE_DIR}/st.c.tmp" \
            || failAndExit "awk quit injection failed" "${ST_SOURCE_DIR}/st.c" \
                            "st.c layout changed, ttynew is not preceded by int or void"

        if [ ! -s "${ST_SOURCE_DIR}/st.c.tmp" ]; then
            rm -f "${ST_SOURCE_DIR}/st.c.tmp"
            failAndExit "awk produced empty output for quit" "${ST_SOURCE_DIR}/st.c" \
                        "check st.c integrity"
        fi

        mv "${ST_SOURCE_DIR}/st.c.tmp" "${ST_SOURCE_DIR}/st.c"

        grep -q '^quit(const Arg \*arg)' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "quit function not present after injection" \
                            "${ST_SOURCE_DIR}/st.c" \
                            "awk injection failed"

        grep -q 'exit(0);' "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "exit call missing in quit function" \
                            "${ST_SOURCE_DIR}/st.c" \
                            "awk injection incomplete"

        logOk "quit function injected into st.c, exit(0) on Ctrl+Shift+Q"
    fi

    if grep -q '^void quit(const Arg \*);' "${ST_SOURCE_DIR}/st.h" 2>/dev/null; then
        logInfo "quit prototype already present in st.h, skipping injection"
    else
        grep -q '^void spawn(const Arg \*);' "${ST_SOURCE_DIR}/st.h" \
            || failAndExit "spawn prototype anchor not found in st.h" "${ST_SOURCE_DIR}/st.h" \
                            "applySpawnFunction must run before applyQuitFunction"

        awk '
        BEGIN { injected = 0 }
        /^void spawn\(const Arg \*\);$/ && !injected {
            print
            print ""
            print "void quit(const Arg *);"
            injected = 1
            next
        }
        { print }
        END { if (!injected) exit 1 }
        ' "${ST_SOURCE_DIR}/st.h" > "${ST_SOURCE_DIR}/st.h.tmp" \
            || failAndExit "awk quit prototype injection failed" "${ST_SOURCE_DIR}/st.h" \
                            "st.h layout changed"

        mv "${ST_SOURCE_DIR}/st.h.tmp" "${ST_SOURCE_DIR}/st.h"

        grep -q '^void quit(const Arg \*);' "${ST_SOURCE_DIR}/st.h" \
            || failAndExit "quit prototype not present after injection" \
                            "${ST_SOURCE_DIR}/st.h" \
                            "awk injection failed"

        logOk "quit prototype injected into st.h"
    fi
}

applyWindowTitle() {
    if grep -q 'Beastie' "${ST_SOURCE_DIR}/x.c" 2>/dev/null && \
       grep -qE 'opt_title[[:space:]]*\?[[:space:]]*opt_title[[:space:]]*:[[:space:]]*"Beastie"' "${ST_SOURCE_DIR}/x.c" 2>/dev/null; then
        logInfo "window title already set to Beastie in x.c, skipping"
        return 0
    fi

    if grep -qE 'opt_title[[:space:]]*\?[[:space:]]*opt_title[[:space:]]*:[[:space:]]*"st"' "${ST_SOURCE_DIR}/x.c" 2>/dev/null; then
        sed -i.bak -E 's/opt_title[[:space:]]*\?[[:space:]]*opt_title[[:space:]]*:[[:space:]]*"st"/opt_title ? opt_title : "Beastie"/g' \
            "${ST_SOURCE_DIR}/x.c" \
            || failAndExit "sed window title replacement failed" "${ST_SOURCE_DIR}/x.c" \
                            "x.c layout changed"
        logOk "window title defaulted to Beastie in x.c opt_title ternary"
        return 0
    fi

    if grep -q 'opt_title = "st"' "${ST_SOURCE_DIR}/st.c" 2>/dev/null; then
        sed -i.bak 's/opt_title = "st"/opt_title = "Beastie"/g' \
            "${ST_SOURCE_DIR}/st.c" \
            || failAndExit "sed opt_title default failed" "${ST_SOURCE_DIR}/st.c" \
                            "st.c layout changed"
        logOk "window title defaulted to Beastie in st.c opt_title default"
        return 0
    fi

    logWarn "window title anchor not found in x.c or st.c, the beastie wrapper will pass -t Beastie as fallback"
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
        extra[0] = "#0a0a0a"; extra[1] = "#e0e0e0"; extra[2] = "#ff6600"; extra[3] = "#555555"
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

    sed -i.bak3 \
        -e 's/^unsigned int defaultfg = [0-9][0-9]*;/unsigned int defaultfg = 257;/' \
        -e 's/^static unsigned int defaultfg = [0-9][0-9]*;/static unsigned int defaultfg = 257;/' \
        -e 's/^unsigned int defaultbg = [0-9][0-9]*;/unsigned int defaultbg = 256;/' \
        -e 's/^static unsigned int defaultbg = [0-9][0-9]*;/static unsigned int defaultbg = 256;/' \
        -e 's/^unsigned int defaultcs = [0-9][0-9]*;/unsigned int defaultcs = 258;/' \
        -e 's/^static unsigned int defaultcs = [0-9][0-9]*;/static unsigned int defaultcs = 258;/' \
        -e 's/^unsigned int defaultrcs = [0-9][0-9]*;/unsigned int defaultrcs = 259;/' \
        -e 's/^static unsigned int defaultrcs = [0-9][0-9]*;/static unsigned int defaultrcs = 259;/' \
        "$targetConfig" \
        || failAndExit "sed defaultXX alignment failed" "$targetConfig" \
                        "config.h layout changed"

    awk '
    BEGIN { injected = 0 }
    /clippaste,/ && !injected {
        print
        print "\t{ ControlMask|ShiftMask, XK_N, spawn, {.v = (char *[]){ \"beastie\", NULL } } },"
        print "\t{ ControlMask|ShiftMask, XK_D, spawn, {.v = (char *[]){ \"devil\", \".\", NULL } } },"
        print "\t{ ControlMask|ShiftMask, XK_F, spawn, {.v = (char *[]){ \"nid\", \".\", NULL } } },"
        print "\t{ ControlMask|ShiftMask, XK_Q, quit, {.i = 0} },"
        injected = 1
        next
    }
    { print }
    ' "$targetConfig" > "$targetConfig.tmp" \
        || failAndExit "awk spawn and quit keybindings injection failed" "$targetConfig" \
                        "config.h layout changed"
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
        || failAndExit "alpha 0.95 missing from config.h" "$targetConfig" \
                        "alpha field may have been clobbered"
    grep -q 'resources\[\]' "$targetConfig" \
        || failAndExit "resources missing from config.h" "$targetConfig" \
                        "xresources array may have been clobbered by awk"
    grep -q 'unsigned int defaultbg = 256;' "$targetConfig" \
        || failAndExit "defaultbg not aligned to 256 in config.h" "$targetConfig" \
                        "sed defaultXX alignment failed"
    grep -q 'unsigned int defaultfg = 257;' "$targetConfig" \
        || failAndExit "defaultfg not aligned to 257 in config.h" "$targetConfig" \
                        "sed defaultXX alignment failed"
    grep -q 'unsigned int defaultcs = 258;' "$targetConfig" \
        || failAndExit "defaultcs not aligned to 258 in config.h" "$targetConfig" \
                        "sed defaultXX alignment failed"
    grep -q 'XK_N, spawn, {.v = (char \*\[\]){ "beastie", NULL } }' "$targetConfig" \
        || failAndExit "Ctrl+Shift+N spawn keybinding missing from config.h" "$targetConfig" \
                        "awk spawn keybindings injection failed"
    grep -q 'XK_D, spawn, {.v = (char \*\[\]){ "devil", ".", NULL } }' "$targetConfig" \
        || failAndExit "Ctrl+Shift+D spawn keybinding missing from config.h" "$targetConfig" \
                        "awk spawn keybindings injection failed"
    grep -q 'XK_F, spawn, {.v = (char \*\[\]){ "nid", ".", NULL } }' "$targetConfig" \
        || failAndExit "Ctrl+Shift+F spawn keybinding missing from config.h" "$targetConfig" \
                        "awk spawn keybindings injection failed"
    grep -q 'XK_Q, quit, {.i = 0} }' "$targetConfig" \
        || failAndExit "Ctrl+Shift+Q quit keybinding missing from config.h" "$targetConfig" \
                        "awk quit keybinding injection failed"

    logOk "config.h themed with Redhot palette, Iosevka Term, Ctrl+Shift+C and V, alpha 0.95, xresources, aligned defaultXX, spawn and quit keybindings"
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
        logWarn "${warningCount} warnings in build log, upstream st, not our code"
    else
        logOk "build clean, 0 warnings"
    fi
    logOk "st ${ST_VERSION} built at ${stBinaryPath}"
}

installBinary() {
    (
        cd "$ST_SOURCE_DIR" || exit 1
        "$BUILD_TOOL" install PREFIX="$ST_INSTALL_PREFIX" >/dev/null 2>&1 \
            || failAndExit "make install failed" "$ST_SOURCE_DIR" \
                            "check Makefile install target and PREFIX permissions"
    )
    installedStPath="${ST_INSTALL_PREFIX}/bin/st"
    [ -x "$installedStPath" ] \
        || failAndExit "st not installed at expected path" "$installedStPath" \
                        "make install may not have honored PREFIX"
    logOk "st binary installed at ${installedStPath}"
}

installTerminfo() {
    stInfoPath="${ST_SOURCE_DIR}/st.info"
    [ -f "$stInfoPath" ] \
        || failAndExit "st.info missing in source tree" "$stInfoPath" \
                        "upstream tarball layout changed"

    beastieInfoPath="${BUILD_DIR}/beastie.info"
    sed 's/^st-256color|/beastie-256color|/' "$stInfoPath" > "$beastieInfoPath" \
        || failAndExit "sed st.info rename failed" "$stInfoPath" \
                        "st.info layout changed"

    grep -q '^beastie-256color|' "$beastieInfoPath" \
        || failAndExit "beastie-256color terminfo entry not found after sed" \
                        "$beastieInfoPath" \
                        "st.info first line may not start with st-256color"

    mkdir -p "$TERMINFO_DIR"
    if command -v tic >/dev/null 2>&1; then
        tic -x -o "$TERMINFO_DIR" "$beastieInfoPath" >/dev/null 2>&1 \
            || failAndExit "tic failed" "$beastieInfoPath" \
                            "check ncurses-bin installation and TERMINFO_DIR permissions"
    else
        failAndExit "tic not found" "PATH=$PATH" \
                    "install ncurses-bin on Debian or ncurses elsewhere"
    fi

    infocmp -A "$TERMINFO_DIR" beastie-256color >/dev/null 2>&1 \
        || failAndExit "beastie-256color not registered in terminfo" \
                        "$TERMINFO_DIR" \
                        "tic may have written to a different TERMINFO dir, check the beastie-256color file"

    logOk "beastie-256color terminfo installed under ${TERMINFO_DIR}"
}

installWrapper() {
    wrapperDir=$(dirname "$WRAPPER_PATH")
    [ -d "$wrapperDir" ] \
        || mkdir -p "$wrapperDir" \
        || failAndExit "cannot create wrapper directory" "$wrapperDir" \
                        "check /usr/local/bin permissions"

    cat > "$WRAPPER_PATH" <<WRAPPER_EOF
#!/bin/sh
if [ "\${1:-}" = "--version" ]; then
    printf 'beastie ${BEASTIE_VERSION} (st ${ST_VERSION})\n'
    exit 0
fi
if [ "\${1:-}" = "--selftest" ]; then
    printf 'beastie selftest\n'
    if command -v st >/dev/null 2>&1; then
        printf '  st: OK (%s)\n' "\$(command -v st)"
    else
        printf '  st: FAIL (st not in PATH)\n'
        exit 1
    fi
    if infocmp -A "\${TERMINFO:-\$HOME/.terminfo}" beastie-256color >/dev/null 2>&1; then
        printf '  terminfo: OK\n'
    else
        printf '  terminfo: FAIL (beastie-256color not found)\n'
        exit 1
    fi
    printf '  config.h: compiled into binary (not runtime verifiable)\n'
    exit 0
fi
export TERM=beastie-256color
exec ${ST_INSTALL_PREFIX}/bin/st \\
  -f "Iosevka Term:size=13" \\
  -g 100x30 \\
  -t "Beastie" \\
  "\$@"
WRAPPER_EOF

    chmod 0755 "$WRAPPER_PATH" \
        || failAndExit "cannot set wrapper executable" "$WRAPPER_PATH" \
                        "check file permissions"

    [ -x "$WRAPPER_PATH" ] \
        || failAndExit "wrapper not executable after chmod" "$WRAPPER_PATH" \
                        "chmod may have failed silently"

    versionOutput=$("$WRAPPER_PATH" --version 2>&1) \
        || failAndExit "wrapper --version failed" "$WRAPPER_PATH" \
                        "check wrapper script for syntax errors"
    case "$versionOutput" in
        beastie*) logOk "wrapper installed at ${WRAPPER_PATH} and reports: ${versionOutput}" ;;
        *) failAndExit "wrapper --version returned unexpected output" "$versionOutput" \
                       "check the wrapper script content" ;;
    esac
}

installManpage() {
    case "$OS" in
        Linux) manDir="/usr/local/share/man/man1" ;;
        FreeBSD) manDir="/usr/local/man/man1" ;;
        *) failAndExit "unknown OS for man directory" "$OS" \
                       "detect-os.sh should have caught this" ;;
    esac

    [ -f "$MANPAGE_SOURCE" ] \
        || failAndExit "beastie.1 not found in repository root" "$MANPAGE_SOURCE" \
                        "the man page must ship as beastie.1 in the repo"

    mkdir -p "$manDir" \
        || failAndExit "cannot create man directory" "$manDir" \
                        "check /usr/local permissions"

    targetMan="${manDir}/beastie.1"
    cp "$MANPAGE_SOURCE" "$targetMan" \
        || failAndExit "cannot install man page" "$MANPAGE_SOURCE" \
                        "check directory permissions"

    chmod 0644 "$targetMan" \
        || failAndExit "cannot set man page permissions" "$targetMan" \
                        "check file permissions"

    [ -f "$targetMan" ] \
        || failAndExit "man page missing after install" "$targetMan" \
                        "cp may have failed silently"

    if command -v mandb >/dev/null 2>&1; then
        mandb -q >/dev/null 2>&1 || logWarn "mandb failed, man beastie may not find the page until mandb runs"
    fi

    logOk "beastie.1 installed at ${targetMan}"
}

installXresources() {
    xresourcesFile="${HOME}/.Xresources"

    if [ -f "$xresourcesFile" ]; then
        if [ -n "$(tail -c 1 "$xresourcesFile")" ]; then
            printf '\n' >> "$xresourcesFile" \
                || failAndExit "cannot append newline to Xresources" "$xresourcesFile" \
                                "check file permissions"
            logInfo "added missing trailing newline to ${xresourcesFile}"
        fi
    else
        touch "$xresourcesFile" \
            || failAndExit "cannot create Xresources file" "$xresourcesFile" \
                            "check HOME permissions"
    fi

    tmpFile="${xresourcesFile}.beastie.tmp"
    if grep -q '^st\.' "$xresourcesFile"; then
        grep -v '^st\.' "$xresourcesFile" > "$tmpFile" \
            || failAndExit "cannot filter Xresources" "$xresourcesFile" \
                            "check file permissions"
        mv "$tmpFile" "$xresourcesFile" \
            || failAndExit "cannot replace Xresources" "$xresourcesFile" \
                            "check directory permissions"
        logInfo "removed previous st properties from ${xresourcesFile}"
    fi

    for propertyLine in \
        'st.background: #0a0a0a' \
        'st.foreground: #e0e0e0' \
        'st.cursorColor: #ff6600' \
        'st.font: Iosevka Term:size=13'; do
        printf '%s\n' "$propertyLine" >> "$xresourcesFile" \
            || failAndExit "cannot append to Xresources" "$xresourcesFile" \
                            "check file permissions"
    done
    logOk "wrote 4 st properties to ${xresourcesFile}"

    if ! command -v xrdb >/dev/null 2>&1; then
        logWarn "xrdb not found, skipping merge, Xsession will load Xresources on next login"
        return 0
    fi

    xrdb -merge "$xresourcesFile" \
        || failAndExit "xrdb merge failed" "$xresourcesFile" \
                        "check DISPLAY is set and X11 is running"

    if ! xrdb -query 2>/dev/null | grep -q '^st\.background:'; then
        xrdbDebug=$(xrdb -query 2>&1 | grep '^st\.' || true)
        failAndExit "st.background not present after xrdb merge" \
                    "$xresourcesFile" \
                    "xrdb loaded: [${xrdbDebug}]"
    fi

    logOk "Xresources merged into running X server, st properties active"
}

reportNextSteps() {
    logInfo "next step 1: run beastie --version and beastie --selftest to verify the wrapper"
    logInfo "next step 2: run man beastie to read the installed man page"
    logInfo "next step 3: run beastie (no -e) for an interactive shell with prompt showing cwd"
    logInfo "next step 4: press Ctrl+Shift+Q inside beastie to quit cleanly"
    logInfo "next step 5: run seq 1 200 and press Shift+PgUp to scroll back"
    logInfo "next step 6: Ctrl+Shift+N spawns another beastie window, Ctrl+Shift+D and F need devil and nid on PATH"
    logInfo "next step 7: change st.background in Xresources, run xrdb merge and restart st to apply"
    logInfo "next step 8: run ${BEASTIE_ROOT}/tests/detect-os.sh and ${BEASTIE_ROOT}/tests/install.sh"
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
    applyXresourcesPatch
    applySpawnFunction
    applyQuitFunction
    applyWindowTitle
    applyConfigHeader
    buildSource
    installBinary
    installTerminfo
    installWrapper
    installManpage
    installXresources
    reportNextSteps
    logOk "install.sh finished successfully"
}

main "$@"