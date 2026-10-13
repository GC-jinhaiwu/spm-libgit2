#!/usr/bin/env bash
# Builds libgit2, libssh2 and OpenSSL as static XCFrameworks for Apple
# platforms and maintains the Swift package manifest. See SPM.md.
#
#   script/spm/build.sh openssl | libssh2 | libgit2   build one library (in this order)
#   script/spm/build.sh all                           build all three
#   script/spm/build.sh manifest <tag>                rewrite Package.swift for release <tag>
#
#   --package-only   skip compiling; only re-create the XCFramework(s) from build/spm
#
# Output: build/spm/dist/<name>.xcframework and .zip; logs in build/spm/logs.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
for part in env openssl libssh2 libgit2 manifest; do
    # shellcheck source=/dev/null
    source "$HERE/lib/$part.sh"
done

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

positional=()
for arg in "$@"; do
    case $arg in
        --package-only) PACKAGE_ONLY=1 ;;
        -h | --help)    usage ;;
        *)              positional+=("$arg") ;;
    esac
done
set -- ${positional[@]+"${positional[@]}"}

case ${1:-} in
    openssl)  build_openssl ;;
    libssh2)  build_libssh2 ;;
    libgit2)  build_libgit2 ;;
    all)      build_openssl && build_libssh2 && build_libgit2 ;;
    manifest) write_manifest "${2:?usage: build.sh manifest <tag>}" ;;
    *)        usage 1 ;;
esac
