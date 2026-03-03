/// Animated press-and-hold record button with pulse animation.
import 'package:flutter/material.dart';

class RecordButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final VoidCallback onRecordCancel;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.onRecordCancel,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  DateTime? _pressStart;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isRecording)
          _buildRecordingIndicator(),
        const SizedBox(height: 8),
        GestureDetector(
          onLongPressStart: (_) {
            _cancelled = false;
            _pressStart = DateTime.now();
            widget.onRecordStart();
          },
          onLongPressEnd: (_) {
            if (!_cancelled) {
              widget.onRecordStop();
            }
          },
          onLongPressMoveUpdate: (details) {
            // Cancel if finger moves too far (drag up to cancel).
            if (details.localOffsetFromOrigin.dy < -80) {
              if (!_cancelled) {
                _cancelled = true;
                widget.onRecordCancel();
              }
            }
          },
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final scale = widget.isRecording ? _pulseAnimation.value : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.isRecording
                        ? const LinearGradient(
                            colors: [Color(0xFFFF4444), Color(0xFFFF6B6B)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF00B8D4)],
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isRecording
                                ? const Color(0xFFFF4444)
                                : const Color(0xFF00E5FF))
                            .withOpacity(0.4),
                        blurRadius: widget.isRecording ? 24 : 12,
                        spreadRadius: widget.isRecording ? 4 : 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isRecording ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.isRecording ? 'Release to send · Drag up to cancel' : 'Hold to talk',
          style: TextStyle(
            color: widget.isRecording
                ? const Color(0xFFFF6B6B)
                : Colors.white.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingIndicator() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 200)),
      builder: (context, _) {
        final elapsed = _pressStart != null
            ? DateTime.now().difference(_pressStart!).inSeconds
            : 0;
        final mins = (elapsed ~/ 60).toString().padLeft(2, '0');
        final secs = (elapsed % 60).toString().padLeft(2, '0');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF4444),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$mins:$secs',
              style: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Wrapper to use AnimatedBuilder in a simpler way.
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder_(
      animation: animation,
      builder: builder,
      child: child,
    );
  }
}

class AnimatedBuilder_ extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder_({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
