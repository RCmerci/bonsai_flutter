# iOS Device Testing

This document describes the repository's physical-device gate. Development
signing, installation, and launch have been verified on a physical iPhone.
Distribution-signed Release export is outside the current support boundary.

## Prerequisites

Use the pinned Flutter 3.44.8, Dart 3.12.2, OCaml 5.1.1, and Xcode toolchains.
The Mac must have an arm64 physical iPhone that is:

- explicitly selected by CoreDevice identifier;
- paired and trusted;
- booted and connected;
- running with Developer Mode enabled;
- currently unlocked and already unlocked at least once since boot.

The Apple Developer account must provide:

- one Team ID;
- one unique application bundle identifier;
- a development certificate and profile for the selected device;
- a distribution certificate and distribution profile;
- export options appropriate for the distribution method;
- certificates and profiles with at least 30 days remaining.

The development profile must allow debugging. The distribution profile must
not allow debugging. Both profiles must cover the bundle identifier and
selected device. Keep all identifiers, certificates, profiles, passwords,
private keys, and account details outside the repository and command output.

## Local preflight

Verify hardware state without inspecting signing material:

```sh
tool/ci/ios_device_preflight.sh <physical-device-id>
```

The full signed lane receives these non-secret configuration variables:

```text
IOS_DEVICE_ID
IOS_DEVELOPMENT_TEAM
IOS_BUNDLE_IDENTIFIER
IOS_DEVELOPMENT_PROFILE_SPECIFIER
IOS_DISTRIBUTION_PROFILE_SPECIFIER
```

It also receives these secret inputs:

```text
IOS_KEYCHAIN_PASSWORD
IOS_DEVELOPMENT_CERTIFICATE_P12_BASE64
IOS_DEVELOPMENT_CERTIFICATE_PASSWORD
IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64
IOS_DISTRIBUTION_CERTIFICATE_PASSWORD
IOS_DEVELOPMENT_PROFILE_BASE64
IOS_DISTRIBUTION_PROFILE_BASE64
IOS_EXPORT_OPTIONS_PLIST_BASE64
```

`tool/ci/install_ios_signing.sh` decodes those values into an ignored,
temporary directory, creates an ephemeral keychain, installs the profiles,
validates the material, and emits only paths and non-secret configuration to
the following step. Its cleanup mode removes the temporary keychain and
profiles and restores the original keychain search list.

Never place a secret directly in a workflow file, repository variable,
checked-in `.xcconfig`, Xcode project, or shell history.

## Canonical command

After installing and exporting the validated signing environment:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

The command is deliberately all-or-nothing. It:

1. reproduces and audits the iPhoneOS OCaml object closure;
2. confirms the explicit device and signing prerequisites;
3. runs the real FFI integration application in Debug;
4. verifies Debug hot restart;
5. runs signed Profile and Release XCTest bundles;
6. archives and exports Release;
7. audits the app, framework, signatures, entitlements, provisioning profile,
   Team ID, App ID, public exports, and target metadata;
8. installs and cold-launches the exported application.

The CI workflow uses a protected environment, one repository-scoped runner,
and global concurrency so two jobs cannot share the phone. It is not triggered
by `pull_request` or `pull_request_target`.

## Failure diagnosis

- An absent or ambiguous target means `IOS_DEVICE_ID` does not resolve to
  exactly one connected Flutter device.
- An emulator result is rejected even if it has an iOS target platform.
- Pairing, trust, Developer Mode, boot, or unlock failures must be corrected
  on the phone and host before rerunning. Keep the phone unlocked while the
  signed application launches.
- A Team, App ID, device-list, `get-task-allow`, or expiry error means the
  supplied profile does not match the lane.
- A certificate error means the imported identity is absent, expired, or has
  less than 30 days remaining.
- A Mach-O error means the wrong target object, SDK kind, architecture, or
  deployment target reached the build. Do not relabel the object or lower only
  the final link target.
- An iOS Simulator target is unsupported. Select the registered physical
  iPhone explicitly.

## Current measured boundary

One attached physical iPhone passed the hardware preflight and a signed
development Eio Worker probe. The probe validates arm64 iPhoneOS execution,
DNS, loopback TCP, bounded file I/O, structural cancellation, reuse, cleanup,
and a real background-to-foreground transition. Device identifiers and signing
material are intentionally not recorded in this document.

A Development-signed Profile DataScript Worker application also passed the
physical-iPhone persistence slice. The application resolved its pinned target
closure, linked the iPhoneOS system SQLite library, opened app-private storage
through `Datascript_sqlite`, persisted one typed fact, disposed the Worker and
host runtime, relaunched, and restored the same fact. Profile mode is required
because the canonical test cold-launches the signed application with
`devicectl`; a Debug Flutter application requires a Flutter tooling or Xcode
debug session instead.

Unsigned iPhoneOS arm64 application builds and final framework audits also
pass. The complete canonical lane has not yet been run with the Flutter FFI
application, so device-side Flutter integration, hot restart, signed Profile
and Release XCTest, Release export, and distribution signing remain unproven.

App Store distribution and TestFlight are outside the support claim until an
authorized validation lane completes.
