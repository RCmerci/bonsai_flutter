(lang 2)
(app
 (name bonsai_flutter_gallery)
 (flutter_root flutter)
 (native_target ocaml/native_embed.exe.o)
 (features)
 (host (mode custom) (main lib/main.dart))
 (macos (minimum_version 26.0) (architectures arm64))
 (ios (minimum_version 15.0) (architectures arm64)))
