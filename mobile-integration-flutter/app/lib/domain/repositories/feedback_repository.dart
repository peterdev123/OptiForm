import '../models/feedback_result.dart';
import '../models/squat_prompt_input.dart';

abstract class FeedbackRepository {
  Future<FeedbackResult> generateFeedback({
    required String instruction,
    required SquatPromptInput input,
    String modelVariant = 'finetuned',
  });
}
