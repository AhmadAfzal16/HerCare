int _revision(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  if (number == null ||
      !number.isFinite ||
      number < 1 ||
      number > 1000000 ||
      number != number.roundToDouble()) {
    throw const FormatException('Invalid transcript revision');
  }
  return number.toInt();
}

class VoiceTranscript {
  VoiceTranscript.fromJson(Map<String, dynamic> json)
      : journalId = json['journal_id'] as String,
        status = json['status'] as String,
        revision = _revision(json['revision']),
        draft = json['draft'] as String?,
        safetyHint = json['safety_hint'] == true,
        modelVersion = json['model_version'] as String?,
        failureCode = json['failure_code'] as String? {
    if (!['queued', 'processing', 'review', 'confirmed', 'failed', 'no_speech']
            .contains(status) ||
        revision < 1 ||
        (draft?.length ?? 0) > 5000 ||
        (status == 'review' && (draft == null || draft!.trim().isEmpty)) ||
        (status != 'review' && draft != null)) {
      throw const FormatException('Invalid private transcript response');
    }
  }
  final String journalId, status;
  final int revision;
  final String? draft, modelVersion, failureCode;
  final bool safetyHint;
  bool get pending => status == 'queued' || status == 'processing';
}
