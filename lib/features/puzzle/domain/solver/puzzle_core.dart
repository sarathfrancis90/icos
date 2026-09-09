/// Barrel for the Dart puzzle core (mirror of
/// `supabase/functions/_shared/puzzle_core.ts`).
///
/// Everything exported here is pure Dart with no Flutter dependencies, so it
/// can run inside `Isolate.run`.
library;

export 'adapters.dart';
export 'generator.dart';
export 'grid.dart';
export 'hamiltonian.dart';
export 'rng.dart';
export 'solver.dart';
