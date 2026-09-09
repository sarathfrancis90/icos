import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

void main() {
  group('fnv1a32 / seedFor', () {
    // Reference values produced by the JS implementation:
    //   h = 0x811c9dc5; for each charCode: h ^= c; h = Math.imul(h, 0x01000193) >>> 0
    test('matches JS FNV-1a for known strings', () {
      expect(fnv1a32(''), 2166136261);
      expect(seedFor('2026-01-01', 'fallback'), 1360798581);
      expect(seedFor('2026-09-09', 'salt'), 2438097975);
    });

    test('is deterministic and salt-sensitive', () {
      expect(seedFor('2026-09-09', 'a'), seedFor('2026-09-09', 'a'));
      expect(seedFor('2026-09-09', 'a'), isNot(seedFor('2026-09-09', 'b')));
      expect(seedFor('2026-09-09', 'a'), isNot(seedFor('2026-09-10', 'a')));
    });

    test('deriveSeed differs per attempt', () {
      final seeds = {for (var i = 0; i < 25; i++) deriveSeed(42, i)};
      expect(seeds.length, 25);
    });
  });

  group('imul32', () {
    test('matches Math.imul semantics for large operands', () {
      // Math.imul(0xFFFFFFFF, 0xFFFFFFFF) >>> 0 === 1
      expect(imul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
      // Math.imul(0x80000000, 2) >>> 0 === 0
      expect(imul32(0x80000000, 2), 0);
      expect(imul32(0x01000193, 0x811c9dc5), (0x01000193 * 0x811c9dc5) & 0xFFFFFFFF);
    });
  });

  group('Rng (mulberry32)', () {
    // Reference streams from the JS mulberry32 implementation.
    const reference = <int, List<double>>{
      1: [
        0.6270739405881613,
        0.002735721180215478,
        0.5274470399599522,
        0.9810509674716741,
        0.9683778982143849,
      ],
      12345: [
        0.9797282677609473,
        0.3067522644996643,
        0.484205421525985,
        0.817934412509203,
        0.5094283693470061,
      ],
      0xFFFFFFFF: [
        0.8964226141106337,
        0.189478256739676,
        0.7156526781618595,
        0.9440599093213677,
        0.8452364315744489,
      ],
      2147483648: [
        0.8205775609239936,
        0.4481089550536126,
        0.7836112855002284,
        0.5120457962621003,
        0.8388098266441375,
      ],
    };

    test('nextDouble matches the JS stream exactly', () {
      reference.forEach((seed, expected) {
        final rng = Rng(seed);
        for (final value in expected) {
          expect(rng.nextDouble(), value, reason: 'seed $seed');
        }
      });
    });

    test('nextInt matches Math.floor(next() * n)', () {
      expect(
        List.generate(5, (_) => Rng(1).nextInt(100)).first,
        62,
      );
      final rng = Rng(12345);
      expect(List.generate(5, (_) => rng.nextInt(100)), [97, 30, 48, 81, 50]);
    });

    test('nextInt stays within range', () {
      final rng = Rng(7);
      for (var i = 0; i < 10000; i++) {
        final v = rng.nextInt(7);
        expect(v, inInclusiveRange(0, 6));
      }
    });

    test('nextIntInclusive covers both bounds', () {
      final rng = Rng(99);
      final seen = <int>{};
      for (var i = 0; i < 1000; i++) {
        seen.add(rng.nextIntInclusive(3, 5));
      }
      expect(seen, {3, 4, 5});
    });

    test('shuffle is a permutation and deterministic', () {
      final a = List.generate(20, (i) => i);
      final b = List.generate(20, (i) => i);
      Rng(5).shuffle(a);
      Rng(5).shuffle(b);
      expect(a, b);
      expect(a.toSet(), List.generate(20, (i) => i).toSet());
      expect(a, isNot(List.generate(20, (i) => i)));
    });
  });
}
