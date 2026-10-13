# OpenSSL. Its build system handles one architecture at a time, so every
# architecture is configured with vendor/openssl-apple.conf and built on its
# own, then the architectures of a slice are merged with lipo.

# Configure targets (see vendor/openssl-apple.conf) making up a slice.
openssl_targets() {
    case $1 in
        ios)           echo "apple-ios-arm64" ;;
        ios-simulator) echo "apple-ios-simulator-x86_64 apple-ios-simulator-arm64" ;;
        maccatalyst)   echo "apple-maccatalyst-x86_64 apple-maccatalyst-arm64" ;;
        macos)         echo "apple-macos-x86_64 apple-macos-arm64" ;;
        *)             die "unknown slice: $1" ;;
    esac
}

# Builds one Configure target into build/spm/openssl/arch/<target>.
# Only the libraries and headers are built and installed.
openssl_build_arch() (
    local target=$1 prefix=$OUT/openssl/arch/$1
    rm -rf "$prefix" "$prefix.build"
    mkdir -p "$prefix.build"
    cd "$prefix.build"
    perl "$VENDOR/openssl/Configure" "$target" \
        --config="$VENDOR/openssl-apple.conf" --prefix="$prefix" --release \
        no-shared no-tests no-apps no-docs
    make -j"$JOBS" build_libs
    make install_dev
)

# Merges the architectures of a slice into build/spm/openssl/<slice>.
openssl_merge_slice() {
    local slice=$1 out=$OUT/openssl/$1 targets target lib inputs
    targets=$(openssl_targets "$slice")
    rm -rf "$out"
    mkdir -p "$out/lib"
    cp -R "$OUT/openssl/arch/${targets%% *}/include" "$out/include"
    for lib in libssl libcrypto; do
        inputs=()
        for target in $targets; do
            inputs+=("$OUT/openssl/arch/$target/lib/$lib.a")
        done
        lipo -create "${inputs[@]}" -output "$out/lib/$lib.a"
    done
}

build_openssl() {
    local slice target
    [ -f "$VENDOR/openssl/Configure" ] || die "vendor/openssl is empty; run: git submodule update --init"
    for slice in $SLICES; do
        if [ "$PACKAGE_ONLY" = 0 ]; then
            for target in $(openssl_targets "$slice"); do
                log "OpenSSL: $target"
                rm -f "$LOGS/openssl-$target.log"
                run_logged "openssl-$target" openssl_build_arch "$target"
            done
        fi
        openssl_merge_slice "$slice"
    done
    # Only libssl carries the headers: both libraries share include/openssl,
    # and SwiftPM rejects two binary targets installing the same header paths.
    make_xcframework libssl openssl libssl.a yes
    make_xcframework libcrypto openssl libcrypto.a no
}
