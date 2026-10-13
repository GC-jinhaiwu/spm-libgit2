Swift Package
=============

This branch turns libgit2 into a Swift package. Nothing is compiled on the
consumer's side: `Package.swift` declares four binary targets whose
XCFrameworks are attached to a GitHub release, and `script/spm` is the tool
chain that builds and publishes them.

| Target | Contents |
| ------ | -------- |
| `Clibgit2` | libgit2 from this branch, static, with a module map (`import Clibgit2`) |
| `libssh2` | SSH transport, linked against the bundled OpenSSL |
| `libssl`, `libcrypto` | OpenSSL 3; only `libssl` carries the headers |

Slices: iOS 13 (arm64), iOS Simulator (x86_64, arm64), Mac Catalyst 13.1
(x86_64, arm64), macOS 10.15 (x86_64, arm64).

Build options baked in: HTTPS via OpenSSL, SSH via libssh2 with in-memory
credentials, bundled zlib, threads, iconv. Tests, CLI, examples and the
system package config are left out.

Using the package
-----------------

```swift
// Package.swift of your project
dependencies: [
    .package(url: "https://github.com/GC-jinhaiwu/spm-libgit2", from: "1.9.7"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "libgit2", package: "spm-libgit2")]),
]
```

```swift
import Clibgit2

git_libgit2_init()
```

`Clibgit2.h` (the module header) pulls in `git2.h` and every `git2/sys/*.h`,
so the backend and transport APIs are available as well. Linking `iconv`
is handled by the module map; nothing else has to be added to the app.

### TLS trust store

The bundled OpenSSL cannot see the system keychain, so HTTPS fails with
"the SSL certificate is invalid" until libgit2 is pointed at a CA bundle.
`git_libgit2_opts` is variadic, which Swift cannot call, so route it through
a small C target of your own:

```c
// Sources/GitSupport/include/GitSupport.h
int git_support_set_ca_bundle(const char *file, const char *directory);

// Sources/GitSupport/GitSupport.c
#include "GitSupport.h"
#include <git2.h>

int git_support_set_ca_bundle(const char *file, const char *directory) {
    return git_libgit2_opts(GIT_OPT_SET_SSL_CERT_LOCATIONS, file, directory);
}
```

```swift
git_libgit2_init()
git_support_set_ca_bundle("/etc/ssl/cert.pem", nil)   // macOS system bundle
```

iOS ships no PEM bundle. Either add one to the app (Mozilla's `cacert.pem`,
for example) and pass its path, or verify the server certificate yourself
in `git_fetch_options.callbacks.certificate_check` with `SecTrust` and
return 0 from the callback.

What lives where
----------------

| Path | Role |
| ---- | ---- |
| `Package.swift` | Written by `script/spm/build.sh manifest`. Never edited by hand. |
| `script/spm/build.sh` | Entry point: `openssl`, `libssh2`, `libgit2`, `all`, `manifest <tag>`. |
| `script/spm/lib/` | One file per library plus `env.sh` (slices, cmake and XCFramework helpers). |
| `vendor/openssl`, `vendor/libssh2` | Shallow submodules; the checked-out commit is the version. |
| `vendor/openssl-apple.conf` | OpenSSL `Configure` targets for the Apple slices. |
| `.github/workflows/swift-package.yml` | Manual release workflow. |
| `build/spm/` | Build output (ignored): `<lib>/<slice>` installs, `dist/` zips, `logs/`. |

Publishing a release
--------------------

1. Put the branch in the state you want to ship. The default tag is the
   `LIBGIT2_VERSION` of `include/git2/version.h` (currently `1.9.7`); the
   upstream `v1.9.7` tag stays untouched. To move a dependency:

   ```bash
   git -C vendor/openssl fetch --depth 1 origin tag openssl-3.5.9
   git -C vendor/openssl checkout openssl-3.5.9
   git add vendor/openssl && git commit -m "spm: openssl 3.5.9"
   ```

2. GitHub → Actions → **Swift Package** → Run workflow on this branch.
   Leave `version` empty, or set it when the same libgit2 version has to be
   rebuilt (for example `1.9.7-1`; consumers then pin it with `exact:`).
   A tag that already exists stops the run before anything is built.

3. The run builds the four zips, commits the regenerated `Package.swift`,
   tags that commit, pushes both and creates the release with the zips.
   Pull the branch afterwards.

If the run stops before the push, nothing has changed on GitHub. If it
stops at the last step, the commit and tag exist but the release does not:
create the release by hand from the `xcframeworks` artifact of the run (the
checksums in the committed `Package.swift` match those zips), or delete the
tag and the commit and rerun.

Building locally
----------------

Needs Xcode, `cmake` and `perl`. OpenSSL is built seven times, so expect
15 minutes or more.

```bash
git submodule update --init
script/spm/build.sh all                 # or one of: openssl, libssh2, libgit2
script/spm/build.sh manifest 1.9.7      # rewrites Package.swift
```

`--package-only` skips compiling and only re-creates the XCFrameworks from
the previous `build/spm` output, which makes iterating on the packaging
cheap.

To publish a local build instead of running the workflow, keep the zips and
the manifest from the same build:

```bash
gh release create 1.9.7 --title 1.9.7 build/spm/dist/{Clibgit2,libssh2,libssl,libcrypto}.zip
git add Package.swift && git commit -m "spm: release 1.9.7"
git tag 1.9.7 && git push origin HEAD 1.9.7
```
