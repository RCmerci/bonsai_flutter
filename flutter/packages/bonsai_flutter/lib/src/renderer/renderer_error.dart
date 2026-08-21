final class RendererBuildException implements Exception {
  const RendererBuildException(this.message);

  final String message;

  @override
  String toString() => 'RendererBuildException($message)';
}
