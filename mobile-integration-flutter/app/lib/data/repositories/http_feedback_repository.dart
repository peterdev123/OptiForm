import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/chat_result.dart';
import '../../domain/models/feedback_result.dart';
import '../../domain/models/squat_prompt_input.dart';
import '../../domain/repositories/feedback_repository.dart';

class HttpFeedbackRepository implements FeedbackRepository {
  final String baseUrl;
  final http.Client client;
  final Duration timeout;
  final String? apiKey;
  final String apiKeyHeader;

  HttpFeedbackRepository({
    required this.baseUrl,
    required this.client,
    this.timeout = const Duration(seconds: 360),
    this.apiKey,
    this.apiKeyHeader = 'x-api-key',
  });

  Map<String, String> get _requestHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final key = apiKey?.trim() ?? '';
    if (key.isNotEmpty) {
      headers[apiKeyHeader] = key;
    }
    return headers;
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
          headers: _requestHeaders,
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

    final response = await client
        .post(
          uri,
          headers: _requestHeaders,
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
