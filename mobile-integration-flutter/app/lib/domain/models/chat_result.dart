class ChatResult {
  const ChatResult({
    required this.answerText,
    required this.modelName,
    this.latencyMs,
  });

  final String answerText;
  final String modelName;
  final int? latencyMs;

  factory ChatResult.fromJson(Map<String, dynamic> json) {
    return ChatResult(
      answerText: (json['answer_text'] ?? '').toString(),
      modelName: (json['model_name'] ?? 'unknown').toString(),
      latencyMs: json['latency_ms'] is int ? json['latency_ms'] as int : null,
    );
  }
}
