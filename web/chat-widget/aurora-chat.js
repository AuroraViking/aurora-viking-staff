/**
 * Aurora Viking Chat Widget
 * Embeddable chat widget for auroraviking.is/com websites
 * Connects to Firebase Firestore for real-time messaging
 */

(function() {
  'use strict';

  // Configuration (set via window.AURORA_CHAT_CONFIG before loading this script)
  const config = window.AURORA_CHAT_CONFIG || {};
  const PROJECT_ID = config.projectId || 'aurora-viking-staff';
  const API_KEY = config.apiKey || 'AIzaSyDdCYDwnVw2IuWPaco_QUzGBMEz8ef2Zj4';
  const POSITION = config.position || 'bottom-right';
  const PRIMARY_COLOR = config.primaryColor || '#00E5FF';
  const GREETING = config.greeting || 'Hi! 👋 Ask us anything about Northern Lights tours!';
  const OFFLINE_MESSAGE = config.offlineMessage || 'Leave a message and we\'ll get back to you soon!';
  const QUICK_REPLIES = config.quickReplies || [
    'Tour availability?',
    'What to wear?',
    'Photo request',
    'Rebooking'
  ];

  // Firebase endpoints
  const FIRESTORE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
  const FUNCTIONS_URL = `https://us-central1-${PROJECT_ID}.cloudfunctions.net`;

  // State
  let sessionId = null;
  let conversationId = null;
  let customerId = null;
  let visitorName = null;
  let visitorEmail = null;
  let messages = [];
  let isOpen = false;
  let isOnline = true;
  let isTyping = false;
  let unreadCount = 0;
  let messageListener = null;
  let lastMessageId = null;

  // DOM Elements (will be created on init)
  let widget = null;
  let chatButton = null;
  let chatWindow = null;
  let messagesContainer = null;
  let inputElement = null;
  let badgeElement = null;

  // ========== Initialization ==========
  
  function init() {
    // Load session from localStorage
    loadSession();
    
    // Create widget DOM
    createWidget();
    
    // Load CSS if not already loaded
    loadStyles();
    
    // Set up message listener if we have a session
    if (sessionId && conversationId) {
      startMessageListener();
    }

    // Track page URL
    trackPageVisit();
    
    console.log('🌌 Aurora Chat Widget initialized');
  }

  function loadSession() {
    try {
      const saved = localStorage.getItem('aurora_chat_session');
      if (saved) {
        const data = JSON.parse(saved);
        sessionId = data.sessionId;
        conversationId = data.conversationId;
        customerId = data.customerId;
        visitorName = data.visitorName;
        visitorEmail = data.visitorEmail;
        messages = data.messages || [];
        lastMessageId = data.lastMessageId;
      }
    } catch (e) {
      console.error('Error loading session:', e);
    }
  }

  function saveSession() {
    try {
      localStorage.setItem('aurora_chat_session', JSON.stringify({
        sessionId,
        conversationId,
        customerId,
        visitorName,
        visitorEmail,
        messages: messages.slice(-50), // Keep last 50 messages
        lastMessageId
      }));
    } catch (e) {
      console.error('Error saving session:', e);
    }
  }

  // ========== Widget DOM Creation ==========

  function createWidget() {
    // Main container
    widget = document.createElement('div');
    widget.className = 'aurora-chat-widget';
    widget.innerHTML = `
      <!-- Floating Button -->
      <button class="aurora-chat-button" aria-label="Open chat">
        <svg viewBox="0 0 24 24">
          <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
        </svg>
        <span class="aurora-chat-badge" style="display: none;">0</span>
      </button>
      
      <!-- Chat Window -->
      <div class="aurora-chat-window">
        <!-- Header -->
        <div class="aurora-chat-header">
          <div class="aurora-chat-logo">
            <svg viewBox="0 0 24 24">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
            </svg>
          </div>
          <div class="aurora-chat-header-info">
            <div class="aurora-chat-title">Aurora Viking</div>
            <div class="aurora-chat-subtitle">
              <span class="aurora-chat-status"></span>
              <span class="aurora-chat-status-text">We typically reply within minutes</span>
            </div>
          </div>
          <button class="aurora-chat-close" aria-label="Close chat">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
          </button>
        </div>
        
        <!-- Connection status -->
        <div class="aurora-chat-connection">
          Connection lost. Reconnecting...
        </div>
        
        <!-- Messages -->
        <div class="aurora-chat-messages">
          <!-- Messages will be inserted here -->
        </div>
        
        <!-- Quick replies (shown on empty state) -->
        <div class="aurora-chat-quick-replies">
          ${QUICK_REPLIES.map(q => `<button class="aurora-chat-quick-reply">${q}</button>`).join('')}
        </div>
        
        <!-- Input area -->
        <div class="aurora-chat-input-container">
          <form class="aurora-chat-input-form">
            <div class="aurora-chat-input-wrapper">
              <textarea 
                class="aurora-chat-input" 
                placeholder="Type your message..." 
                rows="1"
                maxlength="2000"
              ></textarea>
            </div>
            <button type="submit" class="aurora-chat-send" aria-label="Send message">
              <svg viewBox="0 0 24 24">
                <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
              </svg>
            </button>
          </form>
        </div>
        
        <!-- Powered by -->
        <div class="aurora-chat-footer">
          Powered by <a href="https://auroraviking.is" target="_blank" rel="noopener">Aurora Viking</a>
        </div>
      </div>
    `;

    document.body.appendChild(widget);

    // Get references to elements
    chatButton = widget.querySelector('.aurora-chat-button');
    chatWindow = widget.querySelector('.aurora-chat-window');
    messagesContainer = widget.querySelector('.aurora-chat-messages');
    inputElement = widget.querySelector('.aurora-chat-input');
    badgeElement = widget.querySelector('.aurora-chat-badge');

    // Set up event listeners
    setupEventListeners();

    // Render initial messages
    renderMessages();
  }

  function loadStyles() {
    // Check if styles already loaded
    if (document.getElementById('aurora-chat-styles')) return;

    const link = document.createElement('link');
    link.id = 'aurora-chat-styles';
    link.rel = 'stylesheet';
    link.href = `https://${PROJECT_ID}.web.app/chat-widget/aurora-chat.css`;
    document.head.appendChild(link);
  }

  function setupEventListeners() {
    // Toggle chat window
    chatButton.addEventListener('click', toggleChat);
    widget.querySelector('.aurora-chat-close').addEventListener('click', closeChat);

    // Send message
    const form = widget.querySelector('.aurora-chat-input-form');
    form.addEventListener('submit', handleSendMessage);

    // Auto-resize textarea
    inputElement.addEventListener('input', autoResizeTextarea);

    // Enter to send (Shift+Enter for new line)
    inputElement.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSendMessage(e);
      }
    });

    // Quick replies
    widget.querySelectorAll('.aurora-chat-quick-reply').forEach(btn => {
      btn.addEventListener('click', () => {
        inputElement.value = btn.textContent;
        handleSendMessage(new Event('submit'));
      });
    });

    // Track visibility for unread count
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && isOpen) {
        clearUnreadBadge();
      }
    });
  }

  // ========== Chat UI Controls ==========

  function toggleChat() {
    if (isOpen) {
      closeChat();
    } else {
      openChat();
    }
  }

  function openChat() {
    isOpen = true;
    chatWindow.classList.add('open');
    chatButton.classList.add('open');
    clearUnreadBadge();
    inputElement.focus();
    
    // Start session if not exists
    if (!sessionId) {
      createSession();
    }

    // Show welcome message if no messages
    if (messages.length === 0) {
      showWelcomeMessage();
    }

    // Scroll to bottom
    scrollToBottom();
  }

  function closeChat() {
    isOpen = false;
    chatWindow.classList.remove('open');
    chatButton.classList.remove('open');
  }

  function clearUnreadBadge() {
    unreadCount = 0;
    badgeElement.style.display = 'none';
    badgeElement.textContent = '0';
  }

  function incrementUnreadBadge() {
    if (!isOpen || document.hidden) {
      unreadCount++;
      badgeElement.textContent = unreadCount > 99 ? '99+' : unreadCount.toString();
      badgeElement.style.display = 'flex';
    }
  }

  function autoResizeTextarea() {
    inputElement.style.height = 'auto';
    inputElement.style.height = Math.min(inputElement.scrollHeight, 100) + 'px';
  }

  function scrollToBottom() {
    setTimeout(() => {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }, 100);
  }

  // ========== Messages ==========

  function showWelcomeMessage() {
    const welcomeHtml = `
      <div class="aurora-chat-welcome">
        <div class="aurora-chat-welcome-emoji">🌌</div>
        <div class="aurora-chat-welcome-title">Welcome to Aurora Viking!</div>
        <div class="aurora-chat-welcome-text">${GREETING}</div>
      </div>
    `;
    messagesContainer.innerHTML = welcomeHtml;
  }

  function renderMessages() {
    if (messages.length === 0) {
      if (isOpen) showWelcomeMessage();
      widget.querySelector('.aurora-chat-quick-replies').style.display = 'flex';
      return;
    }

    widget.querySelector('.aurora-chat-quick-replies').style.display = 'none';
    
    messagesContainer.innerHTML = messages.map(msg => `
      <div class="aurora-chat-message ${msg.direction === 'inbound' ? 'visitor' : 'staff'}">
        <div class="aurora-chat-bubble">${escapeHtml(msg.content)}</div>
        <div class="aurora-chat-message-time">${formatTime(msg.timestamp)}</div>
      </div>
    `).join('');

    scrollToBottom();
  }

  function addMessage(message) {
    // Avoid duplicates
    if (messages.some(m => m.id === message.id)) return;
    
    messages.push(message);
    lastMessageId = message.id;
    saveSession();
    renderMessages();
    
    // Increment badge if staff message and chat is closed
    if (message.direction === 'outbound') {
      incrementUnreadBadge();
    }
  }

  function showTypingIndicator() {
    if (isTyping) return;
    isTyping = true;
    
    const typingHtml = `
      <div class="aurora-chat-typing" id="aurora-typing">
        <span></span><span></span><span></span>
      </div>
    `;
    messagesContainer.insertAdjacentHTML('beforeend', typingHtml);
    scrollToBottom();
  }

  function hideTypingIndicator() {
    isTyping = false;
    const typingEl = document.getElementById('aurora-typing');
    if (typingEl) typingEl.remove();
  }

  // ========== Session Management ==========

  async function createSession() {
    try {
      const response = await fetch(`${FUNCTIONS_URL}/createWebsiteSession`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pageUrl: window.location.href,
          referrer: document.referrer,
          userAgent: navigator.userAgent,
        })
      });

      if (!response.ok) throw new Error('Failed to create session');
      
      const data = await response.json();
      sessionId = data.sessionId;
      conversationId = data.conversationId;
      customerId = data.customerId;
      
      saveSession();
      startMessageListener();
      
      console.log('🌌 Chat session created:', sessionId);
    } catch (error) {
      console.error('Error creating session:', error);
      showError('Unable to connect. Please try again.');
    }
  }

  function trackPageVisit() {
    if (!sessionId) return;
    
    // Update session with current page
    fetch(`${FUNCTIONS_URL}/updateWebsiteSession`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sessionId,
        currentPageUrl: window.location.href
      })
    }).catch(e => console.error('Error tracking page:', e));
  }

  // ========== Message Sending ==========

  async function handleSendMessage(e) {
    e.preventDefault();
    
    const content = inputElement.value.trim();
    if (!content) return;

    // Clear input immediately for better UX
    inputElement.value = '';
    autoResizeTextarea();

    // Ensure session exists
    if (!sessionId) {
      await createSession();
    }

    // Optimistically add message to UI
    const tempId = 'temp_' + Date.now();
    const tempMessage = {
      id: tempId,
      content,
      direction: 'inbound',
      timestamp: new Date().toISOString(),
      status: 'sending'
    };
    addMessage(tempMessage);

    try {
      const response = await fetch(`${FUNCTIONS_URL}/sendWebsiteMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId,
          conversationId,
          content,
          visitorName,
          visitorEmail
        })
      });

      if (!response.ok) throw new Error('Failed to send message');
      
      const data = await response.json();
      
      // Update temp message with real ID
      const msgIndex = messages.findIndex(m => m.id === tempId);
      if (msgIndex >= 0) {
        messages[msgIndex].id = data.messageId;
        messages[msgIndex].status = 'sent';
        saveSession();
      }

      // If this is the first message, prompt for identification
      if (messages.length === 1 && !visitorName && !visitorEmail) {
        // Could show identification form here
      }
      
    } catch (error) {
      console.error('Error sending message:', error);
      
      // Mark message as failed
      const msgIndex = messages.findIndex(m => m.id === tempId);
      if (msgIndex >= 0) {
        messages[msgIndex].status = 'failed';
        renderMessages();
      }
      
      showError('Message failed to send. Tap to retry.');
    }
  }

  // ========== Real-time Message Listener ==========

  function startMessageListener() {
    if (!conversationId || messageListener) return;

    // Use Firestore REST API with long-polling
    // In production, you'd use the Firestore SDK or a Cloud Function webhook
    pollForMessages();
  }

  async function pollForMessages() {
    if (!conversationId) return;

    try {
      const url = `${FIRESTORE_URL}/messages?` + new URLSearchParams({
        'orderBy': 'timestamp',
        'pageSize': '50'
      });

      const response = await fetch(url + `&where.fieldFilter.field.fieldPath=conversationId&where.fieldFilter.op=EQUAL&where.fieldFilter.value.stringValue=${conversationId}`);
      
      if (response.ok) {
        const data = await response.json();
        if (data.documents) {
          const newMessages = data.documents
            .map(doc => parseFirestoreDocument(doc))
            .filter(msg => !messages.some(m => m.id === msg.id))
            .sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

          newMessages.forEach(msg => addMessage(msg));
        }
      }
    } catch (e) {
      console.error('Error polling messages:', e);
    }

    // Poll every 3 seconds (in production, use real-time listeners)
    setTimeout(pollForMessages, 3000);
  }

  function parseFirestoreDocument(doc) {
    const fields = doc.fields;
    return {
      id: doc.name.split('/').pop(),
      content: fields.content?.stringValue || '',
      direction: fields.direction?.stringValue || 'inbound',
      timestamp: fields.timestamp?.timestampValue || new Date().toISOString(),
      status: fields.status?.stringValue || 'sent'
    };
  }

  // ========== Utilities ==========

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML.replace(/\n/g, '<br>');
  }

  function formatTime(timestamp) {
    const date = new Date(timestamp);
    const now = new Date();
    const diffDays = Math.floor((now - date) / (1000 * 60 * 60 * 24));
    
    if (diffDays === 0) {
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else if (diffDays === 1) {
      return 'Yesterday ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else if (diffDays < 7) {
      return date.toLocaleDateString([], { weekday: 'short' }) + ' ' + 
             date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else {
      return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
    }
  }

  function showError(message) {
    // Could show a toast notification
    console.error('Chat Error:', message);
  }

  // ========== Public API ==========

  window.AuroraChat = {
    open: openChat,
    close: closeChat,
    toggle: toggleChat,
    identify: (name, email) => {
      visitorName = name;
      visitorEmail = email;
      saveSession();
    },
    destroy: () => {
      if (widget && widget.parentNode) {
        widget.parentNode.removeChild(widget);
      }
    }
  };

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();

