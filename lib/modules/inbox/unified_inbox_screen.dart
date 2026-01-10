// Unified Inbox Screen - Phase 1 MVP
// Displays all customer messages from Gmail, Wix, and WhatsApp in one place

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/messaging/messaging_models.dart';
import '../../theme/colors.dart';
import 'inbox_controller.dart';
import 'conversation_screen.dart';

class UnifiedInboxScreen extends StatefulWidget {
  const UnifiedInboxScreen({super.key});

  @override
  State<UnifiedInboxScreen> createState() => _UnifiedInboxScreenState();
}

class _UnifiedInboxScreenState extends State<UnifiedInboxScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize the controller when the screen is first created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InboxController>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InboxController>(
      builder: (context, controller, child) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.inbox_rounded, size: 24),
                const SizedBox(width: 8),
                const Text('Inbox'),
                const SizedBox(width: 8),
                if (controller.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AVColors.auroraGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${controller.unreadCount}',
                      style: const TextStyle(
                        color: AVColors.obsidian,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              // Test message button (for development)
              IconButton(
                icon: const Icon(Icons.science_outlined),
                tooltip: 'Create test message',
                onPressed: () => _showTestMessageDialog(context, controller),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => controller.refresh(),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _buildChannelTabs(controller),
            ),
          ),
          body: _buildBody(controller),
        );
      },
    );
  }

  Widget _buildChannelTabs(InboxController controller) {
    return Container(
      color: AVColors.slate,
      child: Row(
        children: [
          _buildChannelTab(
            label: 'All',
            count: controller.allCount,
            channel: null,
            isSelected: controller.selectedChannelFilter == null,
            onTap: () => controller.setChannelFilter(null),
          ),
          _buildChannelTab(
            label: 'Gmail',
            count: controller.gmailCount,
            channel: 'gmail',
            isSelected: controller.selectedChannelFilter == 'gmail',
            onTap: () => controller.setChannelFilter('gmail'),
            icon: Icons.email_outlined,
            iconColor: Colors.red[400]!,
          ),
          _buildChannelTab(
            label: 'Wix',
            count: controller.wixCount,
            channel: 'wix',
            isSelected: controller.selectedChannelFilter == 'wix',
            onTap: () => controller.setChannelFilter('wix'),
            icon: Icons.chat_bubble_outline,
            iconColor: Colors.blue[400]!,
          ),
          _buildChannelTab(
            label: 'WhatsApp',
            count: controller.whatsappCount,
            channel: 'whatsapp',
            isSelected: controller.selectedChannelFilter == 'whatsapp',
            onTap: () => controller.setChannelFilter('whatsapp'),
            icon: Icons.phone_outlined,
            iconColor: Colors.green[400]!,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTab({
    required String label,
    required int count,
    required String? channel,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AVColors.primaryTeal : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? iconColor : AVColors.textLow,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AVColors.textHigh : AVColors.textLow,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? AVColors.primaryTeal.withOpacity(0.2) : AVColors.slateElev,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? AVColors.primaryTeal : AVColors.textLow,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(InboxController controller) {
    if (controller.isLoading && controller.conversations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AVColors.primaryTeal),
            SizedBox(height: 16),
            Text(
              'Loading conversations...',
              style: TextStyle(color: AVColors.textLow),
            ),
          ],
        ),
      );
    }

    if (controller.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AVColors.forgeRed),
            const SizedBox(height: 16),
            Text(
              'Error loading inbox',
              style: TextStyle(color: AVColors.textHigh, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              controller.error ?? 'Unknown error',
              style: TextStyle(color: AVColors.textLow, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => controller.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (controller.conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AVColors.slateElev,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_rounded,
                size: 48,
                color: AVColors.primaryTeal.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No messages yet',
              style: TextStyle(
                color: AVColors.textHigh,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Customer messages will appear here',
              style: TextStyle(color: AVColors.textLow, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showTestMessageDialog(context, controller),
              icon: const Icon(Icons.add),
              label: const Text('Create Test Message'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => controller.refresh(),
      color: AVColors.primaryTeal,
      backgroundColor: AVColors.slateElev,
      child: ListView.builder(
        itemCount: controller.conversations.length,
        itemBuilder: (context, index) {
          final conversation = controller.conversations[index];
          return _ConversationTile(
            conversation: conversation,
            onTap: () => _openConversation(context, controller, conversation),
          );
        },
      ),
    );
  }

  void _openConversation(
    BuildContext context,
    InboxController controller,
    Conversation conversation,
  ) async {
    await controller.selectConversation(conversation);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ConversationScreen(),
        ),
      ).then((_) {
        // Clear selection when returning from conversation
        controller.clearSelectedConversation();
      });
    }
  }

  void _showTestMessageDialog(BuildContext context, InboxController controller) {
    final emailController = TextEditingController(text: 'test@example.com');
    final contentController = TextEditingController(
      text: 'Hi, I have a question about my aurora tour booking AV-12345. Can you help me reschedule to next week?',
    );
    final subjectController = TextEditingController(text: 'Reschedule request');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AVColors.slate,
        title: const Text('Create Test Message'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'From Email',
                  hintText: 'customer@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Message Content',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              controller.createTestMessage(
                email: emailController.text,
                content: contentController.text,
                subject: subjectController.text,
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<InboxController>(
      builder: (context, controller, child) {
        // Get customer for this conversation
        // Note: In a real implementation, we'd cache customers
        return FutureBuilder<Customer?>(
          future: _getCustomer(context, conversation.customerId),
          builder: (context, snapshot) {
            final customer = snapshot.data;
            final customerName = customer?.displayName ?? 'Loading...';
            final initials = customer?.initials ?? '?';

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: conversation.hasUnread 
                    ? AVColors.slateElev 
                    : AVColors.slate,
                borderRadius: BorderRadius.circular(12),
                border: conversation.hasUnread
                    ? Border.all(color: AVColors.auroraGreen.withOpacity(0.3), width: 1)
                    : null,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getChannelColor(conversation.channel).withOpacity(0.2),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: _getChannelColor(conversation.channel),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (conversation.hasUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AVColors.auroraGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: AVColors.slate, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        customerName,
                        style: TextStyle(
                          fontWeight: conversation.hasUnread 
                              ? FontWeight.bold 
                              : FontWeight.normal,
                          color: AVColors.textHigh,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (conversation.bookingIds.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AVColors.primaryTeal.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${conversation.bookingIds.length} booking${conversation.bookingIds.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: AVColors.primaryTeal,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (conversation.subject != null && conversation.subject!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          conversation.subject!,
                          style: const TextStyle(
                            color: AVColors.textHigh,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        conversation.lastMessagePreview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: conversation.hasUnread 
                              ? AVColors.textHigh 
                              : AVColors.textLow,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimeAgo(conversation.lastMessageAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: conversation.hasUnread 
                            ? AVColors.auroraGreen 
                            : AVColors.textLow,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildChannelIcon(conversation.channel),
                  ],
                ),
                onTap: onTap,
              ),
            );
          },
        );
      },
    );
  }

  Future<Customer?> _getCustomer(BuildContext context, String customerId) async {
    final controller = context.read<InboxController>();
    return controller.messagingService.getCustomer(customerId);
  }

  Color _getChannelColor(String channel) {
    switch (channel) {
      case 'gmail':
        return Colors.red[400]!;
      case 'wix':
        return Colors.blue[400]!;
      case 'whatsapp':
        return Colors.green[400]!;
      default:
        return AVColors.textLow;
    }
  }

  Widget _buildChannelIcon(String channel) {
    IconData icon;
    Color color;

    switch (channel) {
      case 'gmail':
        icon = Icons.email;
        color = Colors.red[400]!;
        break;
      case 'wix':
        icon = Icons.chat_bubble;
        color = Colors.blue[400]!;
        break;
      case 'whatsapp':
        icon = Icons.phone;
        color = Colors.green[400]!;
        break;
      default:
        icon = Icons.message;
        color = AVColors.textLow;
    }

    return Icon(icon, size: 16, color: color);
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}

