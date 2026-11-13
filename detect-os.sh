#!/bin/sh
set -eu

printUsage() {
    printf '%s\n' \
        'usage: detect-os.sh --print' \
        '       detect-os.sh --help' >&2
}

detectOperatingSystem() {
    unameOutput=$(uname -s 2>/dev/null || true)
    case "$unameOutput" in
        FreeBSD) printf 'FreeBSD' ;;
        Linux)   printf 'Linux' ;;
        *)       printf '' ;;
    esac
}

detectPackageManager() {
    if command -v apt >/dev/null 2>&1; then
        printf 'apt'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf'
    elif command -v pacman >/dev/null 2>&1; then
        printf 'pacman'
    elif command -v pkg >/dev/null 2>&1; then
        printf 'pkg'
    else
        printf ''
    fi
}

detectBuildTool() {
    case "$1" in
        FreeBSD) printf 'gmake' ;;
        Linux)   printf 'make'  ;;
        *)       printf ''      ;;
    esac
}

detectX11Prefix() {
    case "$1" in
        FreeBSD) printf '/usr/local' ;;
        Linux)   printf '/usr'       ;;
        *)       printf ''           ;;
    esac
}

detectTerminfoDirectory() {
    case "$1" in
        FreeBSD) printf '/usr/local/share/misc' ;;
        Linux)   printf '%s/.terminfo' "${HOME:-/root}" ;;
        *)       printf '' ;;
    esac
}

failAndExit() {
    printf '[FAIL] %s at %s — %s\n' "$1" "$2" "$3" >&2
    exit 1
}

printEnvironment() {
    printf 'OS=%s\n'           "$operatingSystem"
    printf 'PKG=%s\n'          "$packageManager"
    printf 'BUILD_TOOL=%s\n'   "$buildTool"
    printf 'X11_PREFIX=%s\n'   "$x11Prefix"
    printf 'TERMINFO_DIR=%s\n' "$terminfoDirectory"
}

main() {
    printMode=0
    for argument in "$@"; do
        case "$argument" in
            --print)   printMode=1 ;;
            -h|--help) printUsage; exit 0 ;;
            *) failAndExit 'unknown argument' "$argument" 'run detect-os.sh --help' ;;
        esac
    done

    if [ "$printMode" -eq 0 ]; then
        printUsage
        exit 2
    fi

    operatingSystem=$(detectOperatingSystem)
    if [ -z "$operatingSystem" ]; then
        failAndExit 'unsupported operating system' \
            "$(uname -s 2>/dev/null || printf 'unknown')" \
            'supported: FreeBSD, Linux'
    fi

    packageManager=$(detectPackageManager)
    if [ -z "$packageManager" ]; then
        failAndExit 'no package manager detected' \
            "PATH=$PATH" \
            'install apt, dnf, pacman, or pkg'
    fi

    buildTool=$(detectBuildTool "$operatingSystem")
    x11Prefix=$(detectX11Prefix "$operatingSystem")
    terminfoDirectory=$(detectTerminfoDirectory "$operatingSystem")

    printEnvironment
}

main "$@"