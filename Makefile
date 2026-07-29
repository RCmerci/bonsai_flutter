.PHONY: build test fmt protocol-generate protocol-check protocol-fixtures-generate protocol-fixtures-check dart-test flutter-test dart-analyze native-test native-analyze native-object native-objects integration-native-object integration-test ios-toolchains ios-cross-probes ios-device-native-objects ci-contract ci-ocaml ci-flutter ci-macos ci-sanitizers ci-ios ci-ios-device clean

EXAMPLE ?= counter
NATIVE_OBJECT_TARGET = examples/$(EXAMPLE)/ocaml/native_embed.exe.o
NATIVE_OBJECT_TARGETS = \
	examples/counter/ocaml/native_embed.exe.o \
	examples/gallery/ocaml/native_embed.exe.o \
	examples/host_effects/ocaml/native_embed.exe.o \
	examples/host_navigation/ocaml/native_embed.exe.o \
	examples/mail/ocaml/native_embed.exe.o \
	examples/navigation/ocaml/native_embed.exe.o \
	examples/text_input/ocaml/native_embed.exe.o \
	examples/todo/ocaml/native_embed.exe.o

build:
	dune build @all

test:
	dune runtest

fmt:
	dune build @fmt

protocol-generate:
	dune exec protocol/generator/generate.exe --

protocol-check:
	dune exec protocol/generator/generate.exe -- --check

protocol-fixtures-generate:
	dune exec protocol/generator/generate_fixtures.exe --
	cd flutter/packages/bonsai_flutter && dart run tool/generate_input_fixtures.dart

protocol-fixtures-check:
	dune exec protocol/generator/generate_fixtures.exe -- --check
	cd flutter/packages/bonsai_flutter && dart run tool/generate_input_fixtures.dart --check

dart-test:
	cd flutter/packages/bonsai_flutter && dart test test/node_store_test.dart test/binary_codec_test.dart test/runtime_client_test.dart

flutter-test:
	cd flutter/packages/bonsai_flutter && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost flutter test

dart-analyze:
	cd flutter/packages/bonsai_flutter && dart analyze

native-test:
	cd flutter/packages/bonsai_flutter_native && dart test

native-analyze:
	cd flutter/packages/bonsai_flutter_native && dart analyze

native-object:
	BONSAI_FLUTTER_EMBED_OCAML=enabled dune build $(NATIVE_OBJECT_TARGET)
	tool/macos/stage_native_objects.sh example $(EXAMPLE)

native-objects:
	BONSAI_FLUTTER_EMBED_OCAML=enabled dune build $(NATIVE_OBJECT_TARGETS)
	tool/macos/stage_native_objects.sh examples

integration-native-object:
	BONSAI_FLUTTER_EMBED_OCAML=enabled dune build flutter/integration_test/ocaml/native_integration_embed.exe.o
	tool/macos/stage_native_objects.sh integration

integration-test: integration-native-object
	cd flutter/integration_test && flutter pub get
	cd flutter/integration_test && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost flutter test

ios-toolchains:
	tool/ios/setup_toolchain.sh all

ios-cross-probes: ios-toolchains
	tool/ios/build_probe.sh iphoneos

ios-device-native-objects:
	tool/ios/build_native_objects.sh iphoneos

ci-contract:
	tool/test_ci_contract.sh

ci-ocaml:
	OCAMLPARAM='_,keywords=4.14' opam install . --deps-only --with-test --yes
	dune build @all
	dune runtest
	dune build @fmt
	dune exec protocol/generator/generate.exe -- --check
	dune exec protocol/generator/generate_fixtures.exe -- --check
	dune build --profile release ocaml/bench/runtime_bench.exe
	opam lint bonsai_flutter.opam bonsai_flutter_test.opam

ci-flutter:
	cd flutter/packages/bonsai_flutter && flutter pub get
	cd flutter/packages/bonsai_flutter && dart run tool/generate_input_fixtures.dart --check
	cd flutter/packages/bonsai_flutter && dart format --output=none --set-exit-if-changed lib test benchmark tool
	cd flutter/packages/bonsai_flutter && flutter analyze
	cd flutter/packages/bonsai_flutter && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost flutter test
	cd flutter/packages/bonsai_flutter_native && dart pub get
	cd flutter/packages/bonsai_flutter_native && dart format --output=none --set-exit-if-changed hook lib test
	cd flutter/packages/bonsai_flutter_native && dart analyze
	cd flutter/packages/bonsai_flutter_native && dart test
	cd flutter/packages/bonsai_flutter_native && dart run ffigen --config ffigen.yaml
	git diff --exit-code -- flutter/packages/bonsai_flutter_native/lib/bonsai_flutter_native_bindings_generated.dart
	cd flutter/integration_test && flutter pub get
	cd flutter/integration_test && dart format --output=none --set-exit-if-changed benchmark integration_test lib test test_driver
	cd flutter/integration_test && flutter analyze
	@set -e; for example in counter todo text_input host_effects navigation gallery host_navigation mail; do \
	  (cd "examples/$$example/flutter" && flutter pub get && dart format --output=none --set-exit-if-changed lib && flutter analyze); \
	done

ci-macos: ci-ocaml
	$(MAKE) native-objects
	cd examples/counter/flutter && flutter pub get
	cd examples/counter/flutter && flutter build macos --debug
	cd examples/counter/flutter && flutter build macos --profile
	cd examples/counter/flutter && flutter build macos --release
	$(MAKE) integration-native-object
	cd flutter/integration_test && flutter pub get
	cd flutter/integration_test && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost flutter test

ci-ios:
	$(MAKE) ios-device-native-objects
	cd examples/counter/flutter && flutter pub get
	cd examples/counter/flutter && flutter build ios --debug --no-codesign
	tool/ios/verify_app_bundle.sh examples/counter/flutter/build/ios/iphoneos/Runner.app
	cd examples/counter/flutter && flutter build ios --profile --no-codesign
	tool/ios/verify_app_bundle.sh examples/counter/flutter/build/ios/iphoneos/Runner.app examples/counter/flutter/build/ios/Profile-iphoneos/bonsai_flutter_native.framework.dSYM
	cd examples/counter/flutter && flutter build ios --release --no-codesign
	tool/ios/verify_app_bundle.sh examples/counter/flutter/build/ios/iphoneos/Runner.app examples/counter/flutter/build/ios/Release-iphoneos/bonsai_flutter_native.framework.dSYM

ci-ios-device:
	@test -n "$(IOS_DEVICE_ID)" || (echo "IOS_DEVICE_ID is required" >&2; exit 1)
	@tool/ios/run_device_tests.sh "$(IOS_DEVICE_ID)" --debug --profile --release

ci-sanitizers:
	mkdir -p _build/ci
	@set -e; if test "$$(uname -s)" = Darwin; then \
	  clang -std=c11 -Wall -Wextra -Werror -g -DBF_WITH_OCAML flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.c flutter/packages/bonsai_flutter_native/test/mock_ocaml_bridge.c flutter/packages/bonsai_flutter_native/test/native_bridge_test.c -o _build/ci/native_bridge_sanitized; \
	  _build/ci/native_bridge_sanitized; \
	else \
	  clang -std=c11 -Wall -Wextra -Werror -g -DBF_WITH_OCAML -fsanitize=address,undefined -fno-omit-frame-pointer flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.c flutter/packages/bonsai_flutter_native/test/mock_ocaml_bridge.c flutter/packages/bonsai_flutter_native/test/native_bridge_test.c -o _build/ci/native_bridge_sanitized; \
	  ASAN_OPTIONS=detect_leaks=1 _build/ci/native_bridge_sanitized; \
	fi
	cd flutter/packages/bonsai_flutter && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost flutter test test/binary_codec_test.dart test/native_resource_store_test.dart

clean:
	dune clean
