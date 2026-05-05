import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repositories/http_feedback_repository.dart';
import 'domain/models/chat_result.dart';
import 'domain/models/feedback_result.dart';
import 'domain/models/squat_prompt_input.dart';
import 'features/landing/opti_landing_page.dart';
import 'features/pose_processing/video_pose_analyzer.dart';
import 'features/rule_engine/thresholds.dart';
import 'features/video_input/media_input_service.dart';
import 'theme/app_theme.dart';
import 'widgets/metric_tile.dart';
import 'widgets/opti_button.dart';
import 'widgets/opti_card.dart';
import 'widgets/status_chip.dart';

String _stringifyError(Object error) {
  if (error is String) return error;
  return error.toString();
}

bool _isLikelyInlineAppMessage(String raw) {
  final lower = raw.toLowerCase();
  if (raw.length > 280) return false;
  if (lower.contains('socketexception')) return false;
  if (lower.contains('failed host lookup')) return false;
  if (lower.contains('clientexception')) return false;
  if (lower.contains('timeouterror')) return false;
  if (lower.contains('timeoutexception')) return false;
  if (raw.contains('API failed')) return false;
  if (lower.contains('formatexception')) return false;
  return true;
}

String _friendlyTechnicalSummary(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('timeouterror') || lower.contains('timeoutexception')) {
    return 'The request timed out. Check your connection and backend URL, then try again.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection timed out')) {
    return 'Could not reach the server. Confirm the backend URL and that your device and server are on the same network.';
  }
  if (raw.contains('Feedback API failed') || raw.contains('Chat API failed')) {
    return 'The coaching server returned an error. Check that the API is running and the URL is correct.';
  }
  if (lower.contains('formatexception')) {
    return 'Received an unexpected response from the server.';
  }
  return 'Something went wrong. Expand technical details below if you need them for debugging.';
}

String _errorSummaryForDisplay(Object error) {
  final raw = _stringifyError(error);
  if (_isLikelyInlineAppMessage(raw)) return raw;
  return _friendlyTechnicalSummary(raw);
}

void main() {
  // Silence Dart-side terminal logs from app/framework/plugins.
  debugPrint = (String? _, {int? wrapWidth}) {};
  runZonedGuarded(
    () {
      runApp(const SquatTrainerApp());
    },
    (error, stackTrace) {},
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {},
    ),
  );
}

class SquatTrainerApp extends StatefulWidget {
  const SquatTrainerApp({super.key});

  @override
  State<SquatTrainerApp> createState() => _SquatTrainerAppState();
}

class _SquatTrainerAppState extends State<SquatTrainerApp> {
  static const String _themeModeStorageKey = 'optiform_theme_mode_v1';
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeStorageKey);
    if (!mounted) return;
    setState(() {
      _themeMode = savedMode == 'light' ? ThemeMode.light : ThemeMode.dark;
    });
  }

  Future<void> _toggleThemeMode() async {
    final nextMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() {
      _themeMode = nextMode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeStorageKey, nextMode == ThemeMode.dark ? 'dark' : 'light');
  }

  bool get _isDarkMode => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiForm',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AppShell(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleThemeMode,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.isDarkMode,
    required this.onToggleTheme,
    super.key,
  });

  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const String _historyStorageKey = 'optiform_session_history_v1';
  static const String _landingSeenKey = 'optiform_landing_seen_v1';
  int _currentIndex = 0;
  List<SessionHistoryEntry> _historyEntries = const [];
  bool _showLanding = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyStorageKey) ?? const [];
    final landingSeen = prefs.getBool(_landingSeenKey) ?? false;
    final parsed = <SessionHistoryEntry>[];
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        parsed.add(SessionHistoryEntry.fromJson(map));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _historyEntries = parsed;
      _showLanding = !landingSeen;
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _historyEntries.map((entry) => jsonEncode(entry.toJson())).toList();
    await prefs.setStringList(_historyStorageKey, raw);
  }

  Future<void> _onSessionRecorded(SessionHistoryEntry entry) async {
    setState(() {
      _historyEntries = [entry, ..._historyEntries];
    });
    await _saveHistory();
  }

  Future<void> _onLandingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_landingSeenKey, true);
    if (!mounted) return;
    setState(() {
      _showLanding = false;
      _currentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLanding) {
      return OptiLandingPage(onStartNow: _onLandingCompleted);
    }

    final pages = <Widget>[
      IntroHomePage(
        onStartAnalysis: () {
          setState(() {
            _currentIndex = 1;
          });
        },
      ),
      FeedbackDemoPage(onSessionRecorded: _onSessionRecorded),
      HistoryPage(entries: _historyEntries),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: widget.onToggleTheme,
        tooltip: widget.isDarkMode ? 'Switch to light theme' : 'Switch to dark theme',
        child: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'Analyze',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}

class IntroHomePage extends StatelessWidget {
  const IntroHomePage({super.key, this.onStartAnalysis});

  final VoidCallback? onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OptiCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.fitness_center,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Welcome back', style: theme.textTheme.bodySmall),
                            Text('OptiForm Coach', style: theme.textTheme.titleLarge),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Track squat quality with clean rep analysis, practical feedback, and progress you can review anytime.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            OptiCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How it works', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _IntroStep(
                    number: '1',
                    title: 'Choose body type',
                    description: 'Select your body profile so analysis uses the right movement thresholds.',
                  ),
                  _IntroStep(
                    number: '2',
                    title: 'Upload your set',
                    description: 'Analyze a side-view squat video from camera capture or your files/gallery.',
                  ),
                  _IntroStep(
                    number: '3',
                    title: 'Get rep insights',
                    description: 'OptiForm detects landmarks, counts reps, and flags form issues per rep.',
                  ),
                  _IntroStep(
                    number: '4',
                    title: 'Refine technique',
                    description: 'Review feedback, visual checks, and coaching chat suggestions.',
                  ),
                ],
              ),
            ),
            OptiCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recording checklist', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _ChecklistItem(
                    icon: Icons.videocam_outlined,
                    text: 'Side view with full body in frame',
                  ),
                  _ChecklistItem(
                    icon: Icons.wb_sunny_outlined,
                    text: 'Stable camera and clear lighting',
                  ),
                  _ChecklistItem(
                    icon: Icons.repeat_outlined,
                    text: 'Continuous reps with brief pauses at the top',
                  ),
                  _ChecklistItem(
                    icon: Icons.cloud_outlined,
                    text:
                        'For AI coaching, keep your backend reachable (same Wi‑Fi or correct URL).',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            OptiButton(
              label: 'Open Analyze',
              onPressed: () {
                if (onStartAnalysis != null) {
                  onStartAnalysis!.call();
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeedbackDemoPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FeedbackDemoPage extends StatefulWidget {
  const FeedbackDemoPage({super.key, this.onSessionRecorded});

  final Future<void> Function(SessionHistoryEntry entry)? onSessionRecorded;

  @override
  State<FeedbackDemoPage> createState() => _FeedbackDemoPageState();
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.entries});

  final List<SessionHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Progress History')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: entries.isEmpty
            ? OptiCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('No sessions yet', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Run your first analysis from the Analyze tab to start tracking trends and rep quality over time.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent sessions', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  ...entries.map((entry) {
                    final when = DateTime.tryParse(entry.createdAtIso);
                    final dateText = when == null
                        ? entry.createdAtIso
                        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
                            '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
                    return OptiCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(dateText, style: theme.textTheme.labelLarge),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              MetricTile(label: 'Source', value: entry.source),
                              MetricTile(label: 'Body Type', value: entry.bodyType),
                              MetricTile(label: 'Reps', value: '${entry.repCount}'),
                              MetricTile(
                                label: 'Acceptable',
                                value: '${entry.acceptableCount}/${entry.repCount}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('Top correction: ${entry.topIssue}', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _RepFeedbackEntry {
  const _RepFeedbackEntry({
    required this.input,
    required this.result,
  });

  final SquatPromptInput input;
  final FeedbackResult result;
}

class _ChatMessageEntry {
  const _ChatMessageEntry({
    required this.isUser,
    required this.text,
    this.meta,
  });

  final bool isUser;
  final String text;
  final String? meta;
}

class SessionHistoryEntry {
  const SessionHistoryEntry({
    required this.createdAtIso,
    required this.source,
    required this.bodyType,
    required this.repCount,
    required this.acceptableCount,
    required this.topIssue,
  });

  final String createdAtIso;
  final String source;
  final String bodyType;
  final int repCount;
  final int acceptableCount;
  final String topIssue;

  Map<String, dynamic> toJson() {
    return {
      'created_at_iso': createdAtIso,
      'source': source,
      'body_type': bodyType,
      'rep_count': repCount,
      'acceptable_count': acceptableCount,
      'top_issue': topIssue,
    };
  }

  factory SessionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SessionHistoryEntry(
      createdAtIso: (json['created_at_iso'] ?? '').toString(),
      source: (json['source'] ?? 'unknown').toString(),
      bodyType: (json['body_type'] ?? 'N/A').toString(),
      repCount: (json['rep_count'] is int) ? json['rep_count'] as int : 0,
      acceptableCount: (json['acceptable_count'] is int) ? json['acceptable_count'] as int : 0,
      topIssue: (json['top_issue'] ?? 'No major issues').toString(),
    );
  }
}

enum _VideoInputSource { camera, gallery }

class _FeedbackDemoPageState extends State<FeedbackDemoPage> {
  final GlobalKey _errorBannerKey = GlobalKey();

  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://10.0.2.2:8000',
  );
  final VideoPoseAnalyzer _videoPoseAnalyzer = VideoPoseAnalyzer();
  final MediaInputService _mediaInputService = MediaInputService();
  final TextEditingController _chatController = TextEditingController();
  String _bodyType = 'N/A';
  XFile? _selectedVideo;
  _VideoInputSource? _selectedVideoSource;
  SquatPromptInput? _lastBuiltInput;
  double _videoProgress = 0;
  bool _analyzingVideo = false;
  final List<_RepFeedbackEntry> _repFeedbacks = [];
  List<PoseDebugSnapshot> _debugSnapshots = const [];

  bool _isLoading = false;
  Object? _error;
  FeedbackResult? _result;
  bool _chatLoading = false;
  final List<_ChatMessageEntry> _chatMessages = [];
  bool get _hasSelectedBodyType => _bodyType != 'N/A';

  void _setAnalyzeError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error;
    });
    _scheduleScrollErrorIntoView();
  }

  void _scheduleScrollErrorIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _errorBannerKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _chatController.dispose();
    _videoPoseAnalyzer.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final source = await showModalBottomSheet<_VideoInputSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Choose video source'),
                subtitle: Text('Record now or choose an existing squat video'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record with camera'),
                subtitle: const Text('Capture a new squat set'),
                onTap: () {
                  Navigator.of(sheetContext).pop(_VideoInputSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Choose from files/gallery'),
                subtitle: const Text('Pick an existing video from this device'),
                onTap: () {
                  Navigator.of(sheetContext).pop(_VideoInputSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    final video = source == _VideoInputSource.camera
        ? await _mediaInputService.pickSquatVideoFromCamera()
        : await _mediaInputService.pickSquatVideoFromGallery();
    if (!mounted) return;
    setState(() {
      _selectedVideo = video;
      _selectedVideoSource = video == null ? null : source;
    });
  }

  Future<FeedbackResult> _generateFeedbackForInput(SquatPromptInput input) async {
    final repo = HttpFeedbackRepository(
      baseUrl: _baseUrlController.text.trim(),
      client: http.Client(),
    );
    return repo.generateFeedback(
      instruction: 'Give short corrective coaching feedback for this squat rep.',
      input: input,
    );
  }

  Future<void> _sendChatQuestion() async {
    final question = _chatController.text.trim();
    if (question.isEmpty) return;
    setState(() {
      _chatLoading = true;
      _error = null;
      _chatMessages.add(_ChatMessageEntry(isUser: true, text: question));
    });
    _chatController.clear();

    final repo = HttpFeedbackRepository(
      baseUrl: _baseUrlController.text.trim(),
      client: http.Client(),
    );
    final recentSummaries = _repFeedbacks
        .map((entry) => entry.input.summaryText)
        .where((summary) => summary.trim().isNotEmpty)
        .toList();

    try {
      final chatResult = await repo.chatCoach(
        question: question,
        bodyType: _bodyType,
        recentRepSummaries: recentSummaries,
      );
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          _ChatMessageEntry(
            isUser: false,
            text: chatResult.answerText,
            meta: _chatMeta(chatResult),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          _ChatMessageEntry(
            isUser: false,
            text:
                "Couldn't reach the coach. ${_errorSummaryForDisplay(e)}",
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _chatLoading = false;
        });
      }
    }
  }

  String _chatMeta(ChatResult result) {
    if (result.latencyMs == null) return 'Model: ${result.modelName}';
    return 'Model: ${result.modelName} | ${result.latencyMs} ms';
  }

  Future<void> _analyzeSelectedVideo() async {
    if (!_hasSelectedBodyType) {
      _setAnalyzeError(
        'Body Type is required. Please select one before analysis.',
      );
      return;
    }
    if (_selectedVideo == null) {
      _setAnalyzeError('Please pick a video first.');
      return;
    }
    setState(() {
      _isLoading = true;
      _analyzingVideo = true;
      _videoProgress = 0;
      _error = null;
      _result = null;
      _repFeedbacks.clear();
      _debugSnapshots = const [];
    });

    try {
      final analysis = await _videoPoseAnalyzer.analyzeVideo(
        videoPath: _selectedVideo!.path,
        bodyType: _bodyType,
        thresholds: _selectedThresholds,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _videoProgress = progress;
          });
        },
      );
      if (mounted) {
        setState(() {
          _debugSnapshots = analysis.debugSnapshots;
        });
      }
      for (final rep in analysis.reps) {
        final feedback = await _generateFeedbackForInput(rep);
        if (!mounted) return;
        setState(() {
          _repFeedbacks.add(_RepFeedbackEntry(input: rep, result: feedback));
          _lastBuiltInput = rep;
          _result = feedback;
        });
      }
      if (analysis.reps.isNotEmpty) {
        await widget.onSessionRecorded?.call(
          SessionHistoryEntry(
            createdAtIso: DateTime.now().toIso8601String(),
            source: 'upload_video',
            bodyType: _bodyType,
            repCount: analysis.reps.length,
            acceptableCount: analysis.reps.where((rep) => rep.acceptable).length,
            topIssue: _topIssueFromReps(analysis.reps),
          ),
        );
      }
      if (analysis.reps.isEmpty && mounted) {
        _setAnalyzeError(
          'No reps were finalized from this video. Try a clearer side-view squat video.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _setAnalyzeError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _analyzingVideo = false;
        });
      }
    }
  }

  ThresholdProfile get _selectedThresholds => beginnerThresholds;

  String _topIssueFromReps(List<SquatPromptInput> reps) {
    var heels = 0;
    var torso = 0;
    var knees = 0;
    var elbows = 0;
    for (final rep in reps) {
      if (rep.heelsLifting.flag) heels += 1;
      if (rep.torsoForward.flag) torso += 1;
      if (rep.kneesForward.flag) knees += 1;
      if (rep.elbowFlaring.flag) elbows += 1;
    }
    final issues = <String, int>{
      'Heels Lifting': heels,
      'Torso Forward': torso,
      'Knees Forward': knees,
      'Elbow Flaring': elbows,
    };
    final sorted = issues.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty || sorted.first.value == 0) return 'No major issues';
    return sorted.first.key;
  }

  List<Widget> _buildAnalyzeSections(BuildContext context) {
    return [
      _buildHeaderSection(context),
      if (_isLoading || _analyzingVideo) _buildAnalysisProgressStrip(context),
      _buildConfigSection(context),
      _buildPrivacyFootnote(context),
      if (!kIsWeb) _buildCaptureSection(context),
      _buildFlowSection(context),
      if (_error != null)
        KeyedSubtree(
          key: _errorBannerKey,
          child: _AnalyzeErrorBanner(
            error: _error!,
            onDismiss: () {
              HapticFeedback.lightImpact();
              setState(() {
                _error = null;
              });
            },
          ),
        ),
      if (_result != null) _buildLatestFeedbackSection(context),
      if (_repFeedbacks.isNotEmpty) ..._buildPerRepFeedbackSection(context),
      _buildCoachChatSection(context),
      if (_debugSnapshots.isNotEmpty) _buildVisualCheckSection(context),
    ];
  }

  Widget _buildHeaderSection(BuildContext context) {
    final theme = Theme.of(context);
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analyze Session', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Upload a squat set to get rep-level form feedback. '
            'Use a stable side view and good lighting for best results.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.route_outlined,
                text: 'Mode: Upload Video',
              ),
              _InfoPill(
                icon: _hasSelectedBodyType ? Icons.check_circle_outline : Icons.error_outline,
                text: _hasSelectedBodyType ? 'Body type set' : 'Body type required',
                accent: _hasSelectedBodyType ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisProgressStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OptiCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _analyzingVideo ? 'Analyzing video frames…' : 'Working…',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: _analyzingVideo ? _videoProgress.clamp(0.0, 1.0) : null,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          if (_analyzingVideo) ...[
            const SizedBox(height: 6),
            Text(
              '${(100 * _videoProgress).round()}% · pose + reps on device',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrivacyFootnote(BuildContext context) {
    final theme = Theme.of(context);
    return OptiCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Video and pose landmarks are processed on this device. '
              'AI feedback and coach chat send rep summaries to the backend URL above — use a network you trust.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Configuration',
            subtitle: 'Set backend and body profile',
            icon: Icons.tune,
          ),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Backend Base URL',
              hintText: 'http://10.0.2.2:8000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _bodyType,
            decoration: const InputDecoration(
              labelText: 'Body Type (Required)',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'N/A', child: Text('N/A')),
              DropdownMenuItem(
                value: 'LONGER_LEGS',
                child: Text('Longer Legs'),
              ),
              DropdownMenuItem(
                value: 'LONGER_TORSO',
                child: Text('Longer Torso'),
              ),
              DropdownMenuItem(
                value: 'BALANCED',
                child: Text('Balanced'),
              ),
            ],
            onChanged: _isLoading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _bodyType = value;
                      _error = null;
                    });
                  },
          ),
          if (!_hasSelectedBodyType) ...[
            const SizedBox(height: 6),
            Text(
              'Select a body type to proceed with video analysis.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCaptureSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Input Source',
            subtitle: 'Record or pick a squat video for analysis',
            icon: Icons.video_camera_back_outlined,
          ),
          SizedBox(
            child: OptiButton(
              label: _selectedVideo == null ? 'Pick Squat Video' : 'Video Selected',
              variant: OptiButtonVariant.outlined,
              onPressed: _isLoading || _analyzingVideo ? null : _pickVideo,
            ),
          ),
          if (_selectedVideo != null) ...[
            const SizedBox(height: 4),
            Text(
              'Selected video: ${_selectedVideo!.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Source: ${_selectedVideoSource == _VideoInputSource.camera ? 'Camera capture' : 'Files/Gallery'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              child: OptiButton(
                onPressed: _isLoading ? null : _analyzeSelectedVideo,
                label: _analyzingVideo
                    ? 'Analyzing video... ${(100 * _videoProgress).round()}%'
                    : 'Analyze Uploaded Video',
                loading: _isLoading && _selectedVideo != null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlowSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Pipeline',
            subtitle: 'Pose extraction -> rep detection -> AI feedback',
            icon: Icons.account_tree_outlined,
          ),
          Text(
            'Flow: Upload video -> on-device metrics (body-type thresholds) -> feedback per rep.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_lastBuiltInput != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last Summary: ${_lastBuiltInput!.summaryText}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLatestFeedbackSection(BuildContext context) {
    final theme = Theme.of(context);
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Latest Feedback',
            subtitle: 'Most recent model output for your current rep',
            icon: Icons.auto_awesome_outlined,
          ),
          Text(
            'Model: ${_result!.modelName}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                label: _lastBuiltInput?.acceptable == true ? 'Acceptable' : 'Needs Work',
                color: _lastBuiltInput?.acceptable == true ? Colors.green : Colors.orange,
              ),
              MetricTile(
                label: 'Depth',
                value: _lastBuiltInput != null ? '${_lastBuiltInput!.depth}' : '-',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_result!.feedbackText),
          if (_result!.latencyMs != null) ...[
            const SizedBox(height: 8),
            Text('Latency: ${_result!.latencyMs} ms'),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildPerRepFeedbackSection(BuildContext context) {
    return [
      const SizedBox(height: 4),
      Text(
        'Per-rep feedback',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      ..._repFeedbacks.map((entry) {
        return OptiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rep ${entry.input.repNumber}'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(
                    label: entry.input.acceptable ? 'Acceptable' : 'Needs Work',
                    color: entry.input.acceptable ? Colors.green : Colors.orange,
                  ),
                  MetricTile(label: 'Depth', value: '${entry.input.depth}'),
                ],
              ),
              const SizedBox(height: 8),
              Text(entry.result.feedbackText),
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildCoachChatSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Coach Chat',
            subtitle: 'Ask about movement patterns and practical corrections',
            icon: Icons.chat_bubble_outline,
          ),
          TextField(
            controller: _chatController,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) {
              if (!_chatLoading) {
                _sendChatQuestion();
              }
            },
            decoration: InputDecoration(
              hintText: 'e.g., Why were my last reps flagged for knees forward?',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _chatLoading ? null : _sendChatQuestion,
                icon: const Icon(Icons.send),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_chatLoading) const LinearProgressIndicator(),
          if (_chatMessages.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._chatMessages.map((message) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: message.isUser
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.isUser ? 'You' : 'OptiForm Coach',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(message.text),
                    if (message.meta != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        message.meta!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildVisualCheckSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Pose Landmark Check',
            subtitle: 'Frame snapshots with landmark overlays for quick validation',
            icon: Icons.visibility_outlined,
          ),
          ..._debugSnapshots.map(
            (snapshot) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PoseDebugCard(snapshot: snapshot),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analyze')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildAnalyzeSections(context),
        ),
      ),
    );
  }
}

class _AnalyzeErrorBanner extends StatelessWidget {
  const _AnalyzeErrorBanner({
    required this.error,
    required this.onDismiss,
  });

  final Object error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = _stringifyError(error);
    final summary = _errorSummaryForDisplay(error);
    final showDetail = summary.trim() != detail.trim();

    return OptiCard(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    summary,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (showDetail)
            Padding(
              padding: const EdgeInsets.only(left: 32, right: 4),
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  dense: true,
                  title: Text(
                    'Technical details',
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                  ),
                  children: [
                    SelectableText(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.text,
    this.accent,
  });

  final IconData icon;
  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoseDebugCard extends StatelessWidget {
  const _PoseDebugCard({required this.snapshot});

  final PoseDebugSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rep ${snapshot.repNumber} - Frame @ ${snapshot.timeMs} ms (${snapshot.side} side)'),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: snapshot.imageSize.width / snapshot.imageSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(snapshot.imageBytes, fit: BoxFit.cover),
                  CustomPaint(
                    painter: _LandmarkOverlayPainter(
                      joints: snapshot.joints,
                      connections: snapshot.connections,
                      metricLabels: snapshot.metricLabels,
                      sourceSize: snapshot.imageSize,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandmarkOverlayPainter extends CustomPainter {
  const _LandmarkOverlayPainter({
    required this.joints,
    required this.connections,
    required this.metricLabels,
    required this.sourceSize,
  });

  final Map<String, Offset> joints;
  final List<List<String>> connections;
  final Map<String, String> metricLabels;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = Colors.limeAccent
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final scaleX = size.width / sourceSize.width;
    final scaleY = size.height / sourceSize.height;

    Offset scaled(Offset p) => Offset(p.dx * scaleX, p.dy * scaleY);

    for (final edge in connections) {
      if (edge.length != 2) continue;
      final p1 = joints[edge[0]];
      final p2 = joints[edge[1]];
      if (p1 == null || p2 == null) continue;
      canvas.drawLine(scaled(p1), scaled(p2), linePaint);
    }

    for (final p in joints.values) {
      canvas.drawCircle(scaled(p), 3.0, pointPaint);
    }

    for (final entry in metricLabels.entries) {
      final anchor = joints[entry.key];
      if (anchor == null) continue;
      final screen = scaled(anchor);
      _drawLabel(canvas, screen + const Offset(6, -6), entry.value);
    }
  }

  void _drawLabel(Canvas canvas, Offset position, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromLTWH(
      position.dx - 2,
      position.dy - 1,
      textPainter.width + 4,
      textPainter.height + 2,
    );
    final bg = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      bg,
    );
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _LandmarkOverlayPainter oldDelegate) {
    return oldDelegate.joints != joints ||
        oldDelegate.connections != connections ||
        oldDelegate.metricLabels != metricLabels ||
        oldDelegate.sourceSize != sourceSize;
  }
}
