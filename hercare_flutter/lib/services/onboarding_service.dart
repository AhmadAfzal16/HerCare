import 'package:dio/dio.dart';

import '../data/models/onboarding_model.dart';
import '../data/services/api_service.dart';

class OnboardingService {
  OnboardingService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<void> complete(OnboardingData data) async {
    try {
      await _api.client.put('/onboarding', data: data.toJson());
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map<String, dynamic>) {
        final errors = body['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          throw Exception(
            (errors.first as Map)['message'] ??
                'Please review your information.',
          );
        }
        final message = body['message'];
        if (message is String) throw Exception(message);
      }
      throw Exception('Could not save onboarding. Please try again.');
    }
  }
}
