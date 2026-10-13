# Paths, target slices and helpers shared by script/spm/lib/*.sh.
# Sourced by script/spm/build.sh; not meant to be run on its own.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
VENDOR=$REPO_ROOT/vendor
OUT=$REPO_ROOT/build/spm     # per-slice installs and intermediate builds
DIST=$OUT/dist               # XCFrameworks and the zips attached to releases
LOGS=$OUT/logs
JOBS=$(sysctl -n hw.ncpu)
PACKAGE_ONLY=0

IOS_MIN=13.0
CATALYST_MIN=13.1
MACOS_MIN=10.15

# One entry per XCFramework slice.
SLICES="ios ios-simulator maccatalyst macos"

mkdir -p "$LOGS"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Runs a command with stdout/stderr appended to build/spm/logs/<name>.log.
# On failure the tail of the log is shown and the script stops.
run_logged() {
    local name=$1
    shift
    if ! "$@" >> "$LOGS/$name.log" 2>&1; then
        tail -n 40 "$LOGS/$name.log" >&2
        die "$name failed (full log: $LOGS/$name.log)"
    fi
}

# Sets SLICE_CMAKE_FLAGS: SDK, architectures and deployment target of a slice.
# Mac Catalyst is a macOS SDK build retargeted with -mtargetos, which keeps
# it a single universal build like the simulator slice.
slice_cmake_flags() {
    case $1 in
        ios)
            SLICE_CMAKE_FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos
                -DCMAKE_OSX_ARCHITECTURES=arm64 "-DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN") ;;
        ios-simulator)
            SLICE_CMAKE_FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator
                "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64" "-DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN") ;;
        maccatalyst)
            SLICE_CMAKE_FLAGS=(-DCMAKE_OSX_SYSROOT=macosx "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64"
                "-DCMAKE_C_FLAGS=-mtargetos=ios$CATALYST_MIN-macabi") ;;
        macos)
            SLICE_CMAKE_FLAGS=("-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64"
                "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN") ;;
        *)
            die "unknown slice: $1" ;;
    esac
}

# Configures, builds and installs a cmake project for one slice.
#   cmake_build <name> <slice> <source dir> [extra cmake args...]
# Installs into build/spm/<name>/<slice>.
cmake_build() {
    local name=$1 slice=$2 src=$3
    shift 3
    local prefix=$OUT/$name/$slice
    rm -rf "$prefix" "$prefix.build" "$LOGS/$name-$slice.log"
    slice_cmake_flags "$slice"
    run_logged "$name-$slice" cmake -S "$src" -B "$prefix.build" "${SLICE_CMAKE_FLAGS[@]}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" "$@"
    run_logged "$name-$slice" cmake --build "$prefix.build" --parallel "$JOBS" --target install
}

# Sets OPENSSL_CMAKE_FLAGS so cmake picks up the OpenSSL built for a slice
# instead of anything installed on the machine.
openssl_cmake_flags() {
    local prefix=$OUT/openssl/$1
    OPENSSL_CMAKE_FLAGS=(
        "-DOPENSSL_ROOT_DIR=$prefix"
        "-DOPENSSL_INCLUDE_DIR=$prefix/include"
        "-DOPENSSL_CRYPTO_LIBRARY=$prefix/lib/libcrypto.a"
        "-DOPENSSL_SSL_LIBRARY=$prefix/lib/libssl.a"
    )
}

# Bundles one static library from every slice into dist/<name>.xcframework
# and zips it for the release.
#   make_xcframework <name> <build dir name> <static lib file> <headers: yes|no>
make_xcframework() {
    local name=$1 dir=$2 lib=$3 headers=$4 slice
    local args=()
    for slice in $SLICES; do
        args+=(-library "$OUT/$dir/$slice/lib/$lib")
        if [ "$headers" = yes ]; then
            args+=(-headers "$OUT/$dir/$slice/include")
        fi
    done
    mkdir -p "$DIST"
    rm -rf "$DIST/$name.xcframework" "$DIST/$name.zip" "$LOGS/$name-xcframework.log"
    run_logged "$name-xcframework" xcodebuild -create-xcframework "${args[@]}" -output "$DIST/$name.xcframework"
    (cd "$DIST" && zip -qr "$name.zip" "$name.xcframework")
    log "wrote $DIST/$name.zip"
}
