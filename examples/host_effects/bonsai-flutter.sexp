(lang 2)
(app
 (name bonsai_flutter_host_effects_example)
 (flutter_root flutter)
 (native_target ocaml/native_embed.exe.o)
 (features)
 (host (mode managed_adapter) (adapter lib/application_host_adapter.dart) (entrypoint host_effects) (launch_policy replace_existing))
 (macos (minimum_version 26.0) (architectures arm64))
 (ios (minimum_version 15.0) (architectures arm64)))
