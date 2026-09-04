import '../bonsai_flutter_native_bindings_generated.dart' as bindings;

final class NativeAbiVersion {
  const NativeAbiVersion(this.major, this.minor);

  final int major;
  final int minor;

  @override
  bool operator ==(Object other) =>
      other is NativeAbiVersion && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

final class NativeProtocolVersion {
  const NativeProtocolVersion(this.major, this.minor);

  final int major;
  final int minor;

  @override
  bool operator ==(Object other) =>
      other is NativeProtocolVersion &&
      other.major == major &&
      other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

abstract interface class NativeVersionFacade {
  NativeAbiVersion get abi;
  NativeProtocolVersion get protocol;
}

final class NativeLibraryLoadingException implements Exception {
  const NativeLibraryLoadingException(this.message);

  final String message;

  @override
  String toString() => 'NativeLibraryLoadingException: $message';
}

final class _BindingsNativeVersionFacade implements NativeVersionFacade {
  const _BindingsNativeVersionFacade();

  @override
  NativeAbiVersion get abi => NativeAbiVersion(
    bindings.bf_abi_version_major(),
    bindings.bf_abi_version_minor(),
  );

  @override
  NativeProtocolVersion get protocol => NativeProtocolVersion(
    bindings.bf_protocol_version_major(),
    bindings.bf_protocol_version_minor(),
  );
}

const NativeVersionFacade nativeVersionFacade = _BindingsNativeVersionFacade();

final NativeAbiVersion nativeAbiVersion = nativeVersionFacade.abi;
final NativeProtocolVersion nativeProtocolVersion =
    nativeVersionFacade.protocol;

void validateNativeVersions(NativeVersionFacade versions) {
  const expectedAbi = NativeAbiVersion(2, 0);
  const expectedProtocol = NativeProtocolVersion(2, 26);
  if (versions.abi != expectedAbi) {
    throw NativeLibraryLoadingException(
      'Native ABI ${versions.abi} does not match required ABI $expectedAbi',
    );
  }
  if (versions.protocol != expectedProtocol) {
    throw NativeLibraryLoadingException(
      'Renderer protocol ${versions.protocol} does not match required '
      'protocol $expectedProtocol',
    );
  }
}
