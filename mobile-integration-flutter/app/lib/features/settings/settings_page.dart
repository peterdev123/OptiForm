import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _saving = false;
  String? _savedMessage;

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
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _savedMessage = null);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
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
                            Text('Backend Connection', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              'Set the URL of your local AI backend server.',
                              style: theme.textTheme.bodySmall,
                            ),
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
                      labelText: 'Backend Base URL',
                      hintText: 'http://192.168.x.x:8000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use your PC\'s hotspot IP, e.g. http://192.168.43.25:8000',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
                      Text('How to connect', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Step(
                    number: '1',
                    text: 'Enable a mobile hotspot on any phone/device.',
                  ),
                  _Step(
                    number: '2',
                    text: 'Connect your backend PC to that hotspot Wi‑Fi.',
                  ),
                  _Step(
                    number: '3',
                    text:
                        'Find the PC\'s hotspot IP — run ipconfig (Windows) '
                        'and look for the IPv4 address under Wi‑Fi.',
                  ),
                  _Step(
                    number: '4',
                    text: 'Start the backend: uvicorn app:app --host 0.0.0.0 --port 8000',
                  ),
                  _Step(
                    number: '5',
                    text: 'Enter http://<PC_IP>:8000 above and tap Save.',
                  ),
                  _Step(
                    number: '6',
                    text:
                        'Verify: open http://<PC_IP>:8000/health/ready in phone browser — '
                        'should return {"status":"ready"} once the model is loaded.',
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
