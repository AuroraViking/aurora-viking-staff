// Conversation Screen - Displays messages in a conversation
// Allows sending replies and viewing message history

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../core/models/messaging/messaging_models.dart';
import '../../core/models/messaging/message.dart';
import '../../theme/colors.dart';
import 'inbox_controller.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  String? _dismissedDraftMessageId;  // Track which draft was dismissed
  String? _usedDraftMessageId;  // Track which draft was used (for learning)
  String? _usedDraftContent;  // Original draft content (to compare with sent)

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollController.hasClients) {
      final position = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InboxController>(
      builder: (context, controller, child) {
        final conversation = controller.selectedConversation;
        final customer = controller.selectedCustomer;
        final messages = controller.messages;

        if (conversation == null) {
          return const Scaffold(
            body: Center(
              child: Text('No conversation selected'),
            ),
          );
        }

        // Scroll to bottom when messages change
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && messages.isNotEmpty) {
            _scrollToBottom(animate: false);
          }
        });

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer?.displayName ?? 'Loading...',
                  style: const TextStyle(fontSize: 16),
                ),
                if (conversation.subject != null)
                  Text(
                    conversation.subject!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AVColors.textLow,
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Mark as resolved',
                onPressed: () => _resolveConversation(context, controller),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(context, controller, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Archive'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // Website visitor info panel (for website channel)
              if (conversation.channel == 'website')
                _buildWebsiteVisitorPanel(conversation, customer),

              // Booking context panel (if bookings detected)
              if (conversation.bookingIds.isNotEmpty && 
                  conversation.channel != 'website')
                _buildBookingContextPanel(conversation),

              // Messages list
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(color: AVColors.textLow),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final showDate = index == 0 ||
                              !_isSameDay(
                                messages[index - 1].timestamp,
                                message.timestamp,
                              );
                          return Column(
                            children: [
                              if (showDate)
                                _buildDateDivider(message.timestamp),
                              _buildMessageBubble(message),
                            ],
                          );
                        },
                      ),
              ),

              // AI Draft suggestion panel
              _buildAiDraftPanel(controller),

              // Message input
              _buildMessageInput(controller),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookingContextPanel(Conversation conversation) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AVColors.slateElev,
        border: Border(
          bottom: BorderSide(color: AVColors.outline, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AVColors.primaryTeal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: AVColors.primaryTeal,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Related Bookings',
                  style: TextStyle(
                    color: AVColors.textLow,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: conversation.bookingIds.map((ref) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AVColors.primaryTeal.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ref,
                        style: const TextStyle(
                          color: AVColors.primaryTeal,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Navigate to booking details
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Booking details coming in Phase 3'),
                ),
              );
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebsiteVisitorPanel(Conversation conversation, dynamic customer) {
    // Debug print
    print('🔍 Visitor Panel Debug:');
    print('   customerName: ${conversation.customerName}');
    print('   customerEmail: ${conversation.customerEmail}');
    print('   bookingIds: ${conversation.bookingIds}');
    
    final hasName = conversation.customerName != null && 
        conversation.customerName != 'Website Visitor' &&
        conversation.customerName!.isNotEmpty;
    final hasEmail = conversation.customerEmail != null && 
        conversation.customerEmail!.isNotEmpty;
    final hasBookings = conversation.bookingIds.isNotEmpty;
    
    print('   hasName: $hasName, hasEmail: $hasEmail, hasBookings: $hasBookings');

    // Don't show panel if no visitor info
    if (!hasName && !hasEmail && !hasBookings) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AVColors.slateElev,
        border: Border(
          bottom: BorderSide(color: AVColors.outline, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AVColors.auroraGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: AVColors.auroraGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Website Visitor Details',
                  style: TextStyle(
                    color: AVColors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Visitor info grid
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (hasName)
                _buildVisitorInfoItem(
                  Icons.badge_outlined,
                  'Name',
                  conversation.customerName!,
                ),
              if (hasEmail)
                _buildVisitorInfoItem(
                  Icons.email_outlined,
                  'Email',
                  conversation.customerEmail!,
                ),
              if (hasBookings)
                _buildVisitorInfoItem(
                  Icons.confirmation_number_outlined,
                  'Booking',
                  conversation.bookingIds.join(', '),
                  color: AVColors.primaryTeal,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorInfoItem(IconData icon, String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? AVColors.textLow),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AVColors.textLow,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color ?? AVColors.textHigh,
                fontSize: 13,
                fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    final isToday = _isSameDay(date, now);
    final isYesterday = _isSameDay(date, now.subtract(const Duration(days: 1)));

    String label;
    if (isToday) {
      label = 'Today';
    } else if (isYesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('EEEE, MMM d').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AVColors.outline)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: const TextStyle(
                color: AVColors.textLow,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Divider(color: AVColors.outline)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isOutbound = message.direction == MessageDirection.outbound;
    final timeFormat = DateFormat('h:mm a');

    return Align(
      alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isOutbound
              ? AVColors.primaryTeal.withOpacity(0.15)
              : AVColors.slateElev,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOutbound ? 16 : 4),
            bottomRight: Radius.circular(isOutbound ? 4 : 16),
          ),
          border: isOutbound
              ? Border.all(color: AVColors.primaryTeal.withOpacity(0.3))
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subject line (for emails)
              if (message.subject != null && message.subject!.isNotEmpty) ...[
                Text(
                  message.subject!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AVColors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Message content - prefer plain text, fallback to HTML
              Builder(
                builder: (context) {
                  // Debug: log content lengths
                  debugPrint('Message ${message.id}: content="${message.content.length}" chars, html="${message.contentHtml?.length ?? 0}" chars');
                  
                  // If plain text content is available and not empty, use it
                  if (message.content.isNotEmpty) {
                    return Text(
                      message.content,
                      style: const TextStyle(color: AVColors.textHigh),
                    );
                  }
                  
                  // Try HTML if no plain text
                  if (message.contentHtml != null && message.contentHtml!.isNotEmpty) {
                    // Strip <style> tags to avoid CSS parsing errors
                    String sanitizedHtml = message.contentHtml!
                        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
                        .replaceAll(RegExp(r'<link[^>]*stylesheet[^>]*>', caseSensitive: false), '');
                    
                    try {
                      return Html(
                        data: sanitizedHtml,
                        style: {
                          '*': Style(
                            color: AVColors.textHigh,
                            fontSize: FontSize(14),
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                          ),
                          'a': Style(
                            color: AVColors.primaryTeal,
                            textDecoration: TextDecoration.underline,
                          ),
                          'img': Style(
                            display: Display.block,
                            margin: Margins.only(top: 8, bottom: 8),
                          ),
                        },
                        onLinkTap: (url, _, __) {
                          debugPrint('Link tapped: $url');
                        },
                      );
                    } catch (e) {
                      debugPrint('HTML parsing error: $e');
                    }
                  }
                  
                  // Final fallback
                  return const Text(
                    '(No content available)',
                    style: TextStyle(color: AVColors.textLow, fontStyle: FontStyle.italic),
                  );
                },
              ),

              const SizedBox(height: 8),

              // Footer: timestamp and booking refs
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Channel icon
                  Icon(
                    _getChannelIcon(message.channel),
                    size: 12,
                    color: AVColors.textLow,
                  ),
                  const SizedBox(width: 4),
                  
                  // Timestamp
                  Text(
                    timeFormat.format(message.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AVColors.textLow,
                    ),
                  ),

                  // Sent indicator for outbound
                  if (isOutbound) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.status == MessageStatus.responded
                          ? Icons.done_all
                          : Icons.done,
                      size: 14,
                      color: AVColors.auroraGreen,
                    ),
                  ],
                ],
              ),

              // Booking references
              if (message.detectedBookingNumbers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: message.detectedBookingNumbers.map((ref) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AVColors.primaryTeal.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ref,
                        style: const TextStyle(
                          color: AVColors.primaryTeal,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput(InboxController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AVColors.slate,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AVColors.slateElev,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AVColors.outline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: AVColors.textLow),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(color: AVColors.textHigh),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: _messageController.text.trim().isEmpty
                    ? AVColors.slateElev
                    : AVColors.primaryTeal,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: controller.isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AVColors.textHigh,
                        ),
                      )
                    : Icon(
                        Icons.send,
                        color: _messageController.text.trim().isEmpty
                            ? AVColors.textLow
                            : AVColors.obsidian,
                      ),
                onPressed: controller.isSending ||
                        _messageController.text.trim().isEmpty
                    ? null
                    : () => _sendMessage(controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiDraftPanel(InboxController controller) {
    // Find the latest inbound message with an AI draft
    final messages = controller.messages;
    Message? messageWithDraft;
    
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.direction == MessageDirection.inbound && 
          msg.aiDraft != null && 
          msg.aiDraft!.content.isNotEmpty &&
          msg.id != _dismissedDraftMessageId) {
        messageWithDraft = msg;
        break;
      }
    }
    
    if (messageWithDraft == null || messageWithDraft.aiDraft == null) {
      return const SizedBox.shrink();
    }
    
    // Capture to non-nullable locals for closures
    final message = messageWithDraft;
    final draft = message.aiDraft!;
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AVColors.primaryTeal.withOpacity(0.1),
            AVColors.auroraGreen.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AVColors.primaryTeal.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AVColors.auroraGreen, size: 18),
              const SizedBox(width: 8),
              const Text(
                'AI Suggestion',
                style: TextStyle(
                  color: AVColors.textHigh,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getConfidenceColor(draft.confidence),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(draft.confidence * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Draft content
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Text(
                draft.content,
                style: const TextStyle(
                  color: AVColors.textHigh,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _messageController.text = draft.content;
                      _usedDraftMessageId = message.id;
                      _usedDraftContent = draft.content;
                    });
                    // Log draft usage
                    _logDraftAction(controller, message.id, 'used', draft);
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Use Draft'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AVColors.auroraGreen,
                    foregroundColor: AVColors.obsidian,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  // Log draft dismissal
                  _logDraftAction(controller, message.id, 'dismissed', draft);
                  setState(() {
                    _dismissedDraftMessageId = message.id;
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AVColors.textLow,
                  side: BorderSide(color: AVColors.textLow.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                ),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.85) return AVColors.auroraGreen;
    if (confidence >= 0.7) return Colors.orange;
    return AVColors.forgeRed;
  }

  // Log AI draft actions for learning
  Future<void> _logDraftAction(
    InboxController controller,
    String messageId,
    String action,
    AiDraft draft,
  ) async {
    try {
      await controller.logAiDraftAction(
        messageId: messageId,
        action: action,
        draftContent: draft.content,
        confidence: draft.confidence,
      );
    } catch (e) {
      debugPrint('Failed to log draft action: $e');
    }
  }

  Future<void> _sendMessage(InboxController controller) async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // Check if this was from a draft and if it was edited
    String? draftAction;
    if (_usedDraftMessageId != null && _usedDraftContent != null) {
      if (content == _usedDraftContent) {
        draftAction = 'sent_unchanged';
      } else {
        draftAction = 'sent_edited';
        // Log the edited version for learning
        await controller.logAiDraftEdit(
          messageId: _usedDraftMessageId!,
          originalDraft: _usedDraftContent!,
          editedContent: content,
        );
      }
    }

    _messageController.clear();
    // Reset draft tracking
    _usedDraftMessageId = null;
    _usedDraftContent = null;
    
    final success = await controller.sendMessage(content);
    
    if (success) {
      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.error ?? 'Failed to send message'),
          backgroundColor: AVColors.forgeRed,
        ),
      );
      controller.clearError();
    }
  }

  Future<void> _resolveConversation(
    BuildContext context,
    InboxController controller,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AVColors.slate,
        title: const Text('Mark as Resolved?'),
        content: const Text(
          'This will remove the conversation from your active inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AVColors.auroraGreen,
              foregroundColor: AVColors.obsidian,
            ),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final conversationId = controller.selectedConversation?.id;
      if (conversationId != null) {
        await controller.markAsResolved(conversationId);
        if (mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    InboxController controller,
    String action,
  ) async {
    final conversationId = controller.selectedConversation?.id;
    if (conversationId == null) return;

    switch (action) {
      case 'archive':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AVColors.slate,
            title: const Text('Archive Conversation?'),
            content: const Text(
              'This will archive the conversation. You can still find it in the archived section.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Archive'),
              ),
            ],
          ),
        );

        if (confirm == true && mounted) {
          await controller.archiveConversation(conversationId);
          if (mounted) {
            Navigator.pop(context);
          }
        }
        break;
    }
  }

  IconData _getChannelIcon(MessageChannel channel) {
    switch (channel) {
      case MessageChannel.gmail:
        return Icons.email;
      case MessageChannel.wix:
        return Icons.chat_bubble;
      case MessageChannel.whatsapp:
        return Icons.phone;
      case MessageChannel.website:
        return Icons.language;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

