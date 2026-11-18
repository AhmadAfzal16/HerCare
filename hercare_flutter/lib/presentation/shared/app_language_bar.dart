import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/language_provider.dart';

/// Shared top control, outside the navigator so it is present on every route.
/// It blends into the page background and shows a small language pill.
class AppLanguageBar extends StatelessWidget {
  const AppLanguageBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Material(
          color: theme.scaffoldBackgroundColor,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 42,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 14),
                  // No Tooltip here: this bar sits above the Navigator, so
                  // there is no Overlay for a tooltip to use.
                  child: Semantics(
                    button: true,
                    label: language.isUrdu
                        ? 'Switch to English'
                        : 'اردو میں تبدیل کریں',
                    excludeSemantics: true,
                    child: Material(
                      color: scheme.surface,
                      shape: StadiumBorder(
                          side: BorderSide(color: scheme.outlineVariant)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: language.toggleLocale,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 34),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.translate_rounded,
                                    size: 16, color: scheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  language.isUrdu ? 'English' : 'اردو',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: scheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
