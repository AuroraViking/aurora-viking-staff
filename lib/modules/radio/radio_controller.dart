/// State management for the voice radio feature.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'radio_service.dart';

class RadioController extends ChangeNotifier {
  // ── Channel state ──
  List<RadioChannel> _channels = [];
  List<RadioChannel> get channels => _channels;

  String _activeChannelId = 'fleet';
  String get activeChannelId => _activeChannelId;

  RadioChannel? get activeChannel =>
      _channels.isEmpty ? null : _channels.firstWhere(
        (c) => c.id == _activeChannelId,
        orElse: () => _channels.first,
      );

  // ── Messages state ──
  List<RadioMessage> _messages = [];
  List<RadioMessage> get messages => _messages;
  StreamSubscription? _messagesSub;

  // ── Recording state ──
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  DateTime? _recordingStart;
  String? _recordingPath;

  // ── Playback state ──
  final AudioPlayer _player = AudioPlayer();
  String? _playingMessageId;
  String? get playingMessageId => _playingMessageId;
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // ── Autoplay ──
  bool _autoplay = true;
  bool get autoplay => _autoplay;
  int _lastAutoplayedCount = 0;

  // ── User info (set externally) ──
  String? _userId;
  String? _userName;

  // ── Loading ──
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // ── Unread badge ──
  int _totalUnread = 0;
  int get totalUnread => _totalUnread;

  RadioController() {
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _playingMessageId = null;
      notifyListeners();
    });
  }

  /// Initialize with current user info.
  Future<void> init(String userId, String userName) async {
    // Skip if already initialized for the same user.
    if (_userId == userId && _userName == userName && _channels.isNotEmpty) return;

    _userId = userId;
    _userName = userName;
    _isLoading = true;
    notifyListeners();

    try {
      await RadioService.ensureDefaultChannels();
      print('✅ Radio: default channels ensured');
    } catch (e) {
      print('⚠️ Radio: ensureDefaultChannels failed: $e');
    }

    try {
      _channels = await RadioService.getChannels(userId);
      print('✅ Radio: loaded ${_channels.length} channels for $userName');
    } catch (e) {
      print('⚠️ Radio: getChannels failed: $e');
      _channels = [];
    }

    _isLoading = false;
    notifyListeners();

    // Start listening on the default channel.
    switchChannel(_activeChannelId);
  }

  // ──────────── Channel switching ────────────

  void switchChannel(String channelId) {
    _activeChannelId = channelId;
    _messages = [];
    notifyListeners();

    _messagesSub?.cancel();
    _messagesSub = RadioService.streamMessages(channelId).listen(
      (msgs) {
        final isNew = msgs.length > _messages.length && _messages.isNotEmpty;
        _messages = msgs;
        notifyListeners();

        // Auto-play the newest message if it just arrived.
        if (isNew && _autoplay && msgs.isNotEmpty) {
          final newest = msgs.last;
          if (newest.senderId != _userId) {
            playMessage(newest);
          }
        }
      },
      onError: (error) {
        print('⚠️ Radio stream error: $error');
        print('   This may be because the Firestore index is still building.');
      },
    );
  }

  /// Refresh channels list (e.g. after creating a DM).
  Future<void> refreshChannels() async {
    if (_userId == null) return;
    _channels = await RadioService.getChannels(_userId!);
    notifyListeners();
  }

  // ──────────── Recording ────────────

  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/radio_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: _recordingPath!,
    );

    _isRecording = true;
    _recordingStart = DateTime.now();
    notifyListeners();

    // Haptic + beep feedback so the guide knows recording started.
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
  }

  Future<void> stopRecordingAndSend() async {
    if (!_isRecording) return;

    // Haptic + beep feedback so the guide knows recording stopped.
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    final path = await _recorder.stop();
    _isRecording = false;
    notifyListeners();

    if (path == null || _userId == null || _userName == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final base64Audio = base64Encode(bytes);
    final durationMs = DateTime.now().difference(_recordingStart!).inMilliseconds;

    await RadioService.sendVoiceNote(
      channelId: _activeChannelId,
      senderId: _userId!,
      senderName: _userName!,
      audioBase64: base64Audio,
      durationMs: durationMs,
    );

    // Clean up temp file.
    await file.delete().catchError((_) {});
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.stop();
    _isRecording = false;
    notifyListeners();

    if (_recordingPath != null) {
      File(_recordingPath!).delete().catchError((_) {});
    }
  }

  // ──────────── Playback ────────────

  Future<void> playMessage(RadioMessage message) async {
    try {
      // If already playing the same message, stop it.
      if (_playingMessageId == message.id && _isPlaying) {
        await _player.stop();
        _isPlaying = false;
        _playingMessageId = null;
        notifyListeners();
        return;
      }

      await _player.stop();
      _playingMessageId = message.id;
      _isPlaying = true;
      notifyListeners();

      // Decode base64 → bytes → write to temp file → play.
      final bytes = base64Decode(message.audioBase64);
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/radio_play_${message.id.hashCode}.m4a');
      await tempFile.writeAsBytes(bytes);

      await _player.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      print('❌ Radio playback error: $e');
      _isPlaying = false;
      _playingMessageId = null;
      notifyListeners();
    }
  }

  void toggleAutoplay() {
    _autoplay = !_autoplay;
    notifyListeners();
  }

  // ──────────── Direct messages ────────────

  Future<String> createDirectChannel(String toUserId, String toUserName) async {
    if (_userId == null || _userName == null) return 'fleet';

    final channelId = await RadioService.createDirectChannel(
      fromUserId: _userId!,
      fromUserName: _userName!,
      toUserId: toUserId,
      toUserName: toUserName,
    );

    await refreshChannels();
    return channelId;
  }

  /// Close/delete a channel (only for direct channels, not fleet).
  Future<void> closeChannel(String channelId) async {
    // Don't allow deleting the fleet channel.
    final channel = _channels.firstWhere(
      (c) => c.id == channelId,
      orElse: () => _channels.first,
    );
    if (channel.type == 'fleet') return;

    await RadioService.deleteChannel(channelId);
    await refreshChannels();

    // Switch back to fleet if we were on the deleted channel.
    if (_activeChannelId == channelId) {
      switchChannel('fleet');
    }
  }

  // ──────────── Cleanup ────────────

  @override
  void dispose() {
    _messagesSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
