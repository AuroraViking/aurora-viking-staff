// Inbox Controller for the Unified Inbox
// Manages state and business logic for the messaging module

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/messaging/messaging_models.dart';
import 'messaging_service.dart';

class InboxController extends ChangeNotifier {
  final MessagingService _messagingService = MessagingService();
  
  // Expose messaging service for direct access when needed
  MessagingService get messagingService => _messagingService;

  // State
  List<Conversation> _conversations = [];
  Conversation? _selectedConversation;
  List<Message> _messages = [];
  Customer? _selectedCustomer;
  String? _selectedChannelFilter;
  String? _selectedInboxFilter;  // Filter by inbox (info@, photo@, etc.)
  int _unreadCount = 0;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  bool _isInitialized = false;

  // Subscriptions
  StreamSubscription<List<Conversation>>? _conversationsSubscription;
  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Customer?>? _customerSubscription;
  StreamSubscription<int>? _unreadSubscription;

  // Getters
  List<Conversation> get conversations {
    var filtered = _conversations;
    
    // "Main" inbox (null filter) shows only non-handled conversations
    // Sub-category inboxes show ALL conversations for that inbox (including handled)
    if (_selectedInboxFilter == null) {
      // Main inbox - show only unhandled
      filtered = filtered.where((c) => !c.isHandled).toList();
    } else if (_selectedInboxFilter == 'info@auroraviking.is') {
      // Info inbox - include legacy data (null inboxEmail) and explicit info@
      filtered = filtered.where((c) => 
          c.inboxEmail == 'info@auroraviking.is' || c.inboxEmail == null).toList();
    } else {
      // Other inboxes (photo@, etc.) - exact match only
      filtered = filtered.where((c) => c.inboxEmail == _selectedInboxFilter).toList();
    }
    
    // Then filter by channel
    if (_selectedChannelFilter != null) {
      filtered = filtered.where((c) => c.channel == _selectedChannelFilter).toList();
    }
    
    return filtered;
  }
  
  Conversation? get selectedConversation => _selectedConversation;
  List<Message> get messages => _messages;
  Customer? get selectedCustomer => _selectedCustomer;
  String? get selectedChannelFilter => _selectedChannelFilter;
  String? get selectedInboxFilter => _selectedInboxFilter;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  bool get hasError => _error != null;
  bool get isInitialized => _isInitialized;

  // Channel counts (respect inbox filter)
  List<Conversation> get _filteredByInbox => _selectedInboxFilter == null
      ? _conversations
      : _conversations.where((c) => c.inboxEmail == _selectedInboxFilter).toList();
  
  int get allCount => _filteredByInbox.length;
  int get gmailCount => _filteredByInbox.where((c) => c.channel == 'gmail').length;
  int get wixCount => _filteredByInbox.where((c) => c.channel == 'wix').length;
  int get whatsappCount => _filteredByInbox.where((c) => c.channel == 'whatsapp').length;
  
  // Main inbox count (unhandled only)
  int get mainInboxCount => _conversations.where((c) => !c.isHandled).length;
  
  // Inbox counts (all conversations, including handled)
  int get infoInboxCount => _conversations.where((c) => 
      c.inboxEmail == 'info@auroraviking.is' || c.inboxEmail == null).length;
  int get photoInboxCount => _conversations.where((c) => 
      c.inboxEmail == 'photo@auroraviking.com').length;
  
  // Placeholder counts for future integrations
  int get websiteCount => _conversations.where((c) => c.channel == 'website').length;
  int get whatsappInboxCount => _conversations.where((c) => c.channel == 'whatsapp').length;
  
  // Get unique inbox emails for dynamic tabs
  List<String> get availableInboxes {
    final inboxes = _conversations
        .map((c) => c.inboxEmail)
        .where((e) => e != null)
        .cast<String>()
        .toSet()
        .toList();
    inboxes.sort();
    return inboxes;
  }

  // ============================================
  // INITIALIZATION
  // ============================================

  /// Initialize the controller and start listening to conversations
  void initialize() {
    if (_isInitialized) return; // Prevent double initialization
    _isInitialized = true;
    print('📬 InboxController: Initializing...');
    _subscribeToConversations();
    _subscribeToUnreadCount();
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _customerSubscription?.cancel();
    _unreadSubscription?.cancel();
    super.dispose();
  }

  // ============================================
  // SUBSCRIPTIONS
  // ============================================

  void _subscribeToConversations() {
    _conversationsSubscription?.cancel();
    _isLoading = true;
    _error = null;
    notifyListeners();

    _conversationsSubscription = _messagingService
        .getActiveConversationsStream()
        .listen(
      (conversations) {
        _conversations = conversations;
        _isLoading = false;
        _error = null;
        print('📬 Received ${conversations.length} active conversations');
        notifyListeners();
      },
      onError: (error) {
        print('❌ Error in conversations stream: $error');
        _error = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void _subscribeToUnreadCount() {
    _unreadSubscription?.cancel();
    _unreadSubscription = _messagingService.getUnreadCountStream().listen(
      (count) {
        _unreadCount = count;
        notifyListeners();
      },
      onError: (error) {
        print('❌ Error in unread count stream: $error');
      },
    );
  }

  void _subscribeToMessages(String conversationId) {
    _messagesSubscription?.cancel();
    _messages = [];
    _error = null;
    notifyListeners();

    print('📨 Subscribing to messages for: $conversationId');
    
    _messagesSubscription = _messagingService
        .getMessagesStream(conversationId)
        .listen(
      (messages) {
        print('📬 Received ${messages.length} messages');
        _messages = messages;
        _error = null;
        notifyListeners();
      },
      onError: (error) {
        print('❌ Error in messages stream: $error');
        _error = 'Error loading messages: $error';
        notifyListeners();
        
        // If it's an index error, show the URL
        if (error.toString().contains('index')) {
          print('💡 You may need to create a Firestore index. Check the error URL above.');
        }
      },
    );
  }

  void _subscribeToCustomer(String customerId) {
    _customerSubscription?.cancel();
    _selectedCustomer = null;

    _customerSubscription = _messagingService
        .getCustomerStream(customerId)
        .listen(
      (customer) {
        _selectedCustomer = customer;
        notifyListeners();
      },
      onError: (error) {
        print('❌ Error in customer stream: $error');
      },
    );
  }

  // ============================================
  // ACTIONS
  // ============================================

  /// Set channel filter
  void setChannelFilter(String? channel) {
    _selectedChannelFilter = channel;
    notifyListeners();
  }
  
  /// Set inbox filter (info@, photo@, etc.)
  void setInboxFilter(String? inbox) {
    _selectedInboxFilter = inbox;
    _selectedChannelFilter = null;  // Reset channel filter when changing inbox
    notifyListeners();
  }

  /// Select a conversation and load its messages
  Future<void> selectConversation(Conversation conversation) async {
    _selectedConversation = conversation;
    notifyListeners();

    // Subscribe to messages for this conversation
    _subscribeToMessages(conversation.id);

    // Subscribe to customer data
    _subscribeToCustomer(conversation.customerId);

    // Mark as read
    if (conversation.unreadCount > 0) {
      await markConversationAsRead(conversation.id);
    }
  }

  /// Clear selected conversation
  void clearSelectedConversation() {
    _messagesSubscription?.cancel();
    _customerSubscription?.cancel();
    _selectedConversation = null;
    _messages = [];
    _selectedCustomer = null;
    notifyListeners();
  }

  /// Mark conversation as read
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      await _messagingService.markConversationAsRead(conversationId);
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  /// Send a message in the current conversation
  Future<bool> sendMessage(String content) async {
    if (_selectedConversation == null) {
      _error = 'No conversation selected';
      notifyListeners();
      return false;
    }

    if (content.trim().isEmpty) {
      return false;
    }

    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      await _messagingService.sendMessage(
        conversationId: _selectedConversation!.id,
        content: content.trim(),
        channel: _selectedConversation!.channel,
      );
      _isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('Error sending message: $e');
      _error = 'Failed to send message: $e';
      _isSending = false;
      notifyListeners();
      return false;
    }
  }

  /// Mark conversation as resolved
  Future<void> markAsResolved(String conversationId) async {
    try {
      await _messagingService.updateConversationStatus(
        conversationId,
        ConversationStatus.resolved,
      );
      
      // Clear selection if this was the selected conversation
      if (_selectedConversation?.id == conversationId) {
        clearSelectedConversation();
      }
    } catch (e) {
      print('Error marking conversation as resolved: $e');
      _error = 'Failed to resolve conversation';
      notifyListeners();
    }
  }

  /// Archive conversation
  Future<void> archiveConversation(String conversationId) async {
    try {
      await _messagingService.updateConversationStatus(
        conversationId,
        ConversationStatus.archived,
      );
      
      // Clear selection if this was the selected conversation
      if (_selectedConversation?.id == conversationId) {
        clearSelectedConversation();
      }
    } catch (e) {
      print('Error archiving conversation: $e');
      _error = 'Failed to archive conversation';
      notifyListeners();
    }
  }

  /// Assign conversation to current user
  Future<void> assignToMe(String conversationId, String userId, String userName) async {
    try {
      await _messagingService.assignConversation(conversationId, userId, userName);
      print('✅ Assigned conversation $conversationId to $userName');
    } catch (e) {
      print('Error assigning conversation: $e');
      _error = 'Failed to assign conversation';
      notifyListeners();
    }
  }

  /// Unassign conversation
  Future<void> unassign(String conversationId) async {
    try {
      await _messagingService.unassignConversation(conversationId);
      print('✅ Unassigned conversation $conversationId');
    } catch (e) {
      print('Error unassigning conversation: $e');
      _error = 'Failed to unassign conversation';
      notifyListeners();
    }
  }

  /// Mark conversation as complete (handled)
  Future<void> markAsComplete(String conversationId, String userId) async {
    try {
      await _messagingService.markConversationComplete(conversationId, userId);
      print('✅ Marked conversation $conversationId as complete');
    } catch (e) {
      print('Error marking conversation as complete: $e');
      _error = 'Failed to mark as complete';
      notifyListeners();
    }
  }

  /// Reopen a handled conversation (move back to Main)
  Future<void> reopenConversation(String conversationId) async {
    try {
      await _messagingService.reopenConversation(conversationId);
      print('✅ Reopened conversation $conversationId');
    } catch (e) {
      print('Error reopening conversation: $e');
      _error = 'Failed to reopen conversation';
      notifyListeners();
    }
  }

  /// Refresh conversations
  Future<void> refresh() async {
    _subscribeToConversations();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ============================================
  // DEVELOPMENT / TESTING
  // ============================================

  /// Create a test message for development
  Future<void> createTestMessage({
    String email = 'customer@example.com',
    String content = 'Hi, I have a question about my aurora tour booking AV-12345. Can you help me reschedule?',
    String subject = 'Reschedule request',
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final result = await _messagingService.createTestMessage(
        email: email,
        content: content,
        subject: subject,
      );

      print('✅ Test message created: $result');
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('❌ Failed to create test message: $e');
      _error = 'Failed to create test message: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
}

