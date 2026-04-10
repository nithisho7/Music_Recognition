import 'package:flutter/material.dart';

class RecordingWaveform extends StatelessWidget {
  const RecordingWaveform({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(9, (index) {
            final phase = (animation.value + index * 0.12) % 1.0;
            final height = 18 + (42 * (0.5 + 0.5 * _triangleWave(phase)));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 8,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFFFF8C42),
                      Color.lerp(const Color(0xFFFF8C42), const Color(0xFF25D366), index / 8)!,
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  double _triangleWave(double value) {
    return value < 0.5 ? value * 2 : (1 - value) * 2;
  }
}
