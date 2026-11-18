import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/language_provider.dart';

/// Shared top control, outside the navigator so it is present on every route.
class AppLanguageBar extends StatelessWidget {
  const AppLanguageBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>();
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 40,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextButton.icon(
                    onPressed: language.toggleLocale,
                    icon: const Icon(Icons.language_rounded, size: 18),
                    label: Text(language.isUrdu ? 'English' : 'اردو'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(72, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
