import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/sync_service.dart';
import 'package:icos/shared/widgets/offline_banner.dart';

import '../../helpers/test_helpers.dart';

class _FixedConnectivity extends ConnectivityNotifier {
  _FixedConnectivity(this.online);

  final bool online;

  @override
  bool build() => online;
}

void main() {
  Widget build({required bool online, int queued = 0}) {
    return buildTestWidgetInScaffold(
      const Column(children: [OfflineBanner()]),
      overrides: [
        connectivityNotifierProvider.overrideWith(() => _FixedConnectivity(online)),
        syncQueueLengthProvider.overrideWith((ref) => Stream.value(queued)),
      ],
    );
  }

  group('OfflineBanner', () {
    testWidgets('renders nothing while online with an empty queue',
        (tester) async {
      await tester.pumpWidget(build(online: true));
      await tester.pump();

      expect(find.byKey(const Key('offline-banner')), findsNothing);
      expect(find.byKey(const Key('sync-pending-chip')), findsNothing);
    });

    testWidgets('shows the offline notice when disconnected', (tester) async {
      await tester.pumpWidget(build(online: false));
      await tester.pump();

      expect(find.byKey(const Key('offline-banner')), findsOneWidget);
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('shows a singular pending chip', (tester) async {
      await tester.pumpWidget(build(online: true, queued: 1));
      await tester.pump();

      expect(find.byKey(const Key('offline-banner')), findsNothing);
      expect(find.text('1 result waiting to sync'), findsOneWidget);
    });

    testWidgets('shows a plural pending chip together with the banner',
        (tester) async {
      await tester.pumpWidget(build(online: false, queued: 3));
      await tester.pump();

      expect(find.byKey(const Key('offline-banner')), findsOneWidget);
      expect(find.text('3 results waiting to sync'), findsOneWidget);
    });
  });
}
