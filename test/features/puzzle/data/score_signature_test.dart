import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/data/score_signature.dart';

void main() {
  group('computeScoreSignature', () {
    const nonce = 'abc';
    const date = '2026-09-10';
    const path = [
      [0, 0],
      [0, 1],
    ];

    test('matches an independently computed HMAC-SHA256', () {
      // Expected value built here from first principles (same recipe as the
      // submit-score edge function).
      final pathJson = jsonEncode(path);
      expect(pathJson, '[[0,0],[0,1]]', reason: 'compact JSON, no spaces');
      final pathHash = sha256.convert(utf8.encode(pathJson)).toString();
      final message = '$date|42|0|1|$pathHash';
      final expected =
          Hmac(sha256, utf8.encode(nonce)).convert(utf8.encode(message)).toString();

      final actual = computeScoreSignature(
        nonce: nonce,
        puzzleDate: date,
        timeSeconds: 42,
        hintsUsed: 0,
        undosUsed: 1,
        path: path,
      );

      expect(actual, expected);
      expect(actual, hasLength(64));
      expect(actual, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('message layout is date|time|hints|undos|sha256(path)', () {
      final msg = scoreSignatureMessage(
        puzzleDate: date,
        timeSeconds: 42,
        hintsUsed: 0,
        undosUsed: 1,
        path: path,
      );
      final parts = msg.split('|');
      expect(parts, hasLength(5));
      expect(parts.sublist(0, 4), ['2026-09-10', '42', '0', '1']);
      expect(parts[4], sha256Hex('[[0,0],[0,1]]'));
    });

    test('any field change alters the signature', () {
      String sig({int time = 42, int hints = 0, int undos = 1, String n = nonce}) =>
          computeScoreSignature(
            nonce: n,
            puzzleDate: date,
            timeSeconds: time,
            hintsUsed: hints,
            undosUsed: undos,
            path: path,
          );
      final base = sig();
      expect(sig(time: 43), isNot(base));
      expect(sig(hints: 1), isNot(base));
      expect(sig(undos: 0), isNot(base));
      expect(sig(n: 'abd'), isNot(base));
      expect(sig(), base, reason: 'deterministic');
    });
  });
}
