# Icos

**One line. Every cell.** A daily path puzzle for iOS and Android.

Draw one continuous line through every cell of the grid, visiting the numbered
waypoints in order. Every puzzle has exactly one solution. The same puzzle for
everyone, every day: easy on Monday, expert by Sunday. Streaks, groups with
daily and weekly leaderboards, practice mode and a 30-day archive.

Named after the Icosian game, invented by William Rowan Hamilton in 1857, the
origin of what mathematicians now call Hamiltonian paths.

## Stack

Flutter 3.41 (Riverpod, GoRouter, Hive) on the client; Neon on the backend (Lakebase
Postgres with the Data API, and one Neon Function `api` on Node 24 with Hono and
Better Auth, plus schedule triggers). The puzzle generator and uniqueness solver are
implemented in TypeScript (`backend/src/shared/puzzle_core.ts`)
and Dart (`lib/features/puzzle/domain/solver/`) with a shared parity fixture.

## Develop

```bash
cp .env.example .env.development && cp .env.example .env.production   # fill in values
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

Backend: see `backend/README.md` and `backend/CONTRACTS.md`. Release process and owner checklist: `docs/RELEASE_RUNBOOK.md`.
