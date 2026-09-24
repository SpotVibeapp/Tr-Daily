import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/state/app_state.dart';
import 'package:tr_daily/storage/local_store.dart';
import 'package:tr_daily/ui/app.dart';

void main() {
  testWidgets('app boots to dashboard with paper mode', (tester) async {
    final state = AppState(store: MemoryStore());
    await state.init();

    await tester.pumpWidget(TrDailyApp(state: state));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Tr-Daily'), findsOneWidget);
    expect(find.text('PAPER'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);

    // Bottom nav reaches other screens.
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('BROKER & BANK CONNECTION'), findsOneWidget);

    // Unmount before disposing the state to keep listener teardown clean.
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
