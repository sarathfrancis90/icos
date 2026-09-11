fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios sync_certs

```sh
[bundle exec] fastlane ios sync_certs
```

Sync App Store certificates and profiles via match (read-only on CI)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build the Flutter app and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit an existing TestFlight build for App Store review (metadata from fastlane/metadata)

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload App Store metadata and screenshots (no binary, no submission)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
