import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podpisun/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('показує три панелі', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PodpisunApp()));
    await tester.pump();
    expect(find.text('Підписун'), findsOneWidget);
    expect(find.text('Перетягніть PDF або DOCX сюди'), findsOneWidget);
    expect(find.text('Виберіть PNG зліва'), findsOneWidget);
    expect(find.byTooltip('Додати PNG…'), findsOneWidget);
  });
}
