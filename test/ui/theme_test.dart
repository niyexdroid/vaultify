import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/app.dart';
import 'package:vaultify/ui/theme.dart';

void main() {
  test('light tokens match SPEC.md', () {
    const c = VaultifyColors.light;
    expect(c.primary, const Color(0xFF1A9E5B));
    expect(c.onPrimary, const Color(0xFFFFFFFF));
    expect(c.primarySoft, const Color(0xFFDCF2E5));
    expect(c.background, const Color(0xFFFFFFFF));
    expect(c.surface, const Color(0xFFF5F6F7));
    expect(c.border, const Color(0xFFE3E5E8));
    expect(c.text, const Color(0xFF16181A));
    expect(c.textSecondary, const Color(0xFF5F6368));
    expect(c.weak, const Color(0xFFD93F3F));
    expect(c.fair, const Color(0xFFD9902B));
    expect(c.strong, c.primary);
  });

  test('dark tokens match SPEC.md', () {
    const c = VaultifyColors.dark;
    expect(c.primary, const Color(0xFF3DBE7A));
    expect(c.onPrimary, const Color(0xFF08210F));
    expect(c.primarySoft, const Color(0xFF173B28));
    expect(c.background, const Color(0xFF111315));
    expect(c.surface, const Color(0xFF1B1E21));
    expect(c.border, const Color(0xFF2C3034));
    expect(c.text, const Color(0xFFECEEF0));
    expect(c.textSecondary, const Color(0xFFA0A6AC));
    expect(c.weak, const Color(0xFFF26B6B));
    expect(c.fair, const Color(0xFFE8A94E));
    expect(c.strong, c.primary);
  });

  for (final brightness in Brightness.values) {
    testWidgets('app follows device ${brightness.name} mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const VaultifyApp());

      final context = tester.element(find.byType(Scaffold));
      final expected =
          brightness == Brightness.dark ? VaultifyColors.dark : VaultifyColors.light;
      expect(Theme.of(context).brightness, brightness);
      expect(context.colors.background, expected.background);
      expect(Theme.of(context).scaffoldBackgroundColor, expected.background);
      expect(find.text('Vaultify'), findsOneWidget);
    });
  }
}
