import 'package:flutter_test/flutter_test.dart';

import 'package:voice_to_sheet_frontend/app/voice_to_sheet_app.dart';

void main() {
  testWidgets('app starts on login screen', (tester) async {
    await tester.pumpWidget(const VoiceToSheetApp());

    expect(find.text('VoiceToSheet'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
