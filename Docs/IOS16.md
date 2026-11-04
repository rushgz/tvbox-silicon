# iOS 16 adaptation

Build the `ios16-port` branch using **Actions → iOS IPA → Run workflow**.
The version follows upstream's `project.yml`; the deployment target stays at iOS 16.0.

Each successful workflow run publishes a GitHub Release, whether the IPA is signed or unsigned.
The asset is named `<version>-adapt-ios16.ipa` (for example, `1.8.8-adapt-ios16.ipa`).
The version and build number come from the archived app, and the publisher checks that the IPA
matches that archive. Each new run has its own release tag; retrying the same run replaces its
asset. Signing status is recorded in the release notes.

## Reusing the runtime and FFmpeg

Normally leave `runtime_url` empty. New builds on `ios16-port` automatically restore:

- The packaged native JVM: `apple-runtime-iphoneos-packaged-v1`.
- FFmpeg: a cache keyed by OS, architecture and its build script, with fallback to the existing
  `apple-ffmpeg-v1` cache. The FFmpeg script checks its recipe signature and rebuilds only when needed.

The small Java host (`host.jar`) is rebuilt from current sources and synced into the reused native
runtime. This includes upstream Java fixes without recompiling OpenJDK, Unicorn and the other native
libraries. The runtime job passes that refreshed package to the IPA job as an artifact from the same run.

GitHub caches have branch scope and can be evicted. The previously successful caches are on
`ios16-port`; another branch cannot automatically read caches created only on that branch. If the
cache is missing, the workflow builds the native runtime again. `runtime_url` is an optional way to
import an existing packaged runtime instead, or explicitly use a different package for a run. It can
be a public ZIP or a runtime artifact URL from this repository. An explicit URL takes precedence over
the cached package. Keep the field empty for ordinary rebuilds.

The heavy native cache is intentionally stable across app and Java-host changes. If a future upstream
update changes the native JVM/bindings themselves, bump its cache version or import a compatible
package rather than reusing an incompatible native binary.

## Validation

Use a real device SDK archive; a host SwiftPM build alone does not verify iOS API availability:

```sh
xcodegen generate
xcodebuild archive -project TVBox.xcodeproj -scheme TVBox-iOS \
  -destination 'generic/platform=iOS' -archivePath /tmp/TVBox-iOS16.xcarchive \
  -skipMacroValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
python3 -m unittest discover -s Tests -p test_ios_release.py
```
