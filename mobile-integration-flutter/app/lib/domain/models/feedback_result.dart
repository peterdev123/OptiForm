class FeedbackResult {
  final String feedbackText;
  final String modelName;
  final int? latencyMs;

  const FeedbackResult({
    required this.feedbackText,
    required this.modelName,
    this.latencyMs,
  });

  factory FeedbackResult.fromJson(Map<String, dynamic> json) {
    return FeedbackResult(
      feedbackText: (json['feedback_text'] ?? '').toString(),
      modelName: (json['model_name'] ?? 'unknown').toString(),
      latencyMs: json['latency_ms'] is int ? json['latency_ms'] as int : null,
    );
  }
}
