import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/http_feedback_repository.dart';
import '../../widgets/opti_card.dart';

const String kBackendUrlPrefKey = 'optiform_backend_url_v1';
const String kDefaultBackendUrl = 'http://10.0.2.2:8000';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.onBackendUrlChanged});

  final ValueChanged<String>? onBackendUrlChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _urlController;
  final http.Client _httpClient = http.Client();
  bool _saving = false;
  String? _savedMessage;
  BackendReadiness _backendStatus = BackendReadiness.checking;
  bool _checkingBackend = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kBackendUrlPrefKey) ?? kDefaultBackendUrl;
    if (!mounted) return;
    setState(() {
      _urlController.text = saved;
    });
    await _refreshBackendStatus();
  }

  Future<void> _refreshBackendStatus() async {
    if (_checkingBackend) return;
    setState(() {
      _checkingBackend = true;
      _backendStatus = BackendReadiness.checking;
    });
    final repo = HttpFeedbackRepository(
      baseUrl: _urlController.text.trim(),
      client: _httpClient,
    );
    final status = await repo.checkReadiness();
    if (!mounted) return;
    setState(() {
      _backendStatus = status;
      _checkingBackend = false;
    });
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _saving = true;
      _savedMessage = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBackendUrlPrefKey, url);
    widget.onBackendUrlChanged?.call(url);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedMessage = 'Saved.';
    });
    await _refreshBackendStatus();
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _savedMessage = null);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _httpClient.close();
    super.dispose();
  }

  String _backendStatusLabel(BackendReadiness status) {
    switch (status) {
      case BackendReadiness.checking:
        return 'Checking connection…';
      case BackendReadiness.ready:
        return 'Connected';
      case BackendReadiness.warmingUp:
        return 'Loading model…';
      case BackendReadiness.unreachable:
        return 'Not reachable';
    }
  }

  Color _backendStatusColor(BackendReadiness status, ColorScheme scheme) {
    switch (status) {
      case BackendReadiness.checking:
        return scheme.onSurfaceVariant;
      case BackendReadiness.ready:
        return Colors.green;
      case BackendReadiness.warmingUp:
        return Colors.orange;
      case BackendReadiness.unreachable:
        return scheme.error;
    }
  }

  IconData _backendStatusIcon(BackendReadiness status) {
    switch (status) {
      case BackendReadiness.checking:
        return Icons.sync_outlined;
      case BackendReadiness.ready:
        return Icons.cloud_done_outlined;
      case BackendReadiness.warmingUp:
        return Icons.hourglass_top_outlined;
      case BackendReadiness.unreachable:
        return Icons.cloud_off_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.dns_outlined, size: 16, color: colors.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Coaching server', style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://192.168.x.x:8000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Same Wi‑Fi as your PC running the API.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _backendStatusColor(_backendStatus, colors)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _backendStatusIcon(_backendStatus),
                          size: 18,
                          color: _backendStatusColor(_backendStatus, colors),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _backendStatusLabel(_backendStatus),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _backendStatusColor(_backendStatus, colors),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _checkingBackend ? null : _refreshBackendStatus,
                          child: Text(_checkingBackend ? 'Checking…' : 'Retry'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                  if (_savedMessage != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 16, color: colors.primary),
                        const SizedBox(width: 6),
                        Text(_savedMessage!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colors.primary)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            OptiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.info_outline, size: 16, color: colors.primary),
                      ),
                      const SizedBox(width: 10),
                      Text('Quick setup', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Step(
                    number: '1',
                    text: 'PC and phone on the same Wi‑Fi (or phone hotspot).',
                  ),
                  _Step(
                    number: '2',
                    text: 'Start API on PC: uvicorn app:app --host 0.0.0.0 --port 8000',
                  ),
                  _Step(
                    number: '3',
                    text: 'Enter http://<PC_IP>:8000 above, Save, then Retry.',
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

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
