import 'dart:math';

final _random = Random.secure();

/// A random id of [length] characters from a-z and 0-9. 12 characters give
/// about 62 bits, plenty for ids made on 1 device.
String randomId([int length = 12]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(
    List.generate(length, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
  );
}
