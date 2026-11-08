import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydlp/services/errors.dart';
import 'package:waydlp/theme.dart';
import 'package:waydlp/widgets/common.dart';

Widget host(Widget child) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('theme is AMOLED black with purple accent', (tester) async {
    final t = buildTheme();
    expect(t.scaffoldBackgroundColor, Palette.bg);
    expect(t.colorScheme.primary, Palette.accent);
  });

  testWidgets('failure view shows readable title and hides details until expanded', (tester) async {
    await tester.pumpWidget(host(FailureView(Failure.fromOutput('ERROR: [youtube] x: Private video'))));
    expect(find.text('The media is private'), findsOneWidget);
    expect(find.text('Technical details'), findsOneWidget);
    expect(find.textContaining('[youtube] x: Private video'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[youtube] x: Private video'), findsOneWidget);
  });

  testWidgets('progress shows indeterminate bar only when the total is unknown', (tester) async {
    await tester.pumpWidget(host(const JobProgress(fraction: 0.5, text: '1 MB of 2 MB')));
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
    await tester.pumpWidget(host(const JobProgress(fraction: null, text: 'Merging', animate: false)));
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0);
  });

  testWidgets('empty state and logo render', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            AppLogo(size: 48),
            EmptyState(icon: Icons.history, title: 'No history yet', hint: 'Finished downloads appear here.'),
          ],
        ),
      ),
    );
    expect(find.text('No history yet'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
  });
}
