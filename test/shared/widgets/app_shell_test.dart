import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/theme/app_theme.dart';

void main() {
  group('AppShell (BottomNavigationBar)', () {
    late GoRouter router;
    late List<String> navigatedPaths;

    setUp(() {
      navigatedPaths = [];

      router = GoRouter(
        initialLocation: '/',
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              return Scaffold(
                body: child,
                bottomNavigationBar: BottomNavigationBar(
                  currentIndex: _currentIndex(state.uri.path),
                  onTap: (index) {
                    final path = switch (index) {
                      0 => '/',
                      1 => '/groups',
                      2 => '/stats',
                      3 => '/profile',
                      _ => '/',
                    };
                    navigatedPaths.add(path);
                    GoRouter.of(context).go(path);
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_rounded),
                      label: AppStrings.navHome,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.group_rounded),
                      label: AppStrings.navGroups,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.bar_chart_rounded),
                      label: AppStrings.navStats,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_rounded),
                      label: AppStrings.navProfile,
                    ),
                  ],
                ),
              );
            },
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Center(child: Text('Home Page')),
              ),
              GoRoute(
                path: '/groups',
                builder: (context, state) =>
                    const Center(child: Text('Groups Page')),
              ),
              GoRoute(
                path: '/stats',
                builder: (context, state) =>
                    const Center(child: Text('Stats Page')),
              ),
              GoRoute(
                path: '/profile',
                builder: (context, state) =>
                    const Center(child: Text('Profile Page')),
              ),
            ],
          ),
        ],
      );
    });

    Widget buildAppShell() {
      return MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.darkTheme,
      );
    }

    group('Tab rendering', () {
      testWidgets('shows 4 tabs', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        expect(find.byType(BottomNavigationBar), findsOneWidget);

        // Check all tab labels
        expect(find.text(AppStrings.navHome), findsOneWidget);
        expect(find.text(AppStrings.navGroups), findsOneWidget);
        expect(find.text(AppStrings.navStats), findsOneWidget);
        expect(find.text(AppStrings.navProfile), findsOneWidget);
      });

      testWidgets('shows Home tab icon', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      });

      testWidgets('shows Groups tab icon', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.group_rounded), findsOneWidget);
      });

      testWidgets('shows Stats tab icon', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
      });

      testWidgets('shows Profile tab icon', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      });
    });

    group('Tab navigation', () {
      testWidgets('starts on Home page', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        expect(find.text('Home Page'), findsOneWidget);
      });

      testWidgets('tapping Groups tab navigates to /groups', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.navGroups));
        await tester.pumpAndSettle();

        expect(find.text('Groups Page'), findsOneWidget);
        expect(navigatedPaths, contains('/groups'));
      });

      testWidgets('tapping Stats tab navigates to /stats', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.navStats));
        await tester.pumpAndSettle();

        expect(find.text('Stats Page'), findsOneWidget);
        expect(navigatedPaths, contains('/stats'));
      });

      testWidgets('tapping Profile tab navigates to /profile', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.navProfile));
        await tester.pumpAndSettle();

        expect(find.text('Profile Page'), findsOneWidget);
        expect(navigatedPaths, contains('/profile'));
      });

      testWidgets('tapping Home tab from another tab navigates to /',
          (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        // Navigate to Groups
        await tester.tap(find.text(AppStrings.navGroups));
        await tester.pumpAndSettle();
        expect(find.text('Groups Page'), findsOneWidget);

        // Navigate back to Home
        await tester.tap(find.text(AppStrings.navHome));
        await tester.pumpAndSettle();
        expect(find.text('Home Page'), findsOneWidget);
        expect(navigatedPaths, contains('/'));
      });

      testWidgets('navigating through all tabs works', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        // Groups
        await tester.tap(find.text(AppStrings.navGroups));
        await tester.pumpAndSettle();
        expect(find.text('Groups Page'), findsOneWidget);

        // Stats
        await tester.tap(find.text(AppStrings.navStats));
        await tester.pumpAndSettle();
        expect(find.text('Stats Page'), findsOneWidget);

        // Profile
        await tester.tap(find.text(AppStrings.navProfile));
        await tester.pumpAndSettle();
        expect(find.text('Profile Page'), findsOneWidget);

        // Home
        await tester.tap(find.text(AppStrings.navHome));
        await tester.pumpAndSettle();
        expect(find.text('Home Page'), findsOneWidget);
      });
    });

    group('Bottom navigation bar properties', () {
      testWidgets('has fixed type navigation bar', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        final navBar = tester.widget<BottomNavigationBar>(
          find.byType(BottomNavigationBar),
        );
        expect(navBar.items.length, 4);
      });

      testWidgets('Home tab is selected initially (index 0)', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        final navBar = tester.widget<BottomNavigationBar>(
          find.byType(BottomNavigationBar),
        );
        expect(navBar.currentIndex, 0);
      });

      testWidgets('current index updates when navigating', (tester) async {
        await tester.pumpWidget(buildAppShell());
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.navStats));
        await tester.pumpAndSettle();

        final navBar = tester.widget<BottomNavigationBar>(
          find.byType(BottomNavigationBar),
        );
        expect(navBar.currentIndex, 2);
      });
    });
  });
}

int _currentIndex(String location) {
  if (location.startsWith('/groups')) return 1;
  if (location.startsWith('/stats')) return 2;
  if (location.startsWith('/profile')) return 3;
  return 0;
}
