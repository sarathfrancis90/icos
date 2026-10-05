import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/core/utils/share_utils.dart';
import 'package:icos/features/profile/domain/models/profile.dart';
import 'package:icos/features/profile/providers/profile_provider.dart';
import 'package:share_plus/share_plus.dart';

class _FakeProfile extends ProfileNotifier {
  _FakeProfile(this.exported);

  final Result<File, AppError> exported;

  @override
  AsyncValue<UserProfile?> build() => const AsyncValue.data(null);

  @override
  Future<Result<File, AppError>> exportData() async => exported;
}

class _Shared {
  XFile? file;
  String? subject;
  Rect? origin;
}

void main() {
  late Directory dir;
  late File export;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('icos_export_');
    export = File('${dir.path}/icos-export-2026-10-05T10-00-00.json');
    await export.writeAsString('{"user": {}}');
  });

  tearDown(() async => dir.delete(recursive: true));

  ProviderContainer container(
    Result<File, AppError> exported,
    _Shared shared, {
    Object? shareError,
  }) {
    final c = ProviderContainer(
      overrides: [
        profileNotifierProvider.overrideWith(() => _FakeProfile(exported)),
        fileSharerProvider.overrideWithValue(({
          required XFile file,
          String? subject,
          String? text,
          Rect? origin,
        }) async {
          if (shareError != null) throw shareError;
          shared
            ..file = file
            ..subject = subject
            ..origin = origin;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'hands the exported JSON file to the share sheet with the anchor',
    () async {
      final shared = _Shared();
      final c = container(Result.success(export), shared);
      const anchor = Rect.fromLTWH(10, 20, 30, 40);

      final result = await c
          .read(profileNotifierProvider.notifier)
          .exportAndShareData(origin: anchor);

      expect(result, isA<Success<void, AppError>>());
      expect(shared.file!.path, export.path);
      expect(shared.file!.mimeType, 'application/json');
      expect(shared.origin, anchor);
      expect(shared.subject, isNotNull);
    },
  );

  test('a failed export is returned and nothing is shared', () async {
    final shared = _Shared();
    final c = container(const Result.failure(AppError.network('down')), shared);

    final result = await c
        .read(profileNotifierProvider.notifier)
        .exportAndShareData();

    expect(result, isA<Failure<void, AppError>>());
    expect(shared.file, isNull);
  });

  test(
    'a share sheet that throws becomes a Failure, not an exception',
    () async {
      final shared = _Shared();
      final c = container(
        Result.success(export),
        shared,
        shareError: Exception('no share sheet'),
      );

      final result = await c
          .read(profileNotifierProvider.notifier)
          .exportAndShareData();

      expect(result, isA<Failure<void, AppError>>());
    },
  );
}
