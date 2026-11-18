import 'dart:convert';

import 'package:flutter/services.dart';

class MeditationCue {
  const MeditationCue(
      {required this.en, required this.ur, required this.asset});
  final String en;
  final String ur;
  final String asset;
  String text(bool isUrdu) => isUrdu ? ur : en;
  String audio(bool isUrdu) =>
      'assets/audio/meditation/${isUrdu ? 'ur' : 'en'}_$asset.m4a';
}

class MeditationGuides {
  static Future<Map<String, List<MeditationCue>>>? _cached;
  static Map<String, List<MeditationCue>>? _loaded;
  static Map<String, List<MeditationCue>>? get loaded => _loaded;
  static Future<Map<String, List<MeditationCue>>> load() =>
      _cached ??= _load().catchError((Object error) {
        _cached = null;
        throw error;
      });

  static Future<Map<String, List<MeditationCue>>> _load() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/meditation_guides.json'))
            as Map;
    final activities = data['activities'] as Map;
    const allowed = {'body_scan', 'muscle_relaxation', 'mindfulness'};
    if (data['version'] != 1 ||
        activities.length != allowed.length ||
        !allowed.every(activities.containsKey)) {
      throw const FormatException('Invalid meditation catalog');
    }
    _loaded = Map.unmodifiable(activities.map((id, rawSteps) {
      final steps = rawSteps as List;
      if (steps.length != 4) {
        throw const FormatException('Invalid meditation steps');
      }
      return MapEntry(
          id as String,
          List<MeditationCue>.unmodifiable(steps.asMap().entries.map((entry) {
            final step = entry.value as Map;
            final en = step['en'];
            final ur = step['ur'];
            if (en is! String ||
                ur is! String ||
                en.isEmpty ||
                ur.isEmpty ||
                en.length > 1000 ||
                ur.length > 1000) {
              throw const FormatException('Invalid meditation captions');
            }
            return MeditationCue(en: en, ur: ur, asset: '${id}_${entry.key}');
          })));
    }));
    return _loaded!;
  }
}
