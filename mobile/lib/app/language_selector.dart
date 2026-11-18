import 'package:flutter/material.dart';

/// Small, bilingual control intentionally readable before a language has been
/// selected. The parent owns persistence and any surrounding loading state.
class LanguageSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  final bool compact;
  const LanguageSelector(
      {super.key,
      required this.value,
      required this.onChanged,
      this.compact = false});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
        ChoiceChip(
            label: const Text('中文'),
            selected: value != 'en',
            onSelected: onChanged == null ? null : (_) => onChanged!('zh')),
        ChoiceChip(
            label: const Text('English'),
            selected: value == 'en',
            onSelected: onChanged == null ? null : (_) => onChanged!('en')),
      ]);
}
