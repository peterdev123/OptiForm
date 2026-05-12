import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/chat_result.dart';
import '../../domain/models/feedback_result.dart';
import '../../domain/models/squat_prompt_input.dart';
import '../../domain/repositories/feedback_repository.dart';

enum BackendReadiness {
  checking,
  ready,
  warmingUp,
  unreachable,
}

class HttpFeedbackRepository implements FeedbackRepository {
  final String baseUrl;
  final http.Client client;
  final Duration timeout;

  HttpFeedbackRepository({
    required this.baseUrl,
    required this.client,
    this.timeout = const Duration(seconds: 360),
  });

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  static const Duration _healthCheckTimeout = Duration(seconds: 8);

  Future<BackendReadiness> checkReadiness() async {
    try {
      final healthUri = Uri.parse('$baseUrl/health');
      final healthResponse = await client
          .get(healthUri)
          .timeout(_healthCheckTimeout);
      if (healthResponse.statusCode < 200 || healthResponse.statusCode >= 300) {
        return BackendReadiness.unreachable;
      }

      final readyUri = Uri.parse('$baseUrl/health/ready');
      final readyResponse = await client
          .get(readyUri)
          .timeout(_healthCheckTimeout);
      if (readyResponse.statusCode == 200) {
        return BackendReadiness.ready;
      }
      if (readyResponse.statusCode == 503) {
        return BackendReadiness.warmingUp;
      }
      return BackendReadiness.unreachable;
    } catch (_) {
      return BackendReadiness.unreachable;
    }
  }

  @override
  Future<FeedbackResult> generateFeedback({
    required String instruction,
    required SquatPromptInput input,
    String modelVariant = 'finetuned',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/feedback/generate');
    final body = {
      'instruction': instruction,
      'input_summary': input.summaryText,
      'model_variant': modelVariant,
      'structured_input': input.toJson(),
    };

    final response = await client
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Feedback API failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return FeedbackResult.fromJson(payload);
  }

  Future<ChatResult> chatCoach({
    required String question,
    required String bodyType,
    List<String> recentRepSummaries = const [],
    String modelVariant = 'finetuned',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/chat');
    final body = {
      'question': question,
      'body_type': bodyType,
      'recent_rep_summaries': recentRepSummaries,
      'model_variant': modelVariant,
    };
// TODO: add logging
    final response = await client
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Chat API failed (${response.statusCode}): ${response.body}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatResult.fromJson(payload);
  }
}
