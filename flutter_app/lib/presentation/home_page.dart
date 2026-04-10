import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../controller/music_recognition_controller.dart';
import '../models/performance_metrics.dart';
import '../models/song_suggestion.dart';
import 'widgets/recording_waveform.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final MusicRecognitionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111318), Color(0xFF1E1B2E), Color(0xFF0E1014)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(appState: widget.controller.appState),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _buildStateBody(widget.controller.appState),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateBody(AppState state) {
    switch (state) {
      case AppState.idle:
        return _IdleView(controller: widget.controller);
      case AppState.listening:
        return _ListeningView(controller: widget.controller, animation: _waveController);
      case AppState.processing:
        return const _ProcessingView();
      case AppState.success:
        return _SuccessView(controller: widget.controller);
      case AppState.lowConfidence:
        return _LowConfidenceView(controller: widget.controller);
      case AppState.error:
        return _ErrorView(controller: widget.controller);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final label = switch (appState) {
      AppState.idle => 'Ready to listen',
      AppState.listening => 'Recording live audio',
      AppState.processing => 'Analyzing clip',
      AppState.success => 'Recognition complete',
      AppState.lowConfidence => 'Choose the best match',
      AppState.error => 'Something needs attention',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Music Recognition and Automation System',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFBFC7D5), fontSize: 15),
        ),
      ],
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.controller});

  final MusicRecognitionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('idle'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0x44FF8C42), Color(0x1125D366), Color(0x00000000)],
            ),
            border: Border.all(color: const Color(0x55FFFFFF)),
          ),
          child: IconButton(
            iconSize: 72,
            color: Colors.white,
            onPressed: controller.startListening,
            icon: const Icon(Icons.mic_rounded),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Tap once and capture 10 seconds of audio.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          'The app records a single clip, sends it to the Flask pipeline, and only touches Spotify when confidence rules say it should.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A0B8), fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

class _ListeningView extends StatelessWidget {
  const _ListeningView({required this.controller, required this.animation});

  final MusicRecognitionController controller;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('listening'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${controller.secondsRemaining}',
          style: const TextStyle(
            color: Color(0xFFFF8C42),
            fontSize: 72,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Listening to the room...',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        RecordingWaveform(animation: animation),
        const SizedBox(height: 24),
        const Text(
          'The microphone stays locked during capture so we do not overlap requests or send partial clips.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A0B8), fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: ValueKey('processing'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: CircularProgressIndicator(
            strokeWidth: 5,
            valueColor: AlwaysStoppedAnimation(Color(0xFF25D366)),
          ),
        ),
        SizedBox(height: 28),
        Text(
          'Analyzing audio...',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 10),
        Text(
          'Uploading the clip, preprocessing it, and matching it against the feature bank.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A0B8), fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.controller});

  final MusicRecognitionController controller;

  @override
  Widget build(BuildContext context) {
    final suggestion = controller.primarySuggestion;
    final result = controller.recognitionResult;
    final spotify = controller.spotifyActionResult;

    return SingleChildScrollView(
      key: const ValueKey('success'),
      child: Column(
        children: [
          _HeroCard(
            title: suggestion?.song ?? 'Unknown Song',
            subtitle: suggestion?.artist ?? 'Artist unavailable',
            confidence: result?.confidence ?? suggestion?.confidence ?? 0.0,
            accent: const Color(0xFF25D366),
          ),
          const SizedBox(height: 18),
          _StatusBanner(
            color: spotify?.success == true ? const Color(0xFF25D366) : const Color(0xFFFF8C42),
            title: spotify?.success == true ? 'Spotify automation succeeded' : 'Recognition succeeded',
            message: spotify?.message ?? 'The song was recognized and is ready for playlist automation.',
          ),
          const SizedBox(height: 18),
          if (result != null) _MetricsPanel(metrics: result.metrics),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Recognize another song', onPressed: controller.retry),
        ],
      ),
    );
  }
}

class _LowConfidenceView extends StatelessWidget {
  const _LowConfidenceView({required this.controller});

  final MusicRecognitionController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.recognitionResult;
    final primary = controller.primarySuggestion;
    final suggestions = controller.topSuggestions;

    return SingleChildScrollView(
      key: const ValueKey('lowConfidence'),
      child: Column(
        children: [
          _HeroCard(
            title: primary?.song ?? 'No confident match',
            subtitle: primary?.artist ?? 'Choose the best suggestion below',
            confidence: result?.confidence ?? primary?.confidence ?? 0.0,
            accent: const Color(0xFFFF8C42),
          ),
          const SizedBox(height: 18),
          _StatusBanner(
            color: const Color(0xFFFF8C42),
            title: 'Confirmation needed',
            message: result?.message ?? 'Confidence is not high enough for automatic Spotify actions. Pick the best candidate or retry.',
          ),
          const SizedBox(height: 18),
          if (primary != null)
            _PrimaryButton(
              label: 'Use best match: ${primary.song}',
              onPressed: controller.confirmPrimarySuggestion,
            ),
          const SizedBox(height: 16),
          ...suggestions.map((suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SuggestionTile(
                  suggestion: suggestion,
                  onTap: () => controller.chooseSuggestion(suggestion),
                ),
              )),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry recording'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.controller});

  final MusicRecognitionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('error'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 88, color: Color(0xFFFF8C42)),
        const SizedBox(height: 18),
        const Text(
          'Unable to finish recognition',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          controller.errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFBFC7D5), fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(label: 'Retry', onPressed: controller.retry),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.confidence,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final double confidence;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.25), const Color(0xFF1C1F28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Color(0xFFBFC7D5), fontSize: 15)),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(confidence * 100).toStringAsFixed(1)}% confidence',
            style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.color, required this.title, required this.message});

  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.metrics});

  final PerformanceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricChip(label: 'Recording', value: _format(metrics.recordingTimeMs)),
        _MetricChip(label: 'Upload', value: _format(metrics.uploadTimeMs)),
        _MetricChip(label: 'Backend', value: _format(metrics.backendProcessingTimeMs)),
        _MetricChip(label: 'Total', value: _format(metrics.totalResponseTimeMs)),
      ],
    );
  }

  String _format(double? value) {
    if (value == null) {
      return 'n/a';
    }
    return '${value.toStringAsFixed(0)} ms';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181C23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A0B8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.onTap});

  final SongSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF181C23),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: ListTile(
          title: Text(
            suggestion.song,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(suggestion.subtitle, style: const TextStyle(color: Color(0xFFBFC7D5))),
          trailing: const Icon(Icons.playlist_add_rounded, color: Color(0xFF25D366)),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF8C42),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
