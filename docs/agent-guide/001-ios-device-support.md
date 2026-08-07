# Physical iPhone Support Implementation Plan

Goal: Support macOS arm64 and physical iPhone arm64 without weakening the
OCaml-first architecture or changing the locked language stack.

Architecture: Build a complete OCaml application object independently for
macOS and iPhoneOS, then let Flutter 3.44.8 package the selected object as a
bundled dynamic framework through the existing `package_ffi` build hook.

Supported execution targets:

| Target | Architecture | Native artifact |
| --- | --- | --- |
| macOS 26.0+ | arm64 | `macos/arm64/native_embed.exe.o` |
| Physical iPhone, iOS 15.0+ | arm64 | `ios/iphoneos/arm64/native_embed.exe.o` |

iOS Simulator, Intel Mac, and universal macOS builds are intentionally
unsupported. The native build hook must fail before artifact resolution when
Flutter selects an unsupported Apple target.

## Constraints

- Keep OCaml at exactly 5.3.0.
- Keep Bonsai and Core at exactly `v0.18~preview.130.106+341`.
- Keep Flutter at 3.44.8 and Dart at 3.12.2.
- Keep OCaml and Bonsai as the owners of application state and behavior.
- Keep the batched C ABI and generated `@Native` bindings.
- Keep Flutter's `DynamicLoadingBundled` packaging path.
- Preserve all existing macOS behavior and gates.
- Build every iPhoneOS dependency from source for iOS 15.0.
- Never reuse a macOS object for iPhoneOS.
- Keep signing identities, profiles, private keys, and passwords outside the
  repository.

## Required implementation

1. Pin the iPhoneOS cross compiler and exact target dependency closure.
2. Build and verify a minimal arm64 iPhoneOS probe.
3. Build every standalone example and the aggregate integration object for
   iPhoneOS.
4. Stage target-qualified macOS and iPhoneOS complete objects.
5. Make the native build hook select only those two artifact shapes.
6. Reject unsupported SDKs, missing objects, wrong Mach-O platforms, wrong
   architectures, inconsistent minimum versions, and Bitcode.
7. Generate standard Flutter iOS Runners without application logic.
8. Audit unsigned Debug, Profile, and Release iPhoneOS bundles.
9. Verify Development signing, installation, and launch on an explicitly
   selected physical iPhone.
10. Keep distribution signing and App Store delivery outside the support claim
    until separately authorized and verified.

## Verification

Run the repository contracts and host regressions:

```sh
make ci-contract
make ci-ocaml
make ci-flutter
make ci-sanitizers
make ci-macos
```

Build and audit iPhoneOS artifacts:

```sh
make ios-toolchains
make ios-cross-probes
make ios-device-native-objects
make ci-ios
```

For local Development-signed device execution:

```sh
flutter run --debug -d <physical-device-id>
flutter run --release -d <physical-device-id>
```

The device must be paired, trusted, unlocked, registered in the development
profile, and running with Developer Mode enabled.

## Completion boundary

The repository may claim physical iPhone Development support only when:

- a clean checkout reproduces the iPhoneOS object closure;
- the final embedded framework contains the real OCaml backend;
- Development signing installs and launches the app on a registered iPhone;
- the macOS arm64 gate remains green; and
- documentation records the exact measured environment without extrapolating
  to untested devices or distribution methods.
