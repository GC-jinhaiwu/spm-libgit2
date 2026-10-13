# libssh2, linked against the OpenSSL slice built by openssl.sh.

build_libssh2() {
    local slice
    [ -f "$VENDOR/libssh2/CMakeLists.txt" ] || die "vendor/libssh2 is empty; run: git submodule update --init"
    if [ "$PACKAGE_ONLY" = 0 ]; then
        for slice in $SLICES; do
            log "libssh2: $slice"
            openssl_cmake_flags "$slice"
            cmake_build libssh2 "$slice" "$VENDOR/libssh2" "${OPENSSL_CMAKE_FLAGS[@]}" \
                -DBUILD_SHARED_LIBS=OFF \
                -DBUILD_STATIC_LIBS=ON \
                -DCRYPTO_BACKEND=OpenSSL \
                -DENABLE_ZLIB_COMPRESSION=OFF \
                -DBUILD_EXAMPLES=OFF \
                -DBUILD_TESTING=OFF
        done
    fi
    make_xcframework libssh2 libssh2 libssh2.a yes
}
