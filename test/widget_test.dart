import 'package:flutter_test/flutter_test.dart';
import 'package:sailor/main.dart';

void main() {
  testWidgets('SailorApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SailorApp());
    // Basic smoke test — app should render without crashing
    expect(find.byType(SailorApp), findsOneWidget);
  });
}
