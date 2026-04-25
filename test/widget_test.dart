import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/main.dart';

void main() {
  testWidgets('missing config app renders guidance', (WidgetTester tester) async {
    await tester.pumpWidget(const MissingConfigApp());

    expect(find.text('Balık Uygulaması'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
