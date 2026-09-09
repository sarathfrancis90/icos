/// Deterministic pseudo-random helpers shared with the TypeScript puzzle core.
///
/// Both implementations must produce identical numeric streams, so every
/// operation here emulates JavaScript's 32-bit integer semantics
/// (`Math.imul`, `>>> 0`, `| 0`) using explicit uint32 wrapping.
library;

const int _mask32 = 0xFFFFFFFF;

/// Emulates JavaScript `Math.imul(a, b) >>> 0` without relying on 64-bit
/// overflow behaviour (safe on both the VM and JS compile targets).
int imul32(int a, int b) {
  final al = a & 0xFFFF;
  final ah = (a >> 16) & 0xFFFF;
  final bl = b & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF;
  final low = al * bl;
  final cross = ((ah * bl + al * bh) & 0xFFFF) << 16;
  return (low + cross) & _mask32;
}

/// FNV-1a 32-bit hash over the UTF-16 code units of `text`, matching the
/// JavaScript implementation that iterates `charCodeAt`.
int fnv1a32(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = (hash ^ unit) & _mask32;
    hash = imul32(hash, 0x01000193);
  }
  return hash;
}

/// Seed for a given puzzle date and salt: `FNV-1a("$salt:$date")`.
int seedFor(String date, String salt) => fnv1a32('$salt:$date');

/// Derives a retry seed from a base seed and an attempt counter.
int deriveSeed(int seed, int attempt) => fnv1a32('$seed:$attempt');

/// mulberry32 generator. Produces the same stream as the reference JS code:
///
/// ```js
/// a |= 0; a = a + 0x6D2B79F5 | 0;
/// var t = Math.imul(a ^ a >>> 15, 1 | a);
/// t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
/// return ((t ^ t >>> 14) >>> 0) / 4294967296;
/// ```
class Rng {
  Rng(int seed) : _state = seed & _mask32;

  int _state;

  /// Current internal state (uint32). Exposed for tests only.
  int get state => _state;

  /// Next uint32 value in the stream.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask32;
    var t = imul32(_state ^ (_state >> 15), 1 | _state);
    t = ((t + imul32(t ^ (t >> 7), 61 | t)) & _mask32) ^ t;
    return (t ^ (t >> 14)) & _mask32;
  }

  /// Uniform double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform integer in `[0, n)`. Requires `n > 0`.
  int nextInt(int n) {
    assert(n > 0, 'nextInt requires n > 0');
    return (nextDouble() * n).floor();
  }

  /// Uniform integer in `[lo, hi]` inclusive.
  int nextIntInclusive(int lo, int hi) => lo + nextInt(hi - lo + 1);

  /// Returns `true` with probability `p`.
  bool chance(double p) => nextDouble() < p;

  /// In-place Fisher–Yates shuffle.
  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }
}
