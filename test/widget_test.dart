import 'package:film2watch/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('zeigt die fünf Hauptbereiche in der Bottom-Navigation', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Film2WatchApp()));

    expect(find.text('Swipe'), findsWidgets);
    expect(find.text('Matches'), findsOneWidget);
    expect(find.text('Gruppen'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('wechselt beim Tippen auf einen Tab den sichtbaren Bereich', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Film2WatchApp()));

    expect(find.text('Swipe-Bereich'), findsOneWidget);

    await tester.tap(find.text('Matches'));
    await tester.pumpAndSettle();

    expect(find.text('Matches-Bereich'), findsOneWidget);
  });
}
