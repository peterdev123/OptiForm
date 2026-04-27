import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repositories/http_feedback_repository.dart';
import 'domain/models/chat_result.dart';
import 'domain/models/feedback_result.dart';
import 'domain/models/squat_prompt_input.dart';
import 'features/pose_processing/live_pose_stream_service.dart';
import 'features/pose_processing/video_pose_analyzer.dart';
import 'features/rule_engine/thresholds.dart';
import 'features/video_input/media_input_service.dart';
import 'theme/app_theme.dart';
import 'widgets/metric_tile.dart';
import 'widgets/opti_button.dart';
import 'widgets/opti_card.dart';
import 'widgets/status_chip.dart';

void main() {
  // Silence Dart-side terminal logs from app/framework/plugins.
  debugPrint = (String? _, {int? wrapWidth}) {};
  runZonedGuarded(
    () {
      runApp(const SquatTrainerApp());
    },
    (_, __) {},
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, ____) {},
    ),
  );
}

class SquatTrainerApp extends StatelessWidget {
  const SquatTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiForm',
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const String _historyStorageKey = 'optiform_session_history_v1';
  int _currentIndex = 0;
  List<SessionHistoryEntry> _historyEntries = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyStorageKey) ?? const [];
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

  @override
  Widget build(BuildContext context) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('OptiForm')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OptiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.fitness_center,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Welcome to OptiForm', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your AI-powered squat form coach. Analyze every rep, catch common faults, and get practical feedback based on your movement data.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            OptiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How it works', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _IntroStep(
                    number: '1',
                    title: 'Select Body Type',
                    description: 'Pick your body type before analysis to apply the proper thresholds.',
                  ),
                  _IntroStep(
                    number: '2',
                    title: 'Upload or Go Live',
                    description: 'Use a side-view squat video or start live camera tracking.',
                  ),
                  _IntroStep(
                    number: '3',
                    title: 'Rep-Level Analysis',
                    description: 'OptiForm extracts pose landmarks, counts reps, and detects form issues.',
                  ),
                  _IntroStep(
                    number: '4',
                    title: 'Review and Improve',
                    description: 'See visual checks, per-rep feedback, and ask the coach chat for tips.',
                  ),
                ],
              ),
            ),
            OptiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Best recording setup', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('- Side view with full body visible', style: Theme.of(context).textTheme.bodySmall),
                  Text('- Stable camera and clear lighting', style: Theme.of(context).textTheme.bodySmall),
                  Text('- Perform continuous reps with pauses only at top', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 6),
            OptiButton(
              label: 'Start Analysis',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
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
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: entries.isEmpty
            ? OptiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session History', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'No sessions yet. Analyze a workout in the Analyze tab to start building your history.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session History', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...entries.map((entry) {
                    final when = DateTime.tryParse(entry.createdAtIso);
                    final dateText = when == null
                        ? entry.createdAtIso
                        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
                            '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
                    return OptiCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dateText, style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
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
                          const SizedBox(height: 8),
                          Text('Top issue: ${entry.topIssue}'),
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

enum _AnalysisSource { uploadVideo, liveCamera }

class _FeedbackDemoPageState extends State<FeedbackDemoPage> {
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://10.0.2.2:8000',
  );
  final LivePoseStreamService _livePoseService = LivePoseStreamService();
  final VideoPoseAnalyzer _videoPoseAnalyzer = VideoPoseAnalyzer();
  final MediaInputService _mediaInputService = MediaInputService();
  final TextEditingController _chatController = TextEditingController();
  _AnalysisSource _analysisSource = _AnalysisSource.uploadVideo;
  String _bodyType = 'N/A';
  XFile? _selectedVideo;
  bool _liveStreaming = false;
  SquatPromptInput? _lastBuiltInput;
  SquatPromptInput? _lastFinalizedRepInput;
  int _finalizedRepCount = 0;
  double _videoProgress = 0;
  bool _analyzingVideo = false;
  final List<_RepFeedbackEntry> _repFeedbacks = [];
  List<PoseDebugSnapshot> _debugSnapshots = const [];

  bool _isLoading = false;
  String? _error;
  FeedbackResult? _result;
  bool _chatLoading = false;
  final List<_ChatMessageEntry> _chatMessages = [];
  bool get _hasSelectedBodyType => _bodyType != 'N/A';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _chatController.dispose();
    _livePoseService.dispose();
    _videoPoseAnalyzer.dispose();
    super.dispose();
  }

  Future<void> _startLivePose() async {
    if (!_hasSelectedBodyType) {
      setState(() {
        _error = 'Body Type is required. Please select one before starting.';
      });
      return;
    }
    try {
      await _livePoseService.start(
        bodyType: _bodyType,
        thresholds: _selectedThresholds,
        onInputUpdated: (input) {
          if (!mounted) return;
          setState(() {
            _lastBuiltInput = input;
          });
        },
        onRepFinalized: (repInput) {
          if (!mounted) return;
          setState(() {
            _lastFinalizedRepInput = repInput;
            _finalizedRepCount += 1;
          });
          _generateFeedbackForInput(repInput);
        },
      );
      if (!mounted) return;
      setState(() {
        _liveStreaming = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Live pose start failed: $e';
      });
    }
  }

  Future<void> _stopLivePose() async {
    await _livePoseService.stop();
    if (!mounted) return;
    setState(() {
      _liveStreaming = false;
    });
  }

  Future<void> _pickVideo() async {
    final video = await _mediaInputService.pickSquatVideo();
    if (!mounted) return;
    setState(() {
      _selectedVideo = video;
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
            text: 'Coach chat failed: $e',
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
      setState(() {
        _error = 'Body Type is required. Please select one before analysis.';
      });
      return;
    }
    if (_selectedVideo == null) {
      setState(() {
        _error = 'Please pick a video first.';
      });
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
    #check
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
        setState(() {
          _error =
              'No reps were finalized from this video. Try a clearer side-view squat video.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
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

  Future<void> _generateFromLatestLiveRep() async {
    final input = _lastFinalizedRepInput ?? _livePoseService.lastInput;
    if (input == null) {
      setState(() {
        _error = 'No live rep input available yet. Start live pose first.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _generateFeedbackForInput(input);
      if (!mounted) return;
      setState(() {
        _lastBuiltInput = input;
        _result = result;
        _repFeedbacks.add(_RepFeedbackEntry(input: input, result: result));
      });
      await widget.onSessionRecorded?.call(
        SessionHistoryEntry(
          createdAtIso: DateTime.now().toIso8601String(),
          source: 'live_camera',
          bodyType: _bodyType,
          repCount: 1,
          acceptableCount: input.acceptable ? 1 : 0,
          topIssue: _topIssueFromReps([input]),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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
      _buildConfigSection(context),
      if (!kIsWeb) _buildCaptureSection(context),
      _buildFlowSection(context),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_result != null) _buildLatestFeedbackSection(context),
      if (_repFeedbacks.isNotEmpty) ..._buildPerRepFeedbackSection(context),
      _buildCoachChatSection(context),
      if (_debugSnapshots.isNotEmpty) _buildVisualCheckSection(context),
    ];
  }

  Widget _buildHeaderSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OptiForm Analysis', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Upload or stream a squat set, detect rep-level issues, then get coaching feedback.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Mode: ${_analysisSource == _AnalysisSource.uploadVideo ? 'Upload Video' : 'Live Camera'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            _hasSelectedBodyType ? 'Body Type: Selected' : 'Body Type: Required',
            style: TextStyle(
              color: _hasSelectedBodyType ? Colors.green : Colors.orange,
              fontSize: 13,
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
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Backend Base URL',
              hintText: 'http://10.0.2.2:8000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_AnalysisSource>(
            segments: const [
              ButtonSegment<_AnalysisSource>(
                value: _AnalysisSource.uploadVideo,
                label: Text('Upload Video'),
              ),
              ButtonSegment<_AnalysisSource>(
                value: _AnalysisSource.liveCamera,
                label: Text('Live Camera'),
              ),
            ],
            selected: {_analysisSource},
            onSelectionChanged: (selection) {
              setState(() {
                _analysisSource = selection.first;
              });
            },
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
              'Select a body type to proceed with video or live analysis.',
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
          if (_analysisSource == _AnalysisSource.uploadVideo) ...[
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
              const SizedBox(height: 8),
              SizedBox(
                child: OptiButton(
                  onPressed: _isLoading ? null : _analyzeSelectedVideo,
                  label: _analyzingVideo
                      ? 'Analyzing video... ${(100 * _videoProgress).round()}%'
                      : 'Analyze Uploaded Video',
                ),
              ),
            ],
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OptiButton(
                    variant: OptiButtonVariant.outlined,
                    onPressed: _isLoading || _liveStreaming ? null : _startLivePose,
                    label: 'Start Live Pose',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OptiButton(
                    variant: OptiButtonVariant.outlined,
                    onPressed: _isLoading || !_liveStreaming ? null : _stopLivePose,
                    label: 'Stop Live Pose',
                  ),
                ),
              ],
            ),
            if (_livePoseService.controller != null) ...[
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: _livePoseService.controller!.value.aspectRatio,
                child: CameraPreview(_livePoseService.controller!),
              ),
              const SizedBox(height: 8),
              Text(
                'Finalized reps: $_finalizedRepCount',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_lastFinalizedRepInput != null)
                Text(
                  'Last finalized summary: ${_lastFinalizedRepInput!.summaryText}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
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
          Text(
            'Flow: Upload/Live -> on-device pose metrics (mode/body-type thresholds) -> AI feedback per rep.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_lastBuiltInput != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last Summary: ${_lastBuiltInput!.summaryText}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            child: OptiButton(
              onPressed: _analysisSource == _AnalysisSource.liveCamera
                  ? (_isLoading ? null : _generateFromLatestLiveRep)
                  : null,
              label: _isLoading ? 'Generating...' : 'Generate From Latest Live Rep',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestFeedbackSection(BuildContext context) {
    return OptiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Latest Feedback',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Model: ${_result!.modelName}',
            style: Theme.of(context).textTheme.bodySmall,
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
        'Per-rep feedbacks',
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
          Text(
            'Coach Chat',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Ask about history, tips, and form patterns using your recent rep context.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
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
          Text(
            'Pose Landmark Visual Check',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'One captured frame per finalized rep with detected landmarks overlaid.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
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
      appBar: AppBar(title: const Text('OptiForm')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildAnalyzeSections(context),
        ),
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
