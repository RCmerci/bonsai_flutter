# Consumer-Style Example Builds Implementation Plan

Goal: Convert every repository example and the aggregate integration harness into consumer workspaces that build through the public `bonsai-flutter` workflow used by external applications.

Architecture: Each example will own an independent Dune and opam project, a `bonsai-flutter.sexp` file, and a Flutter host whose native artifacts are built and selected only by `bonsai-flutter`.
The tool will support both generated managed hosts and consumer-owned custom hosts while preserving consumer-owned pubspec content.
Repository CI will exercise those public commands and will remove the obsolete manual native-object staging paths.

Tech Stack: OCaml 5.1, Dune, opam lock files, Cmdliner, Flutter, Dart Native Assets hooks, Xcode, shell contract tests, and GitHub Actions.

Related: Builds on [014-ocaml-first-tooling.md](014-ocaml-first-tooling.md) and [015-build-architecture.md](015-build-architecture.md).

## Problem statement

The repository examples currently look like applications, but they do not build like external `bonsai_flutter` consumers.

They share the repository's root Dune workspace, reference framework Flutter packages through repository-relative paths, configure a manually staged `_build/native-artifacts` directory, and invoke `flutter` directly from `Makefile` and shell scripts.

Those paths bypass the `bonsai-flutter` profile wrapper that builds the correct OCaml complete object, injects `native_artifact_profile`, invokes Flutter, and restores the original pubspec.

The bypass causes `native_artifact_profile` to be `null` in direct example and integration tests.

The direct iOS native-object script also assumes `SDK_OPAM_SWITCH`, while the public tool owns the fixed `bonsai-flutter-ios` switch and should make that repository-specific environment variable unnecessary.

The migration is structural rather than a command substitution because advanced examples own Dart behavior that the current managed adapter cannot express.

The current host synchronizer also regenerates the whole pubspec, which would erase consumer dependencies such as `path_provider` when a custom application uses `bonsai-flutter exec`.

The target state must therefore establish independent consumer roots, explicit host ownership, mixed-ownership pubspec updates, and CI that invokes only the public tool workflow.

## Testing Plan

I will use @Test-Driven Development (TDD) for every implementation task and will add behavior tests before changing production code or build wiring.

I will add `bonsai_flutter_tool` tests that parse the new configuration language, reject obsolete configuration, distinguish managed and custom host ownership, and preserve consumer-authored Flutter files.

I will add temporary-workspace tests that execute `sync-host` and `exec` against realistic pubspecs with extra dependencies, comments, CRLF input, malformed managed regions, successful child commands, failing child commands, and interrupted child commands.

I will add scaffold tests proving that `init --adopt` records an existing layout without creating the default `app/` tree.

I will extend repository contract tests so every example is verified as an independent consumer root with a config file, Dune project, opam manifest, committed lock, standard native aliases, and no repository-relative native artifact root.

I will add a consumer canary that builds Counter from its own root using the locally built `bonsai-flutter` executable before migrating the remaining examples.

I will add profile tests that invoke each example through `bonsai-flutter exec --profile=debug -- flutter test --no-pub` and prove that direct `flutter test` is absent from the supported CI path.

I will retain behavior-level host tests for Gallery registry configuration, Network runtime injection, SQLite application-support bootstrapping, and integration FFI loading under the custom-host mode.

I will add macOS and unsigned iOS matrix tests that invoke `bonsai-flutter build`, inspect the staged artifact manifest, and verify the final bundle architecture and deployment target.

I will keep the physical-device lane behind its existing signing preflight and will invoke the application through the public tool once `IOS_DEVELOPMENT_TEAM` and device identity are available.

I will run the complete OCaml, Dart, Flutter, macOS, iOS, formatting, repository contract, and snapshot-lock suites after the obsolete staging paths are deleted.

NOTE: I will write *all* tests before I add any implementation behavior.

## Research findings

### Current tool behavior

`bonsai_flutter_tool/lib/config.ml` accepts one application with one native target and only the `managed_adapter` host mode.

`bonsai_flutter_tool/lib/scaffold.ml` generates a default application, Dune rules, project files, opam metadata, a lock, configuration, and standard platform aliases.

The current `init --adopt` path still runs the fresh-project initializer and can create an unwanted default `app/` tree in an existing non-default layout.

`bonsai_flutter_tool/lib/host.ml` generates the entire Flutter pubspec and temporarily writes `native_artifact_profile` around a child command.

This whole-file ownership prevents examples with consumer-specific Dart dependencies from safely using `exec`.

`bonsai_flutter_tool/lib/build_system.ml` already owns the correct native build, profile selection, profile injection, Flutter invocation, and exact pubspec restoration behavior.

`bonsai_flutter_tool/lib/plan.ml` already isolates build products by platform, SDK fingerprint, and profile below the consumer project.

`bonsai_flutter_tool/lib/assets.ml` can synchronize Flutter packages into a project-local `.bonsai-flutter/flutter-packages` directory.

The missing capability is therefore a supported consumer-host ownership contract, not another repository staging script.

### Current repository behavior

The repository contains eleven examples under `/Users/rcmerci/gh-repos/bonsai_flutter/examples`.

None currently owns `bonsai-flutter.sexp`, a nested `dune-project`, or a per-example opam lock.

All Flutter pubspecs point at framework packages through paths such as `../../../flutter/packages/...` and point native hooks at `../../../_build/native-artifacts/<example>/`.

`/Users/rcmerci/gh-repos/bonsai_flutter/Makefile` directly loops over `flutter analyze`, `flutter test`, and platform builds.

`/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test` is an aggregate internal harness with its own OCaml target, but it also invokes Flutter without the profile wrapper.

The harness imports the SQLite example's Flutter project for bootstrap behavior, which couples one application's host implementation to the aggregate runner.

Mail defines separate debug and release native targets and depends on private tracing libraries, so it is not currently representative of an external consumer.

The iOS repository snapshot lock currently records a digest that differs from the deterministic digest of the committed snapshot contents.

That snapshot mismatch is an adjacent pre-existing test blocker and must be audited before its lock is updated.

### Example migration inventory

| Consumer | Native feature set | Target host mode | Special migration work |
|---|---|---|---|
| Clock | Core | Managed | Replace repository-relative packages and artifact root. |
| Counter | Core | Managed | Use as the first end-to-end consumer canary. |
| Gallery | Core | Custom | Preserve its custom `NativeWidgetRegistry`. |
| Host Effects | Core | Managed | Preserve entrypoint and title configuration. |
| Host Navigation | Core | Managed | Preserve entrypoint and title configuration. |
| Mail | Core | Managed | Collapse debug and release targets and move private tracing coverage out of the public example. |
| Navigation | Core | Managed | Preserve entrypoint and title configuration. |
| Network | Network | Custom | Preserve injectable runtime startup and loading and error UI. |
| SQLite Worker | SQLite | Custom | Preserve `path_provider`, asynchronous payload creation, and bootstrap behavior. |
| Text Input | Core | Managed | Replace repository-relative packages and artifact root. |
| Todo | Core | Managed | Preserve entrypoint and title configuration. |
| Integration Harness | Core, Network, and SQLite test fixtures | Custom | Become an independent internal consumer and stop importing an example Flutter application. |

## Target architecture

The public build path will be identical for an external application, a repository example, and the internal integration harness.

```text
example or integration consumer root
│
├── dune-project + package.opam + package.opam.locked
├── bonsai-flutter.sexp
├── ocaml/
│   ├── application library
│   ├── native_embed executable
│   └── bonsai-flutter-macos / bonsai-flutter-ios aliases
└── flutter/
    ├── consumer-owned pubspec with tool-owned marker regions
    ├── managed generated host or custom consumer host
    └── platform projects
          │
          ▼
    bonsai-flutter exec/build/run
          │
          ├── validate consumer project and feature closure
          ├── build the profile-specific OCaml complete object with Dune
          ├── stage a project-local artifact and manifest
          ├── inject the selected profile into the managed pubspec region
          ├── invoke Flutter or Xcode
          └── restore the exact original pubspec bytes
```

### Consumer roots

Each directory under `/Users/rcmerci/gh-repos/bonsai_flutter/examples` will become an independent consumer root without renaming its existing `ocaml/` and `flutter/` directories.

Each root will add `dune-project`, one package opam manifest, one committed `.opam.locked` file, `.ocamlformat`, and `bonsai-flutter.sexp`.

The package identities will follow the existing application library identities so the migration does not introduce unrelated renames.

| Consumer root | Package identity |
|---|---|
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/clock` | `bonsai_flutter_clock_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter` | `bonsai_flutter_counter_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery` | `bonsai_flutter_gallery`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/host_effects` | `bonsai_flutter_host_effects_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/host_navigation` | `bonsai_flutter_host_navigation_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail` | `bonsai_flutter_mail_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/navigation` | `bonsai_flutter_navigation_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network` | `bonsai_flutter_network_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker` | `bonsai_flutter_sqlite_worker_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/text_input` | `bonsai_flutter_text_input_example`. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/todo` | `bonsai_flutter_todo_example`. |

For each row, the exact metadata paths are `<consumer-root>/dune-project`, `<consumer-root>/.ocamlformat`, `<consumer-root>/bonsai-flutter.sexp`, `<consumer-root>/<package-identity>.opam`, and `<consumer-root>/<package-identity>.opam.locked`.

Each config will use `ocaml/native_embed.exe.o` as its single native target.

The network config will declare the `network` feature and the SQLite config will declare the `sqlite` feature.

All other example configs will use the core feature set.

Each native target directory will define the standard `bonsai-flutter-macos` and `bonsai-flutter-ios` dependency aliases generated by the tool.

The first canary must prove that a nested Dune project builds correctly both from its own root and when the repository root runs aggregate checks.

If nested project discovery creates ambiguous package ownership, the migration must stop and choose explicit installed-package boundaries rather than adding root-relative fallbacks.

### Host ownership modes

Configuration language version 2 will replace the version 1 host model without a compatibility parser.

`managed_adapter` will mean that the tool owns the mechanical Dart entrypoint and host widget tests.

`custom` will mean that the consumer owns `flutter/lib/main.dart` and its Dart tests while the tool still owns native artifact production, profile injection, package synchronization, validation, and Flutter invocation.

Custom mode will validate required files and marker regions but will never overwrite consumer-owned Dart source.

Managed mode will continue to generate deterministic Dart source from the configured adapter.

The tool will fail with a focused diagnostic if configuration selects custom mode but the required entrypoint is missing.

The tool will fail if managed mode encounters an edited generated file whose generated-content marker no longer matches.

| Host field | Managed mode | Custom mode |
|---|---|---|
| `mode` | Must be `managed_adapter`. | Must be `custom`. |
| `adapter` | Required application-owned adapter path relative to the Flutter root. | Forbidden. |
| `entrypoint` | Required registered native entrypoint name. | Forbidden because the custom Dart host selects its registered entrypoint. |
| `launch_policy` | Required generated-host launch policy. | Forbidden because the custom Dart host owns launch behavior. |
| `main` | Forbidden. | Required consumer-owned Dart entrypoint path relative to the Flutter root. |

Unknown or mode-inappropriate fields will be rejected so ownership cannot be inferred from partially compatible configuration.

### Pubspec ownership

The consumer will own package metadata, SDK constraints, direct Dart dependencies, dev dependencies, Flutter settings, and platform declarations.

The tool will own only delimited sections for synchronized local package paths and `hooks.user_defines.bonsai_flutter_native` values.

The marker identities will be stable names such as `bonsai-flutter:begin packages`, `bonsai-flutter:end packages`, `bonsai-flutter:begin native-hook`, and `bonsai-flutter:end native-hook` in YAML comment lines.

The package region will contain only tool-synchronized Bonsai Flutter path dependencies, while the native-hook region will contain the artifact root, target platform metadata, and the temporary profile selector.

`sync-host` will update those delimited sections atomically and will preserve all content outside them byte-for-byte where possible.

`exec` will change only `native_artifact_profile` inside the tool-owned hook section and will restore the exact original pubspec bytes after success, child failure, or interruption.

Missing, duplicated, nested, or malformed marker regions will be hard errors.

The implementation will not fall back to whole-file regeneration and will not accept an unmarked version 1 pubspec.

### OCaml package boundaries

Example application libraries needed by the integration harness will receive explicit package ownership and public names.

The integration project will depend on installed example packages or on test fixtures it owns directly rather than reaching through a sibling project's private Dune library.

The migration will first enumerate which example libraries are genuine reusable fixtures and which tests should move into their owning example.

Only reusable integration fixtures will become public packages because publishing every example-internal library would create unnecessary API surface.

The root `bonsai_flutter_network_example` package declaration and opam file will move into `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network` once no root target owns that package.

### Mail ownership

Mail will expose one `ocaml/native_embed.exe.o` target for every profile.

Profile differences will be expressed through the tool's build profile and Flutter build mode rather than separate Dune target names.

Private `bonsai_flutter_trace_debug` and `bonsai_flutter_trace_release` dependencies will be removed from the external-consumer example.

Tracing behavior that still needs coverage will move to an internal runtime test fixture or the integration harness.

No compatibility aliases will retain the old Mail target names.

### Integration harness ownership

The aggregate harness will become a real consumer root with the same required project files and public command path as the examples.

Its target location will remain `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test` during the first canary to avoid unrelated platform-project churn.

If placing `dune-project` beside the existing Flutter root prevents the desired `ocaml/` and `flutter/` ownership model, the harness will move to `/Users/rcmerci/gh-repos/bonsai_flutter/integration_test` with `ocaml/` and `flutter/` children in one atomic task.

The harness will use custom host mode because it intentionally composes multiple native entrypoints and test-only UI behavior.

Reusable SQLite bootstrap code will move to an application-neutral support library owned by the integration harness or a shared package.

The harness pubspec will stop path-depending on `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker/flutter`.

### CI ownership

Repository convenience targets may orchestrate a matrix, but every application command inside the matrix must invoke the public `bonsai-flutter` CLI.

The locally built executable will be used through an explicit variable so CI tests the current source without relying on an older globally installed binary.

The command surface will remain consumer-shaped, such as `bonsai-flutter exec --profile=debug -- flutter test --no-pub` and `bonsai-flutter build macos --profile=release`.

The implementation must not set `native_artifact_profile`, stage native complete objects, or set `SDK_OPAM_SWITCH` outside the tool.

Once all lanes use the tool, obsolete repository staging targets and scripts will be deleted rather than retained as fallbacks.

### Standard consumer command matrix

Each example will document and exercise the same commands an external consumer runs from its Flutter directory.

| Intent | Public command |
|---|---|
| Validate synchronized host files | `bonsai-flutter sync-host --check`. |
| Analyze consumer Dart code | `bonsai-flutter exec --profile=debug -- flutter analyze`. |
| Run consumer Flutter tests | `bonsai-flutter exec --profile=debug -- flutter test --no-pub`. |
| Build a macOS debug application | `bonsai-flutter build macos --profile debug`. |
| Build a macOS release application | `bonsai-flutter build macos --profile release`. |
| Build an unsigned iOS application | `bonsai-flutter build ios --profile release --no-codesign`. |
| Run on a connected iPhone | `bonsai-flutter run ios --profile debug --device <device-id>`. |

Repository CI may select a subset of platform builds per example according to feature coverage, but it may not replace these commands with direct native staging.

### Alternatives considered

Wrapping the existing raw Flutter loops without creating consumer roots was rejected because it would continue testing the repository workspace instead of the installed-package model.

Adding every advanced host callback to `BonsaiFlutterHostAdapter` was rejected because registry construction, asynchronous platform bootstrapping, and test runtime injection are application composition concerns rather than a stable generated-host contract.

Regenerating the complete pubspec and adding an allowlist of extra dependencies was rejected because it would keep the tool as the owner of consumer package metadata and would lose arbitrary valid settings.

Keeping one repository-level `bonsai-flutter.sexp` for all examples was rejected because the public configuration intentionally models one application and one native target.

Keeping manual staging as a fallback was rejected because it would preserve the path that caused profile and toolchain divergence.

## File ownership matrix

| Path | Planned responsibility |
|---|---|
| `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/config.ml` | Parse version 2 managed and custom host configuration. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/scaffold.ml` | Separate fresh initialization from adoption and create marker-aware hosts. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/host.ml` | Synchronize owned regions and preserve consumer files. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/build_system.ml` | Apply profile-scoped execution and robust restoration. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/test/tool_tests.ml` | Cover configuration, adoption, host ownership, restoration, and command behavior. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/examples/*` | Own independent consumer projects and example-specific host behavior. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test` | Own aggregate consumer configuration and integration-only fixtures. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/Makefile` | Orchestrate tool-based consumer matrices only. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_ci_contract.sh` | Enforce the public command path and absence of obsolete staging. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_network_ios_contract.sh` | Enforce Network feature and iOS consumer behavior. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/docs/testing.md` | Document local and CI consumer commands. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/docs/packaging.md` | Document project-local package and artifact ownership. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/docs/architecture.md` | Document managed versus custom host boundaries. |

## Scope and non-goals

This plan migrates repository applications to the already intended public build architecture and fills the minimum missing tool capabilities needed by real consumers.

This plan does not add Android, Linux, Windows, or iOS Simulator support.

This plan does not make signing credentials part of `bonsai-flutter.sexp`.

This plan does not preserve version 1 configuration, whole-pubspec generation, old Mail targets, or manual staging entrypoints.

This plan does not publish application-specific libraries unless the integration harness has a demonstrated reusable dependency on them.

This plan does not hide the repository snapshot digest mismatch with a skipped test.

## Implementation plan

### Task 1: Lock the failing baseline in repository contracts

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_ci_contract.sh`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_network_ios_contract.sh`.

Steps:

1. Add failing assertions that every example has the required consumer-root files and has no `native_artifact_root` pointing at the repository root.
2. Add failing assertions that supported Make targets call `bonsai-flutter exec`, `bonsai-flutter build`, or `bonsai-flutter run` and do not call native-object staging scripts.
3. Add a failing assertion that Network declares the public `network` feature in its consumer config.
4. Run `bash tool/test_ci_contract.sh` and confirm the new assertions fail on the current layout.
5. Run `bash tool/test_network_ios_contract.sh` and confirm the feature assertion fails on the current layout.
6. Commit the red contract tests as `dev(ci): define consumer-style example contracts` only if the project permits test-only red commits.

### Task 2: Define configuration language version 2

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/config.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/test/tool_tests.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/docs/packaging.md`.

Steps:

1. Write tests that parse a version 2 managed host and expose its adapter metadata.
2. Write tests that parse a version 2 custom host and expose its consumer-owned entrypoint path.
3. Write tests that reject version 1, multiple host modes, absolute paths, parent traversal, and a missing custom entrypoint declaration.
4. Run `dune exec bonsai_flutter_tool/test/tool_tests.exe` and confirm the version 2 cases fail.
5. Implement the minimal version 2 configuration model with an explicit managed-or-custom variant.
6. Run `dune exec bonsai_flutter_tool/test/tool_tests.exe` and confirm all configuration tests pass.
7. Update the configuration reference without documenting a version 1 fallback.
8. Commit as `feat(tool): define custom host ownership`.

### Task 3: Separate fresh initialization from adoption

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/scaffold.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/test/tool_tests.ml`.

Steps:

1. Write a temporary-workspace test that creates existing `ocaml/` and `flutter/` trees and runs the adoption path.
2. Assert that adoption writes only missing project metadata and never creates `/app/application.ml` or `/app/native_embed.ml`.
3. Write tests for conflict diagnostics when adoption would overwrite an existing config or incompatible Dune alias.
4. Run the tool tests and confirm the adoption tests fail.
5. Split fresh initialization and adoption into distinct code paths.
6. Make adoption validate the configured native target before adding project metadata.
7. Run the tool tests and confirm all adoption behaviors pass.
8. Commit as `fix(tool): make project adoption non-destructive`.

### Task 4: Implement mixed-ownership pubspec synchronization

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/host.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/build_system.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/test/tool_tests.ml`.

Steps:

1. Write tests that synchronize tool-owned marker regions while preserving consumer dependencies, comments, ordering, and unrelated hook values.
2. Write tests that reject missing, duplicated, nested, reversed, and partially written marker regions.
3. Write tests that inject debug and release profiles only inside the native hook region.
4. Write tests that compare original and restored pubspec bytes after child success, child nonzero exit, and an interrupt signal.
5. Write a CRLF fixture and prove synchronization preserves its line-ending convention.
6. Run the tool tests and confirm every new behavior fails against whole-file generation.
7. Implement a marker-region parser and atomic replacement primitive without introducing a general YAML reserializer.
8. Update `sync-host` to edit only tool-owned regions.
9. Update `exec` to restore the original bytes in a guaranteed cleanup path.
10. Run the tool tests and confirm all ownership and restoration behaviors pass.
11. Commit as `feat(tool): preserve consumer pubspec content`.

### Task 5: Implement custom host synchronization

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/host.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/lib/scaffold.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_tool/test/tool_tests.ml`.

Steps:

1. Write tests proving managed mode still generates deterministic `lib/main.dart` and its host widget test.
2. Write tests proving custom mode preserves consumer-owned `lib/main.dart` and tests byte-for-byte.
3. Write tests for focused custom-mode diagnostics when the entrypoint or required pubspec markers are absent.
4. Run the tool tests and confirm custom mode fails.
5. Implement the custom-mode validation and synchronization boundary.
6. Keep generated-file checks exclusive to managed mode.
7. Run the tool tests and confirm both host modes pass.
8. Commit as `feat(tool): support consumer-owned Flutter hosts`.

### Task 6: Externalize Counter as the consumer canary

Files:

- Add `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/dune-project`.
- Add `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/bonsai_flutter_counter.opam`.
- Add `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/bonsai_flutter_counter.opam.locked`.
- Add `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/.ocamlformat`.
- Add `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/bonsai-flutter.sexp`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/ocaml/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/flutter/pubspec.yaml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/README.md`.

Steps:

1. Extend the repository contract test with Counter-specific expected paths and aliases.
2. Run the contract test and confirm it fails.
3. Add the independent package metadata and version 2 managed-host configuration.
4. Add the standard platform aliases to the configured native target directory.
5. Replace repository-relative Flutter package paths with project-local synchronized paths and marker regions.
6. Build the current tool with `dune build bonsai_flutter_tool/bin/main.exe`.
7. From `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter`, run `../../_build/default/bonsai_flutter_tool/bin/main.exe exec --profile=debug -- sh -c 'cd flutter && flutter test --no-pub'`.
8. Confirm the native artifact is built below Counter's project root, Flutter tests pass, and the pubspec is restored exactly.
9. From the repository root, run `dune build @all` and confirm the nested project does not create ambiguous packages or targets.
10. Stop the migration and revise package boundaries if either canary command exposes nested-workspace ambiguity.
11. Commit as `feat(examples): externalize counter consumer`.

### Task 7: Externalize the managed-host examples

Files:

- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/clock`.
- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/host_effects`.
- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/host_navigation`.
- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/navigation`.
- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/text_input`.
- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/todo`.
- Modify each corresponding `ocaml/dune`, `flutter/pubspec.yaml`, and top-level example `README.md`.

Steps:

1. Add one failing contract-test case per example before editing that example.
2. Add the independent Dune project, opam manifest, lock, formatting config, and version 2 managed-host config for one example at a time.
3. Add its standard native aliases and marker-owned pubspec sections.
4. Run its OCaml tests from its consumer root.
5. Run its Flutter tests through `bonsai-flutter exec --profile=debug`.
6. Run the repository contract test after each example.
7. Commit each coherent example or small group with `feat(examples): externalize <name> consumer`.

### Task 8: Externalize Gallery with a custom host

Files:

- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery/ocaml/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery/flutter/pubspec.yaml`.
- Preserve `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery/flutter/lib/main.dart` as consumer-owned source.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery/README.md`.

Steps:

1. Add a host test that proves the custom registry still resolves Gallery-specific widgets after synchronization.
2. Add a contract assertion that Gallery selects custom host mode.
3. Run both tests and confirm the consumer contract fails before migration.
4. Add Gallery's independent consumer metadata and custom-host config.
5. Synchronize only the pubspec's tool-owned regions.
6. Run Gallery's host tests through `bonsai-flutter exec --profile=debug`.
7. Confirm `lib/main.dart` is byte-identical before and after `sync-host` and `exec`.
8. Commit as `feat(gallery): adopt consumer build workflow`.

### Task 9: Externalize Network with its feature closure

Files:

- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network/ocaml/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network/flutter/pubspec.yaml`.
- Preserve `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network/flutter/lib/main.dart` as consumer-owned source.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network/flutter/test/network_host_test.dart`.
- Move package ownership out of `/Users/rcmerci/gh-repos/bonsai_flutter/dune-project` and `/Users/rcmerci/gh-repos/bonsai_flutter/bonsai_flutter_network_example.opam`.

Steps:

1. Extend the Network contract test to require custom host mode, the `network` feature, and a project-local package lock.
2. Keep behavior tests for injected runtime startup, loading UI, and error UI.
3. Run the contract and host tests and confirm the consumer contract fails.
4. Move Network's package metadata into its consumer root and declare the complete host and iOS feature closure.
5. Remove the obsolete root package declaration after no root target owns it.
6. Run Network OCaml tests from its own root.
7. Run Network Flutter tests through `bonsai-flutter exec --profile=debug`.
8. Run `bonsai-flutter build ios --profile=release` and the existing Mach-O verification when the iOS toolchain is installed.
9. Commit as `feat(network): adopt consumer build workflow`.

### Task 10: Externalize SQLite Worker without losing Dart dependencies

Files:

- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker/ocaml/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker/flutter/pubspec.yaml`.
- Preserve `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker/flutter/lib/main.dart` as consumer-owned source.
- Modify tests under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker/flutter/test` only as required by the ownership boundary.

Steps:

1. Add a regression test proving `path_provider` remains in the pubspec after `sync-host` and `exec`.
2. Keep behavior tests for asynchronous application-support path resolution, payload construction, loading UI, and startup failure UI.
3. Add a contract assertion that SQLite Worker selects custom host mode and the `sqlite` feature.
4. Run the new tests and confirm the consumer contract fails.
5. Add the independent consumer project and custom-host configuration.
6. Run OCaml SQLite tests from the consumer root.
7. Run Flutter tests through `bonsai-flutter exec --profile=debug`.
8. Confirm the resulting artifact manifest includes the validated SQLite target closure.
9. Commit as `feat(sqlite): adopt consumer build workflow`.

### Task 11: Normalize Mail to one public native target

Files:

- Add consumer-root metadata under `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/ocaml/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/ocaml/mail.ml` only if trace-specific application branches must be removed.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/flutter/lib/main.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/flutter/pubspec.yaml`.
- Move or replace `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/flutter/test/mail_runtime_trace_test.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/README.md`.

Steps:

1. Add a contract test requiring exactly one configured `ocaml/native_embed.exe.o` target.
2. Add or retain behavior tests for Mail UI and profile-independent native entrypoint selection.
3. Add an internal trace test at the runtime or integration boundary before removing example-private trace variants.
4. Run the tests and confirm the single-target contract fails.
5. Replace debug and release native executables with one standard target.
6. Remove private trace libraries from the external-consumer package closure.
7. Remove old target names without aliases or fallbacks.
8. Run Mail tests through debug and release tool profiles.
9. Commit as `feat(mail): use one consumer native target`.

### Task 12: Convert the aggregate integration harness

Files:

- Add consumer metadata at `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test` or atomically move the harness to `/Users/rcmerci/gh-repos/bonsai_flutter/integration_test` if the canary proves that layout necessary.
- Modify the harness `ocaml/dune` file in the selected root.
- Modify the harness `pubspec.yaml` file in the selected root.
- Modify the harness `lib/main.dart` file in the selected root.
- Modify the harness tests in `test/`, `integration_test/`, and `benchmark/` in the selected root.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/README.md` or its moved replacement.

Steps:

1. Add a failing contract assertion that the harness is a configured custom-host consumer.
2. Add a failing assertion that its pubspec does not depend on an example Flutter application.
3. Inventory every OCaml example library used by the harness and assign it to an installable example package or an integration-owned fixture.
4. Move SQLite bootstrap behavior into the chosen application-neutral owner and update its behavior tests first.
5. Add the harness's project metadata, lock, feature set, standard aliases, custom-host config, and marker-owned pubspec regions.
6. Run unit and FFI tests through `bonsai-flutter exec --profile=debug`.
7. Run macOS integration tests through the tool-built artifact.
8. Run unsigned iOS integration builds through `bonsai-flutter build ios`.
9. Commit as `feat(integration): use consumer build workflow`.

### Task 13: Replace Make and CI orchestration

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/Makefile`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_ci_contract.sh`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_network_ios_contract.sh`.
- Modify workflow files under `/Users/rcmerci/gh-repos/bonsai_flutter/.github/workflows` only where their existing Make target cannot remain stable.

Steps:

1. Add contract assertions for the exact example matrix and the locally built tool executable.
2. Add contract assertions that raw example `flutter test`, `flutter analyze`, `flutter build`, and manual native staging commands are absent.
3. Run contract tests and confirm the new assertions fail.
4. Add a small matrix driver only if Make repetition would obscure failures, and keep that driver limited to public tool invocations.
5. Rewrite `ci-flutter` to synchronize each consumer and run analyze and tests through `exec`.
6. Rewrite `ci-macos` to call `build macos` for the selected application matrix.
7. Rewrite `ci-ios` to call `build ios` and existing bundle verification without `SDK_OPAM_SWITCH`.
8. Rewrite `ci-ios-device` to use `run ios` or a tool-wrapped integration invocation after signing preflight.
9. Run `make ci-contract`, `make ci-flutter`, `make ci-macos`, and `make ci-ios` in that order.
10. Commit as `feat(ci): build examples through bonsai flutter tool`.

### Task 14: Delete obsolete staging paths

Files:

- Delete `/Users/rcmerci/gh-repos/bonsai_flutter/tool/macos/stage_native_objects.sh` if no remaining internal target uses it.
- Delete `/Users/rcmerci/gh-repos/bonsai_flutter/tool/ios/build_native_objects.sh` if no remaining SDK-construction test uses it.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/Makefile` to remove `native-objects`, `integration-native-object`, and `ios-device-native-objects` after all callers migrate.
- Modify documentation and contract tests that mention the deleted paths.

Steps:

1. Add a contract assertion that the obsolete targets and production staging scripts do not exist.
2. Run the contract test and confirm it fails while the old paths remain.
3. Use `rg` to classify every remaining reference as migrated, SDK-internal, or stale.
4. Delete only application staging scripts and targets that have no SDK-internal responsibility.
5. Remove all stale references instead of adding forwarding wrappers.
6. Run `make ci-contract` and the full supported build matrix.
7. Commit as `dev(build): remove manual application staging`.

### Task 15: Repair and verify the repository snapshot lock

Files:

- Audit `/Users/rcmerci/gh-repos/bonsai_flutter/tool/ios/opam-repository/0.1.0`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/ios/opam-repository/0.1.0/repository.sexp` only after the audit confirms the committed snapshot is authoritative.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_ios_closure_lock.sh` only if its behavioral contract is incorrect.

Steps:

1. Run `bash tool/test_ios_closure_lock.sh` and record the expected current digest mismatch.
2. Verify the snapshot file set, package versions, patch contents, and deterministic ordering against the intended locked SDK universe.
3. Confirm that the digest algorithm excludes only `repository.sexp` and includes every other committed snapshot file.
4. Update the recorded digest to the audited value rather than weakening the test.
5. Run `bash tool/test_ios_closure_lock.sh` and confirm it passes.
6. Commit as `fix(ios): refresh audited repository snapshot digest`.

### Task 16: Update public documentation

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/README.md`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/docs/testing.md`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/docs/packaging.md`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/docs/architecture.md`.
- Modify affected example READMEs under `/Users/rcmerci/gh-repos/bonsai_flutter/examples`.

Steps:

1. Add documentation contract assertions for public commands where stable command snippets are part of the product contract.
2. Document managed and custom host ownership with one example of each.
3. Document that Flutter commands for native-backed apps run through `bonsai-flutter exec`.
4. Document project-local synchronized package paths and profile artifact ownership.
5. Remove direct staging, `SDK_OPAM_SWITCH`, old Mail targets, and raw example Flutter command guidance.
6. Run markdown and repository contract checks.
7. Commit as `doc(build): document consumer example workflow`.

### Task 17: Run final quality gates

Files:

- Do not modify production files during this task unless a failing gate exposes a defect covered by a new failing regression test.

Steps:

1. Run `dune build @fmt` and expect success with no diff.
2. Run `dune build @all` and expect success.
3. Run `dune runtest` and expect every test, including the audited snapshot lock, to pass.
4. Run `make ci-contract` and expect all consumer ownership assertions to pass.
5. Run `make ci-flutter` and expect analyze and Flutter tests for every example and the harness to pass through the tool.
6. Run `make ci-macos` and expect all selected macOS application builds and integration tests to pass.
7. Run `make ci-ios` and expect unsigned device application builds and bundle verification to pass.
8. Run `make ci-ios-device` on the connected iPhone after setting `IOS_DEVELOPMENT_TEAM`, and expect the signed integration application to install and run.
9. Run `git diff --check` and expect no whitespace errors.
10. Search with `rg 'native_artifact_root|SDK_OPAM_SWITCH|stage_native_objects|build_native_objects|native_embed_(debug|release)' examples flutter/integration_test Makefile docs tool` and classify any remaining occurrence as an error unless it belongs to SDK-internal documentation or tests.
11. Review `git status --short` and confirm the change set contains no generated build artifacts, temporary pubspecs, signing files, or unrelated user changes.

## Edge cases and failure policy

Concurrent debug and release commands for one consumer must serialize pubspec mutation with the existing project lock or use isolated temporary input so one profile cannot leak into another invocation.

An interrupted command must restore the original pubspec before releasing the project lock.

A child command that rewrites pubspec while `exec` is active must cause an explicit conflict instead of silently overwriting the child's changes during restoration.

Symlinked consumer roots and Flutter paths must remain inside the validated project ownership boundary.

Spaces and non-ASCII characters in project paths must be passed as argv values and never interpolated into shell commands.

Custom hosts must be allowed to add dependencies and dev dependencies without surrendering their source or pubspec ownership.

Managed hosts must reject local edits to generated files instead of erasing them silently.

Feature-specific examples must fail before Flutter invocation when their host or iOS package closure is incomplete.

An unavailable `bonsai-flutter-ios` switch must produce the public toolchain recovery command and must not fall back to `SDK_OPAM_SWITCH`.

Unsigned CI must not require signing identities, while the physical-device lane must fail at preflight before performing a long native build when signing configuration is absent.

The migration must preserve unrelated uncommitted work in the repository and must never regenerate or reset files outside each task's stated scope.

## Authorization boundary

Implementation requires edits to `/Users/rcmerci/gh-repos/bonsai_flutter/examples/*/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/ocaml/dune`, and likely `/Users/rcmerci/gh-repos/bonsai_flutter/dune-project`.

The example Dune files are `/Users/rcmerci/gh-repos/bonsai_flutter/examples/clock/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/counter/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/gallery/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/host_effects/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/host_navigation/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/navigation/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/network/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/sqlite_worker/ocaml/dune`, `/Users/rcmerci/gh-repos/bonsai_flutter/examples/text_input/ocaml/dune`, and `/Users/rcmerci/gh-repos/bonsai_flutter/examples/todo/ocaml/dune`.

The repository instructions prohibit Dune file changes without explicit user authorization.

Approval of this planning document does not itself authorize implementation unless the user explicitly asks to execute the plan and permits those Dune edits.

No OCaml file below `/Users/rcmerci/gh-repos/bonsai_flutter/spec` is in scope.

## Rollout and stopping conditions

Counter is the mandatory canary and must pass both standalone and repository-root builds before another example migrates.

Managed examples migrate before custom-host examples so pubspec and native-build ownership can stabilize independently of advanced Dart behavior.

Gallery validates custom registry ownership before Network and SQLite add feature closures and external Dart dependencies.

Mail and the aggregate harness migrate only after both host modes pass their behavioral suites.

Manual staging paths are deleted only after every supported CI and device lane has a tool-based replacement.

The implementation must stop if a required `spec/*.mli` definition is unclear or unreasonable and must report the exact interface issue without editing `spec`.

The implementation must also stop if the Counter canary proves that nested consumer projects cannot coexist safely with the root Dune workspace because that result changes the package-boundary design.

## Testing Details

The tool tests exercise observable filesystem and command behavior in temporary projects rather than testing internal variants or mocked data structures.

The repository contracts inspect each real example and then execute a Counter canary through the same CLI surface an external user receives.

The advanced-host tests execute actual widget and runtime boundaries so custom mode cannot pass merely by preserving files.

The platform gates inspect produced artifacts and bundles so a successful command without the correct architecture, profile, or closure is still a failure.

The final suite covers restoration, concurrency, interruption, malformed ownership markers, feature closure errors, unsigned builds, signing preflight, and real-device execution.

## Implementation Details

- Replace configuration language version 1 with version 2 and do not keep a compatibility parser.
- Support generated managed hosts and consumer-owned custom hosts through one native build workflow.
- Preserve consumer pubspec content through explicit tool-owned marker regions.
- Make every example an independent Dune and opam consumer project with one native target.
- Use Counter as the standalone and repository-root workspace canary.
- Keep advanced Dart behavior in custom hosts and keep build policy in the tool.
- Collapse Mail to one profile-independent native target and relocate private tracing tests.
- Convert the aggregate integration harness into a configured custom consumer.
- Replace repository staging commands with public `bonsai-flutter exec`, `build`, and `run` calls.
- Delete obsolete paths only after the complete CI and device matrix uses the tool.

## Question

Implementation needs explicit authorization to edit the listed Dune files because the repository instructions otherwise prohibit those changes.

The final physical-device gate also needs a valid `IOS_DEVELOPMENT_TEAM` and signing identity, while all planning, unit, Flutter, macOS, and unsigned iOS work can proceed without them.

---
