# Physical iPhone Support Implementation Report

Measured on 2026-07-26 in Asia/Shanghai.

## Supported platform scope

The repository targets:

- macOS arm64;
- physical iPhone arm64 with an iOS 13.0 deployment target.

iOS Simulator is intentionally unsupported. The build hook reports a clear
error when Flutter requests that SDK.

## Native toolchain

The iPhoneOS toolchain is isolated below ignored `_build/ios` paths and pins:

- OCaml 5.3.0;
- `ocaml-ios64.5.3.0`;
- opam-cross-ios commit `8380b52b0154752c26c6e221c04fbced3320aa48`;
- Bonsai and Core `v0.18~preview.130.106+341`;
- iPhoneOS arm64 at minimum iOS 13.0.

The exact runtime closure is recorded in
`vendor/opam-ios/runtime-closure.lock`. Host PPX executables remain macOS
processes while target runtime libraries compile for iPhoneOS.

## Artifact packaging

All standalone examples and the aggregate integration application produce
target-qualified complete objects. The build hook:

1. selects the macOS or iPhoneOS object;
2. validates architecture, platform, SDK, minimum version, and Bitcode;
3. links the complete object into the generated native framework;
4. exports only the public `bf_*` ABI; and
5. lets Flutter embed and sign the framework.

Unsigned iPhoneOS Debug, Profile, and Release bundles pass the repository
artifact audit.

## Physical iPhone evidence

The connected iPhone passed:

- physical-device selection;
- pairing and trust checks;
- boot and unlock checks;
- Developer Mode and developer-disk-image checks;
- Development certificate validation;
- development provisioning-profile Team, bundle, and device checks;
- Development-signed build and installation.

A Development-signed application can be installed and launched from Xcode or
the Flutter command line. Distribution signing was not configured because the
current Apple team role cannot create an Apple Distribution certificate and
the requested scope is Development testing.

The Flutter integration-test host currently disconnects from its local
WebSocket after installation. This occurs after signing and installation and
is tracked as a separate runtime-test issue.

## Commands

```sh
make ci-contract
make ios-device-native-objects
make ci-ios
```

Run an example on a registered iPhone with a repository-external signing
configuration:

```sh
XCODE_XCCONFIG_FILE=<development-signing.xcconfig> \
  flutter run --debug -d <physical-device-id>
```

Use `--release` for an AOT Release build that is still Development-signed for
the registered device.

## Remaining boundary

The current evidence does not claim:

- Ad Hoc, TestFlight, or App Store distribution;
- distribution-signed Release IPA export;
- support for untested device or OS versions;
- a passing automated Flutter integration-test connection on the device.
