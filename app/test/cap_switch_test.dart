import 'package:cukup/features/cap_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bills stays out of the weekly cap by default, everything else counts', () {
    expect(capDefault('Bills'), isFalse);
    expect(capDefault(' bills '), isFalse);
    expect(capDefault('Food'), isTrue);
    expect(capDefault('Other'), isTrue);
    expect(capDefault(null), isTrue);
  });
}
