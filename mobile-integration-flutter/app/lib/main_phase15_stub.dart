import 'package:flutter/material.dart';

void main() {
  runApp(const Phase15App());
}

class Phase15App extends StatelessWidget {
  const Phase15App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Squat Trainer',
      home: Scaffold(
        appBar: AppBar(title: const Text('AI Squat Trainer (Phase 1.5)')),
        body: const Center(
          child: Text(
            'Scaffold ready.\nRun flutter create first, then wire this into lib/main.dart.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
