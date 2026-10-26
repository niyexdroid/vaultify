import 'package:flutter/widgets.dart';

/// Content width cap: keeps a screen's content at a readable width and
/// centres it in wider windows, as in SPEC.md "Window and layout sizes"
/// ("content width capped at 600 and centred").
///
/// The desktop window is resizable, so without this the generator's fields
/// and buttons stretch the full width of a maximised window and the rows of
/// the saved list run so wide they are hard to scan.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  /// Matches the cap named in SPEC.md.
  static const double maxWidth = 600;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
