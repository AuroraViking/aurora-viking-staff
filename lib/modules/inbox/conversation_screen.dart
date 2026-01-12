// Conversation Screen - Displays messages in a conversation
// Allows sending replies and viewing message history

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../core/models/messaging/messaging_models.dart';
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
          if (messages.isNotEmpty) {
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

              // Message content - render HTML if available
              if (message.contentHtml != null && message.contentHtml!.isNotEmpty)
                Html(
                  data: message.contentHtml!,
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
                    // TODO: Handle link taps (open in browser)
                    debugPrint('Link tapped: $url');
                  },
                )
              else
                Text(
                  message.content,
                  style: const TextStyle(color: AVColors.textHigh),
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

  Future<void> _sendMessage(InboxController controller) async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();
    
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

