import 'package:cukup/core/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const good = {'build': 5, 'name': '1.0.4', 'apk': 'https://example.com/cukup.apk', 'notes': 'Fixes scan'};

  test('parses a valid feed', () {
    final u = parseUpdate(good)!;
    expect(u.build, 5);
    expect(u.name, '1.0.4');
    expect(u.notes, 'Fixes scan');
  });

  test('notes are optional', () => expect(parseUpdate({'build': 2, 'name': '1.0.1', 'apk': 'https://x.test/a.apk'})!.notes, ''));
  test('rejects a missing field', () => expect(parseUpdate({'build': 5, 'name': '1.0.4'}), isNull));
  test('rejects a non-https download', () => expect(parseUpdate({'build': 5, 'name': 'x', 'apk': 'http://example.com/a.apk'}), isNull));
  test('rejects a build that is not a number', () => expect(parseUpdate({'build': '5', 'name': 'x', 'apk': 'https://x.test/a.apk'}), isNull));
  test('rejects junk', () {
    expect(parseUpdate(null), isNull);
    expect(parseUpdate('hello'), isNull);
    expect(parseUpdate([1, 2]), isNull);
  });

  group('decodeFeed', () {
    const body = '{"apk":"https://x.test/a.apk","build":3,"name":"1.0.0","notes":"n"}';
    test('plain text', () => expect(parseUpdate(decodeFeed(body))?.build, 3));
    test('text with a byte-order mark and Windows line ends', () => expect(parseUpdate(decodeFeed('﻿{\r\n  "apk":  "https://x.test/a.apk",\r\n  "build":  3,\r\n  "name":  "1.0.0"\r\n}\r\n'))?.build, 3));
    test('raw bytes', () => expect(parseUpdate(decodeFeed(body.codeUnits))?.build, 3));
    test('already decoded', () => expect(parseUpdate(decodeFeed({'build': 3, 'name': '1.0.0', 'apk': 'https://x.test/a.apk'}))?.build, 3));
    test('not json', () => expect(decodeFeed('<html>'), isNull));
    test('null', () => expect(decodeFeed(null), isNull));
  });

  group('newerThan', () {
    final latest = parseUpdate(good);
    test('offers a higher build', () => expect(newerThan(4, latest)?.build, 5));
    test('same build is up to date', () => expect(newerThan(5, latest), isNull));
    test('a lower build never downgrades', () => expect(newerThan(9, latest), isNull));
    test('no feed means nothing to offer', () => expect(newerThan(1, null), isNull));
  });
}
