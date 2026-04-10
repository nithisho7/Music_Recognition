import 'package:flutter_test/flutter_test.dart';
import 'package:soundmatch/app/soundmatch_app.dart';

void main() {
  testWidgets('SoundMatch smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SoundMatchApp());
    expect(find.text('Music Recognition and Automation System'), findsOneWidget);
  });
}
