/// Voice message tile – shows sender, timestamp, duration, and play/pause.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../radio_service.dart';

class VoiceMessageTile extends StatelessWidget {
  final RadioMessage message;
  final bool isPlaying;
  final bool isOwnMessage;
  final VoidCallback onPlay;

  const VoiceMessageTile({
    super.key,
    required this.message,
    required this.isPlaying,
    required this.isOwnMessage,
    required this.onPlay,
  });

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).ceil();
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.createdAt);
    final duration = _formatDuration(message.durationMs);

    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          crossAxisAlignment:
              isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isOwnMessage)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPlay,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isOwnMessage
                        ? const LinearGradient(
                            colors: [Color(0xFF00838F), Color(0xFF006064)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF2D3748), Color(0xFF1A202C)],
                          ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft:
                          Radius.circular(isOwnMessage ? 20 : 4),
                      bottomRight:
                          Radius.circular(isOwnMessage ? 4 : 20),
                    ),
                    border: Border.all(
                      color: isPlaying
                          ? const Color(0xFF00E5FF)
                          : Colors.white.withOpacity(0.08),
                      width: isPlaying ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Play / pause icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPlaying
                              ? const Color(0xFF00E5FF).withOpacity(0.2)
                              : Colors.white.withOpacity(0.1),
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: isPlaying
                              ? const Color(0xFF00E5FF)
                              : Colors.white.withOpacity(0.8),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Fake waveform bars
                      _buildWaveform(isPlaying),
                      const SizedBox(width: 10),
                      // Duration
                      Text(
                        duration,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, top: 2),
              child: Text(
                time,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveform(bool active) {
    // Simple decorative waveform bars.
    final heights = [8.0, 14.0, 10.0, 18.0, 6.0, 16.0, 12.0, 8.0, 14.0, 10.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(heights.length, (i) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 200 + i * 40),
          width: 3,
          height: active ? heights[i] : heights[i] * 0.5,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF00E5FF).withOpacity(0.8 - i * 0.04)
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
