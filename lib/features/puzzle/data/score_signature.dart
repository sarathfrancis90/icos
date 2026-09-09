import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Lower-case hex SHA-256 of [input] (UTF-8).
String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// Canonical message signed by the client and re-computed by `submit-score`:
/// `${date}|${time}|${hints}|${undos}|${sha256hex(JSON(path))}` where the path
/// is serialised as compact JSON (`[[r,c],...]`, no whitespace).
String scoreSignatureMessage({
  required String puzzleDate,
  required int timeSeconds,
  required int hintsUsed,
  required int undosUsed,
  required List<List<int>> path,
}) {
  final pathHash = sha256Hex(jsonEncode(path));
  return '$puzzleDate|$timeSeconds|$hintsUsed|$undosUsed|$pathHash';
}

/// Hex HMAC-SHA256 over [scoreSignatureMessage] keyed with the session
/// [nonce] (UTF-8).
String computeScoreSignature({
  required String nonce,
  required String puzzleDate,
  required int timeSeconds,
  required int hintsUsed,
  required int undosUsed,
  required List<List<int>> path,
}) {
  final message = scoreSignatureMessage(
    puzzleDate: puzzleDate,
    timeSeconds: timeSeconds,
    hintsUsed: hintsUsed,
    undosUsed: undosUsed,
    path: path,
  );
  final hmac = Hmac(sha256, utf8.encode(nonce));
  return hmac.convert(utf8.encode(message)).toString();
}
