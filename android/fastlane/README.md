fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android internal

```sh
[bundle exec] fastlane android internal
```

Upload the release AAB to the Internal testing track

### android beta

```sh
[bundle exec] fastlane android beta
```

Upload the release AAB to the Closed testing (beta) track

### android production

```sh
[bundle exec] fastlane android production
```

Upload the release AAB directly to Production

### android promote_to_production

```sh
[bundle exec] fastlane android promote_to_production
```

Promote the current Internal build to Production (no rebuild). Pass from:beta to promote from Closed testing.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
