.PHONY: build test viewport-type-test fmt protocol-generate protocol-check protocol-fixtures-generate protocol-fixtures-check dart-test flutter-test dart-analyze native-test native-analyze native-object integration-test ios-toolchains ios-cross-probes ci-contract ci-install-framework ci-install-consumers ci-install-ios-toolchain ci-ocaml ci-flutter ci-macos ci-sanitizers ci-ios ci-ios-device clean

EXAMPLE ?= counter
BONSAI_FLUTTER := $(CURDIR)/_build/default/bonsai_flutter_tool/bin/main.exe
CONSUMERS := clock counter gallery host_effects host_navigation mail navigation network sqlite_worker text_input todo
CONSUMER_ROOTS := $(addprefix ./examples/,$(CONSUMERS))

build:
	dune build @all

test:
	dune runtest
	tool/check_viewport_types.sh

viewport-type-test:
	tool/check_viewport_types.sh

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
	dune build bonsai_flutter_tool/bin/main.exe
	cd examples/$(EXAMPLE) && $(BONSAI_FLUTTER) build macos --profile debug

integration-test:
	dune build bonsai_flutter_tool/bin/main.exe
	cd flutter/integration_test && $(BONSAI_FLUTTER) exec --profile=debug -- flutter test --no-pub

ios-toolchains:
	tool/ios/setup_toolchain.sh all

ios-cross-probes: ios-toolchains
	tool/ios/build_probe.sh iphoneos

ci-contract:
	tool/test_ci_contract.sh
	tool/test_ios_closure_lock.sh
	tool/test_datascript_worker_contract.sh

ci-install-framework:
	opam install . --deps-only --with-test --yes
	opam install . --yes

ci-install-consumers: ci-install-framework
	opam install $(CONSUMER_ROOTS) --yes

ci-install-ios-toolchain:
	dune build bonsai_flutter_tool/bin/main.exe
	@$(BONSAI_FLUTTER) toolchain show iphoneos >/dev/null 2>&1 || $(BONSAI_FLUTTER) toolchain install iphoneos
	$(BONSAI_FLUTTER) toolchain verify iphoneos

ci-ocaml: ci-install-consumers
	dune build @all
	dune runtest
	tool/check_viewport_types.sh
	dune build @fmt
	dune exec protocol/generator/generate.exe -- --check
	dune exec protocol/generator/generate_fixtures.exe -- --check
	dune build --profile release ocaml/bench/runtime_bench.exe
	opam lint bonsai_flutter.opam bonsai_flutter_test.opam bonsai_flutter_tool.opam
	@set -e; for consumer in $(CONSUMERS); do 	  (cd "examples/$$consumer" && dune build --root=. @all && dune runtest --root=.); 	done

ci-flutter: ci-install-consumers
	dune build bonsai_flutter_tool/bin/main.exe
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
	@set -e; for consumer in $(CONSUMERS); do 	  (cd "examples/$$consumer" && 	    $(BONSAI_FLUTTER) sync-host --check && 	    cd flutter && 	    dart format --output=none --set-exit-if-changed lib test && 	    $(BONSAI_FLUTTER) exec --profile=debug -- flutter analyze && 	    if find test -type f -name '*_test.dart' | grep -q .; then 	      NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost $(BONSAI_FLUTTER) exec --profile=debug -- flutter test --no-pub; 	    fi); 	done
	cd flutter/integration_test && dart format --output=none --set-exit-if-changed benchmark integration_test lib test test_driver
	cd flutter/integration_test && $(BONSAI_FLUTTER) sync-host --check
	cd flutter/integration_test && $(BONSAI_FLUTTER) exec --profile=debug -- flutter analyze
	cd flutter/integration_test && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost $(BONSAI_FLUTTER) exec --profile=debug -- flutter test --no-pub

ci-macos: ci-ocaml
	dune build bonsai_flutter_tool/bin/main.exe
	cd examples/counter && $(BONSAI_FLUTTER) build macos --profile debug
	cd examples/counter && $(BONSAI_FLUTTER) build macos --profile profile
	cd examples/counter && $(BONSAI_FLUTTER) build macos --profile release
	cd examples/network && $(BONSAI_FLUTTER) build macos --profile debug
	cd examples/network && $(BONSAI_FLUTTER) build macos --profile profile
	cd examples/network && $(BONSAI_FLUTTER) build macos --profile release
	cd flutter/integration_test && $(BONSAI_FLUTTER) exec --profile=debug -- flutter test --no-pub

ci-ios: ci-install-ios-toolchain
	dune build bonsai_flutter_tool/bin/main.exe
	cd examples/counter && $(BONSAI_FLUTTER) build ios --profile debug --no-codesign
	cd examples/counter && $(BONSAI_FLUTTER) build ios --profile profile --no-codesign
	cd examples/counter && $(BONSAI_FLUTTER) build ios --profile release --no-codesign
	cd examples/sqlite_worker && $(BONSAI_FLUTTER) build ios --profile debug --no-codesign
	cd examples/sqlite_worker && $(BONSAI_FLUTTER) build ios --profile profile --no-codesign
	cd examples/sqlite_worker && $(BONSAI_FLUTTER) build ios --profile release --no-codesign
	cd examples/network && $(BONSAI_FLUTTER) build ios --profile debug --no-codesign
	cd examples/network && $(BONSAI_FLUTTER) build ios --profile profile --no-codesign
	cd examples/network && $(BONSAI_FLUTTER) build ios --profile release --no-codesign
	cd flutter/integration_test && $(BONSAI_FLUTTER) build ios --profile release --no-codesign

ci-ios-device: ci-install-consumers ci-install-ios-toolchain
	@test -n "$(IOS_DEVICE_ID)" || (echo "IOS_DEVICE_ID is required" >&2; exit 1)
	@tool/ci/ios_device_preflight.sh
	dune build bonsai_flutter_tool/bin/main.exe
	cd flutter/integration_test && $(BONSAI_FLUTTER) run ios --profile debug --device "$(IOS_DEVICE_ID)"

ci-sanitizers:
	mkdir -p _build/ci
	@set -e; if test "$$(uname -s)" = Darwin; then 	  clang -std=c11 -Wall -Wextra -Werror -g -DBF_WITH_OCAML flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.c flutter/packages/bonsai_flutter_native/test/mock_ocaml_bridge.c flutter/packages/bonsai_flutter_native/test/native_bridge_test.c -o _build/ci/native_bridge_sanitized; 	  _build/ci/native_bridge_sanitized; 	else 	  clang -std=c11 -Wall -Wextra -Werror -g -DBF_WITH_OCAML -fsanitize=address,undefined -fno-omit-frame-pointer flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.c flutter/packages/bonsai_flutter_native/test/mock_ocaml_bridge.c flutter/packages/bonsai_flutter_native/test/native_bridge_test.c -o _build/ci/native_bridge_sanitized; 	  ASAN_OPTIONS=detect_leaks=1 _build/ci/native_bridge_sanitized; 	fi
	cd flutter/packages/bonsai_flutter && NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost flutter test test/binary_codec_test.dart test/native_resource_store_test.dart

clean:
	dune clean
