import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/providers.dart';
import 'features/activity_page.dart';
import 'features/add_page.dart';
import 'features/quick_page.dart';
import 'features/friends_page.dart';
import 'features/bills_page.dart';
import 'features/detected_card.dart';
import 'features/home_page.dart';
import 'features/insights_page.dart';
import 'features/login_page.dart';
import 'features/lock_gate.dart';
import 'features/recurring_page.dart';
import 'features/review_page.dart';
import 'features/settings_page.dart';
import 'features/scan_page.dart';
import 'features/shell.dart';
import 'data/receipt_models.dart';
import 'features/txn_detail_page.dart';
import 'theme/theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final here = state.matchedLocation;
      if (auth == AuthStatus.unknown) return here == '/splash' ? null : '/splash';
      if (auth == AuthStatus.signedOut) return here == '/login' ? null : '/login';
      if (here == '/login' || here == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator(color: Brand.forest)))),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/recurring', builder: (_, _) => const RecurringPage()),
      GoRoute(path: '/add', builder: (_, _) => const AddPage()),
      GoRoute(path: '/quick', builder: (_, _) => const QuickPage()),
      GoRoute(path: '/detected', builder: (_, _) => const DetectedPage()),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsPage()),
      GoRoute(path: '/friends/:id', builder: (_, state) => FriendDetailPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/edit/:id', builder: (_, state) => AddPage(editId: state.pathParameters['id']!)),
      GoRoute(path: '/review', builder: (_, state) => ReviewPage(parsed: state.extra as ParsedReceipt?)),
      GoRoute(path: '/review/:id', builder: (_, state) => ReviewPage(editId: state.pathParameters['id']!)),
      GoRoute(path: '/txn/:id', builder: (_, state) => TxnDetailPage(id: state.pathParameters['id']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/activity', builder: (_, _) => const ActivityPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/scan', builder: (_, _) => const ScanPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/insights', builder: (_, _) => const InsightsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/bills', builder: (_, _) => const BillsPage())]),
        ],
      ),
    ],
  );
});

class CukupApp extends ConsumerWidget {
  const CukupApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(title: 'Cukup', debugShowCheckedModeBanner: false, theme: buildTheme(), routerConfig: ref.watch(routerProvider), builder: (context, child) => LockGate(child: child ?? const SizedBox.shrink()));
  }
}



