/// Full-screen Radio UI with channel selector, message list, and multi-mode input.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_controller.dart';
import 'radio_controller.dart';
import 'radio_service.dart';
import 'widgets/record_button.dart';
import 'widgets/voice_message_tile.dart';
import 'widgets/text_message_tile.dart';
import 'widgets/image_message_tile.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showTextInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthController>();
      final userId = auth.currentUser?.id ?? '';
      final userName = auth.currentUser?.fullName ?? 'Unknown';
      context.read<RadioController>().init(userId, userName);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RadioController>(
      builder: (context, radio, _) {
        // Scroll to bottom when messages change.
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Scaffold(
          backgroundColor: const Color(0xFF0A0D12),
          appBar: _buildAppBar(radio),
          body: radio.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00E5FF),
                  ),
                )
              : Column(
                  children: [
                    _buildChannelSelector(radio),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(child: _buildMessageList(radio)),
                    _buildBottomBar(radio),
                  ],
                ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(RadioController radio) {
    return AppBar(
      backgroundColor: const Color(0xFF0F1318),
      title: Row(
        children: [
          const Icon(Icons.cell_tower, color: Color(0xFF00E5FF), size: 22),
          const SizedBox(width: 8),
          const Text(
            'Radio',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          if (radio.activeChannel != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _channelColor(radio.activeChannel!.type).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _channelColor(radio.activeChannel!.type).withOpacity(0.3),
                ),
              ),
              child: Text(
                '#${radio.activeChannel!.name}',
                style: TextStyle(
                  color: _channelColor(radio.activeChannel!.type),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Autoplay toggle
        IconButton(
          icon: Icon(
            radio.autoplay ? Icons.volume_up : Icons.volume_off,
            color: radio.autoplay ? const Color(0xFF00E5FF) : Colors.white38,
          ),
          tooltip: radio.autoplay ? 'Autoplay ON' : 'Autoplay OFF',
          onPressed: radio.toggleAutoplay,
        ),
        // New DM button
        IconButton(
          icon: const Icon(Icons.person_add, color: Colors.white70),
          tooltip: 'Direct message',
          onPressed: () => _showNewDmDialog(radio),
        ),
      ],
    );
  }

  Widget _buildChannelSelector(RadioController radio) {
    return Container(
      height: 48,
      color: const Color(0xFF0F1318),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: radio.channels.length,
        itemBuilder: (context, i) {
          final ch = radio.channels[i];
          final isActive = ch.id == radio.activeChannelId;
          final canClose = ch.type != 'fleet';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: GestureDetector(
              onLongPress: canClose ? () => _showCloseChannelDialog(radio, ch) : null,
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _channelIcon(ch.type),
                      size: 14,
                      color: isActive ? Colors.white : Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Text(ch.name),
                    if (canClose && isActive) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 12, color: Colors.white.withOpacity(0.4)),
                    ],
                  ],
                ),
                selected: isActive,
                onSelected: (_) => radio.switchChannel(ch.id),
                selectedColor: _channelColor(ch.type).withOpacity(0.3),
                backgroundColor: const Color(0xFF1A202C),
                labelStyle: TextStyle(
                  color: isActive ? Colors.white : Colors.white60,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isActive
                        ? _channelColor(ch.type).withOpacity(0.5)
                        : Colors.white12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageList(RadioController radio) {
    final auth = context.read<AuthController>();
    final userId = auth.currentUser?.id ?? '';

    if (radio.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cell_tower, size: 64, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a voice note, text, or image',
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: radio.messages.length,
      itemBuilder: (context, i) {
        final msg = radio.messages[i];
        final isOwn = msg.senderId == userId;

        switch (msg.type) {
          case RadioMessageType.text:
            return TextMessageTile(
              message: msg,
              isOwnMessage: isOwn,
            );
          case RadioMessageType.image:
            return ImageMessageTile(
              message: msg,
              isOwnMessage: isOwn,
            );
          case RadioMessageType.voice:
          default:
            return VoiceMessageTile(
              message: msg,
              isPlaying: radio.playingMessageId == msg.id && radio.isPlaying,
              isOwnMessage: isOwn,
              onPlay: () => radio.playMessage(msg),
            );
        }
      },
    );
  }

  Widget _buildBottomBar(RadioController radio) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 24, left: 12, right: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1318),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sending indicator
            if (radio.isSending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sending...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            // Input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Image attachment button
                _buildActionButton(
                  icon: Icons.image,
                  tooltip: 'Send image',
                  onPressed: radio.isSending
                      ? null
                      : () => _showImageOptions(radio),
                ),
                const SizedBox(width: 6),
                // Toggle text input
                _buildActionButton(
                  icon: _showTextInput ? Icons.mic : Icons.text_fields,
                  tooltip: _showTextInput ? 'Voice mode' : 'Text mode',
                  color: const Color(0xFF00E5FF),
                  onPressed: () {
                    setState(() {
                      _showTextInput = !_showTextInput;
                      if (_showTextInput) {
                        _focusNode.requestFocus();
                      } else {
                        _focusNode.unfocus();
                      }
                    });
                  },
                ),
                const SizedBox(width: 6),
                // Text input OR mic button
                Expanded(
                  child: _showTextInput
                      ? _buildTextInput(radio)
                      : RecordButton(
                          isRecording: radio.isRecording,
                          onRecordStart: radio.startRecording,
                          onRecordStop: radio.stopRecordingAndSend,
                          onRecordCancel: radio.cancelRecording,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInput(RadioController radio) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A202C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(radio),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          decoration: BoxDecoration(
            color: _textController.text.trim().isEmpty
                ? const Color(0xFF1A202C)
                : const Color(0xFF00E5FF),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: radio.isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.send,
                    color: _textController.text.trim().isEmpty
                        ? Colors.white30
                        : const Color(0xFF0A0D12),
                    size: 20,
                  ),
            onPressed: radio.isSending || _textController.text.trim().isEmpty
                ? null
                : () => _sendText(radio),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    Color color = Colors.white54,
    VoidCallback? onPressed,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1A202C),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12),
      ),
      child: IconButton(
        icon: Icon(icon, color: onPressed != null ? color : Colors.white24, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _sendText(RadioController radio) async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    await radio.sendTextMessage(text);
  }

  void _showImageOptions(RadioController radio) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A202C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library, color: Color(0xFF00E5FF)),
                ),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Pick an existing photo',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  radio.pickAndSendImage();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF69F0AE).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: Color(0xFF69F0AE)),
                ),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Use camera to take a new photo',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  radio.takeAndSendPhoto();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──

  Color _channelColor(String type) {
    switch (type) {
      case 'fleet':
        return const Color(0xFF00E5FF);
      case 'direct':
        return const Color(0xFF69F0AE);
      default:
        return const Color(0xFF00E5FF);
    }
  }

  IconData _channelIcon(String type) {
    switch (type) {
      case 'fleet':
        return Icons.groups;
      case 'direct':
        return Icons.person;
      default:
        return Icons.radio;
    }
  }

  void _showCloseChannelDialog(RadioController radio, RadioChannel ch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('Close conversation?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${ch.name}" and all its messages?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              radio.closeChannel(ch.id);
            },
            child: const Text('Close', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
  }

  void _showNewDmDialog(RadioController radio) async {
    showDialog(
      context: context,
      builder: (ctx) => _NewDmDialog(radio: radio),
    );
  }
}

/// Dialog to pick a staff member and create a direct channel.
class _NewDmDialog extends StatefulWidget {
  final RadioController radio;
  const _NewDmDialog({required this.radio});

  @override
  State<_NewDmDialog> createState() => _NewDmDialogState();
}

class _NewDmDialogState extends State<_NewDmDialog> {
  List<Map<String, String>>? _staffUsers;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final users = await RadioService.getStaffUsers();
    final auth = context.read<AuthController>();
    final myId = auth.currentUser?.id ?? '';
    setState(() {
      _staffUsers = users.where((u) => u['id'] != myId).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A202C),
      title: const Text(
        'Direct Message',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 300,
        height: 300,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
              )
            : _staffUsers == null || _staffUsers!.isEmpty
                ? const Center(
                    child: Text(
                      'No other staff members found',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: _staffUsers!.length,
                    itemBuilder: (ctx, i) {
                      final user = _staffUsers![i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF2D3748),
                          child: Text(
                            (user['name'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(color: Color(0xFF00E5FF)),
                          ),
                        ),
                        title: Text(
                          user['name'] ?? 'Unknown',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          user['role'] ?? '',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          final channelId =
                              await widget.radio.createDirectChannel(
                            user['id']!,
                            user['name']!,
                          );
                          widget.radio.switchChannel(channelId);
                        },
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }
}
