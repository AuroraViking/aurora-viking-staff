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
              preferredSize: const Size.fromHeight(60),
              child: _buildInboxTabs(controller),
            ),
          ),
          body: _buildBody(controller),
        );
      },
    );
  }

  Widget _buildInboxTabs(InboxController controller) {
    return Container(
      color: AVColors.obsidian,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _buildInboxTab(
              label: 'Main',
              count: controller.mainInboxCount,
              inbox: null,
              isSelected: controller.selectedInboxFilter == null,
              onTap: () => controller.setInboxFilter(null),
              icon: Icons.inbox,
              color: AVColors.auroraGreen,
              showBadge: true,
            ),
            const SizedBox(width: 8),
            _buildInboxTab(
              label: 'Info',
              count: controller.infoInboxCount,
              inbox: 'info@auroraviking.is',
              isSelected: controller.selectedInboxFilter == 'info@auroraviking.is',
              onTap: () => controller.setInboxFilter('info@auroraviking.is'),
              icon: Icons.email_outlined,
              color: Colors.blue,
            ),
            const SizedBox(width: 8),
            _buildInboxTab(
              label: 'Photo',
              count: controller.photoInboxCount,
              inbox: 'photo@auroraviking.com',
              isSelected: controller.selectedInboxFilter == 'photo@auroraviking.com',
              onTap: () => controller.setInboxFilter('photo@auroraviking.com'),
              icon: Icons.photo_camera_outlined,
              color: Colors.purple,
            ),
            const SizedBox(width: 8),
            _buildInboxTab(
              label: 'Website',
              count: controller.websiteCount,
              inbox: 'website',
              isSelected: controller.selectedInboxFilter == 'website',
              onTap: () => _showComingSoon(context, 'Website Chat'),
              icon: Icons.language,
              color: Colors.orange,
              isPlaceholder: true,
            ),
            const SizedBox(width: 8),
            _buildInboxTab(
              label: 'WhatsApp',
              count: controller.whatsappCount,
              inbox: 'whatsapp',
              isSelected: controller.selectedInboxFilter == 'whatsapp',
              onTap: () => _showComingSoon(context, 'WhatsApp'),
              icon: Icons.chat,
              color: Colors.green,
              isPlaceholder: true,
            ),
          ],
        ),
      ),
    );
  }
  
  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature integration coming soon!'),
        backgroundColor: AVColors.slate,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildInboxTab({
    required String label,
    required int count,
    required String? inbox,
    required bool isSelected,
    required VoidCallback onTap,
    required IconData icon,
    Color? color,
    bool showBadge = false,
    bool isPlaceholder = false,
  }) {
    final tabColor = color ?? AVColors.primaryTeal;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? tabColor.withOpacity(0.15)
              : (isPlaceholder ? AVColors.slate.withOpacity(0.5) : AVColors.slateElev),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? tabColor : (isPlaceholder ? AVColors.textLow.withOpacity(0.3) : Colors.transparent),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? tabColor : (isPlaceholder ? AVColors.textLow.withOpacity(0.5) : AVColors.textLow),
                ),
                if (isPlaceholder)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AVColors.slate,
                        shape: BoxShape.circle,
                        border: Border.all(color: AVColors.textLow, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? tabColor : (isPlaceholder ? AVColors.textLow.withOpacity(0.5) : AVColors.textLow),
              ),
            ),
            if (count > 0 && !isPlaceholder) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? tabColor.withOpacity(0.3) : AVColors.slate,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? tabColor : AVColors.textLow,
                  ),
                ),
              ),
            ],
            if (isPlaceholder) ...[
              const SizedBox(height: 2),
              Text(
                'Soon',
                style: TextStyle(
                  fontSize: 8,
                  color: AVColors.textLow.withOpacity(0.5),
                ),
              ),
            ],
          ],
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

    return Column(
      children: [
        // Swipe hint for Main inbox
        if (controller.selectedInboxFilter == null && controller.conversations.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AVColors.obsidian,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swipe, size: 14, color: AVColors.textLow),
                const SizedBox(width: 8),
                Text(
                  '← Assign  •  Complete →',
                  style: TextStyle(
                    color: AVColors.textLow,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => controller.refresh(),
            color: AVColors.primaryTeal,
            backgroundColor: AVColors.slateElev,
            child: ListView.builder(
              itemCount: controller.conversations.length,
              itemBuilder: (context, index) {
                final conversation = controller.conversations[index];
                return _SwipeableConversationTile(
                  conversation: conversation,
                  onTap: () => _openConversation(context, controller, conversation),
                  onMarkComplete: () => _markComplete(context, controller, conversation),
                  onAssignToMe: () => _assignToMe(context, controller, conversation),
                  onReopen: () => _reopenConversation(context, controller, conversation),
                  showInMain: controller.selectedInboxFilter == null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _markComplete(BuildContext context, InboxController controller, Conversation conversation) async {
    // TODO: Get actual user ID from auth
    await controller.markAsComplete(conversation.id, 'current_user_id');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Marked as complete'),
          backgroundColor: AVColors.auroraGreen,
          action: SnackBarAction(
            label: 'Undo',
            textColor: AVColors.obsidian,
            onPressed: () => controller.reopenConversation(conversation.id),
          ),
        ),
      );
    }
  }

  void _assignToMe(BuildContext context, InboxController controller, Conversation conversation) async {
    // TODO: Get actual user ID and name from auth
    await controller.assignToMe(conversation.id, 'current_user_id', 'You');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assigned to you'),
          backgroundColor: AVColors.primaryTeal,
        ),
      );
    }
  }

  void _reopenConversation(BuildContext context, InboxController controller, Conversation conversation) async {
    await controller.reopenConversation(conversation.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moved back to Main inbox'),
          backgroundColor: AVColors.primaryTeal,
        ),
      );
    }
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

class _SwipeableConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onMarkComplete;
  final VoidCallback onAssignToMe;
  final VoidCallback onReopen;
  final bool showInMain;

  const _SwipeableConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onMarkComplete,
    required this.onAssignToMe,
    required this.onReopen,
    required this.showInMain,
  });

  @override
  Widget build(BuildContext context) {
    // In Main inbox: swipe right = complete, swipe left = assign
    // In sub-inboxes: show reopen option if handled
    
    return Dismissible(
      key: Key(conversation.id),
      direction: showInMain 
          ? DismissDirection.horizontal 
          : (conversation.isHandled ? DismissDirection.startToEnd : DismissDirection.none),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Swipe left = Assign to me (don't dismiss)
          onAssignToMe();
          return false;
        } else if (direction == DismissDirection.startToEnd) {
          if (showInMain) {
            // Swipe right in Main = Mark complete
            onMarkComplete();
          } else if (conversation.isHandled) {
            // Swipe right in sub-inbox = Reopen
            onReopen();
          }
          return false;
        }
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: showInMain ? AVColors.auroraGreen : AVColors.primaryTeal,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Row(
          children: [
            Icon(
              showInMain ? Icons.check_circle : Icons.replay,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              showInMain ? 'Complete' : 'Reopen',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: showInMain ? Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AVColors.primaryTeal,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Assign to me',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.person_add,
              color: Colors.white,
            ),
          ],
        ),
      ) : null,
      child: _ConversationTile(
        conversation: conversation,
        onTap: onTap,
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
                          color: conversation.isHandled 
                              ? AVColors.textLow 
                              : AVColors.textHigh,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Assignment badge
                    if (conversation.isAssigned)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person, size: 10, color: Colors.orange),
                            const SizedBox(width: 2),
                            Text(
                              conversation.assignedToName ?? 'Assigned',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Handled badge
                    if (conversation.isHandled)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AVColors.auroraGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 10, color: AVColors.auroraGreen),
                            SizedBox(width: 2),
                            Text(
                              'Done',
                              style: TextStyle(
                                color: AVColors.auroraGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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

