import 'package:flutter_test/flutter_test.dart';
import 'package:musify/constants/version.dart';

void main() {
  test('app version is generated', () {
    expect(appVersion, isNotEmpty);
  });
}
