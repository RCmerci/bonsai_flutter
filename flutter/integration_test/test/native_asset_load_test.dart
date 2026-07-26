import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';
import 'package:test/test.dart';

void main() {
  test('loads the embedded native asset', () {
    expect(nativeProtocolVersion, const NativeProtocolVersion(1, 12));
  });
}
