/**
 * Aurora Viking Chat Widget
 * Embeddable chat widget for auroraviking.is/com websites
 * Connects to Firebase Firestore for real-time messaging
 * Uses Firebase Anonymous Authentication for secure API access
 */

(function () {
  'use strict';

  // Configuration (set via window.AURORA_CHAT_CONFIG before loading this script)
  const config = window.AURORA_CHAT_CONFIG || {};
  const PROJECT_ID = config.projectId || 'aurora-viking-staff';
  const API_KEY = config.apiKey || 'AIzaSyDdCYDwnVw2IuWPaco_QUzGBMEz8ef2Zj4';
  const POSITION = config.position || 'bottom-right';
  const PRIMARY_COLOR = config.primaryColor || '#00E5FF';
  const GREETING = config.greeting || 'Hey there! ✨ Need to reschedule, change your pickup spot, or have questions about your tour? Just drop your booking number and we\'ll sort it out!';
  const OFFLINE_MESSAGE = config.offlineMessage || 'Leave a message and we\'ll get back to you soon!';
  const QUICK_REPLIES = config.quickReplies || [
    'Reschedule my tour',
    'Change pickup location',
    'Cancel booking',
    'Tour info'
  ];

  // Firebase configuration
  const FIREBASE_CONFIG = {
    apiKey: API_KEY,
    authDomain: `${PROJECT_ID}.firebaseapp.com`,
    projectId: PROJECT_ID,
  };

  // Firebase endpoints
  const FIRESTORE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
  const FUNCTIONS_URL = `https://us-central1-${PROJECT_ID}.cloudfunctions.net`;

  // State
  let sessionId = null;
  let conversationId = null;
  let customerId = null;
  let visitorName = null;
  let visitorEmail = null;
  let bookingRef = null;
  let messages = [];
  let isOpen = false;

  // Check for embedded mode (no button, just chat window)
  // Can be set via: ?embedded=true in URL or window.AURORA_CHAT_EMBEDDED = true
  const embeddedMode = window.AURORA_CHAT_EMBEDDED === true ||
    new URLSearchParams(window.location.search).get('embedded') === 'true';
  let isOnline = true;
  let isTyping = false;
  let unreadCount = 0;
  let messageListener = null;
  let lastMessageId = null;
  let authToken = null;
  let firebaseApp = null;
  let isAuthReady = false;

  // DOM Elements (will be created on init)
  let widget = null;
  let chatButton = null;
  let chatWindow = null;
  let messagesContainer = null;
  let inputElement = null;
  let badgeElement = null;

  // ========== Firebase Initialization ==========

  async function loadFirebaseSDK() {
    // Load Firebase SDKs (compat version for vanilla JS)
    if (typeof firebase === 'undefined') {
      await loadScript('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
      await loadScript('https://www.gstatic.com/firebasejs/10.7.1/firebase-auth-compat.js');
      await loadScript('https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore-compat.js');
    }

    // Initialize Firebase
    if (!firebase.apps.length) {
      firebaseApp = firebase.initializeApp(FIREBASE_CONFIG);
    } else {
      firebaseApp = firebase.app();
    }

    console.log('🔥 Firebase initialized with Firestore');
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  async function initializeAuth() {
    try {
      // Sign in anonymously
      const userCredential = await firebase.auth().signInAnonymously();
      console.log('🔐 Signed in anonymously:', userCredential.user.uid);

      // Get auth token
      authToken = await userCredential.user.getIdToken();
      isAuthReady = true;

      // Listen for token refresh
      firebase.auth().onIdTokenChanged(async (user) => {
        if (user) {
          authToken = await user.getIdToken();
          console.log('🔄 Auth token refreshed');
        }
      });

      return userCredential.user.uid;
    } catch (error) {
      console.error('❌ Anonymous auth failed:', error);
      throw error;
    }
  }

  async function getAuthToken() {
    if (!isAuthReady) {
      await initializeAuth();
    }

    // Refresh token if needed
    const user = firebase.auth().currentUser;
    if (user) {
      authToken = await user.getIdToken();
    }

    return authToken;
  }

  // ========== Authenticated Fetch Helper ==========

  async function authenticatedFetch(url, options = {}) {
    const token = await getAuthToken();

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      ...options.headers,
    };

    return fetch(url, {
      ...options,
      headers,
    });
  }

  // ========== Initialization ==========

  async function init() {
    try {
      // Load Firebase SDK
      await loadFirebaseSDK();

      // Initialize anonymous auth
      await initializeAuth();

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

      console.log('🌌 Aurora Chat Widget initialized with Firebase Auth');
    } catch (error) {
      console.error('❌ Failed to initialize chat widget:', error);
      // Still create widget but show error state
      createWidget();
      loadStyles();
    }
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
        bookingRef = data.bookingRef;
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
        bookingRef,
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
        <span class="aurora-chat-label">CHAT</span>
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
        
        <!-- Visitor Info Form (collapsible) -->
        <div class="aurora-chat-visitor-form">
          <button type="button" class="aurora-chat-visitor-toggle">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
              <circle cx="12" cy="7" r="4"/>
            </svg>
            <span class="aurora-visitor-toggle-text">Add your details (optional)</span>
            <svg class="aurora-visitor-chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="6 9 12 15 18 9"/>
            </svg>
          </button>
          <div class="aurora-chat-visitor-fields" style="display: none;">
            <input type="text" class="aurora-visitor-input" id="aurora-visitor-name" placeholder="Your name" autocomplete="name"/>
            <input type="email" class="aurora-visitor-input" id="aurora-visitor-email" placeholder="Email address" autocomplete="email"/>
            <input type="text" class="aurora-visitor-input" id="aurora-visitor-booking" placeholder="Booking ref (e.g. AUR-12345)"/>
          </div>
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

    // Handle embedded mode (no button, always open)
    if (embeddedMode) {
      widget.classList.add('embedded');
      chatButton.style.display = 'none';
      chatWindow.classList.add('open');
      widget.querySelector('.aurora-chat-close').style.display = 'none';
      isOpen = true;
      console.log('🌌 Aurora Chat running in embedded mode');
    }

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

    // Visitor info form toggle
    const visitorToggle = widget.querySelector('.aurora-chat-visitor-toggle');
    const visitorFields = widget.querySelector('.aurora-chat-visitor-fields');
    const visitorChevron = widget.querySelector('.aurora-visitor-chevron');

    visitorToggle.addEventListener('click', () => {
      const isHidden = visitorFields.style.display === 'none';
      visitorFields.style.display = isHidden ? 'flex' : 'none';
      visitorChevron.style.transform = isHidden ? 'rotate(180deg)' : 'rotate(0deg)';
    });

    // Capture visitor info on input change
    widget.querySelector('#aurora-visitor-name').addEventListener('change', (e) => {
      visitorName = e.target.value.trim() || null;
      saveSession();
    });
    widget.querySelector('#aurora-visitor-email').addEventListener('change', (e) => {
      visitorEmail = e.target.value.trim() || null;
      saveSession();
    });
    widget.querySelector('#aurora-visitor-booking').addEventListener('change', (e) => {
      bookingRef = e.target.value.trim() || null;
      saveSession();
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

  // ========== Session Management - Direct Firestore ==========

  // Helper to capture visitor info from form inputs
  function captureVisitorInfo() {
    const nameInput = document.getElementById('aurora-visitor-name');
    const emailInput = document.getElementById('aurora-visitor-email');
    const bookingInput = document.getElementById('aurora-visitor-booking');

    if (nameInput && nameInput.value.trim()) {
      visitorName = nameInput.value.trim();
    }
    if (emailInput && emailInput.value.trim()) {
      visitorEmail = emailInput.value.trim();
    }
    if (bookingInput && bookingInput.value.trim()) {
      bookingRef = bookingInput.value.trim().toUpperCase();
    }

    console.log('📋 Visitor info captured:', {
      name: visitorName,
      email: visitorEmail,
      booking: bookingRef,
      nameInputValue: nameInput?.value,
      emailInputValue: emailInput?.value,
      bookingInputValue: bookingInput?.value
    });
  }

  async function createSession() {
    if (!isAuthReady) {
      console.log('⏳ Waiting for auth...');
      await initializeAuth();
    }

    // Capture visitor info from form before creating session
    captureVisitorInfo();

    try {
      const db = firebase.firestore();
      const uid = firebase.auth().currentUser?.uid || 'anon_' + Date.now();

      // Generate unique session ID
      sessionId = 'ws_' + uid.substring(0, 12) + '_' + Date.now().toString(36);

      // Create customer document
      const customerRef = await db.collection('customers').add({
        name: visitorName || 'Website Visitor',
        email: visitorEmail || null,
        phone: null,
        source: 'website_chat',
        sessionId: sessionId,
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        firstPageUrl: window.location.href,
        referrer: document.referrer || null,
        userAgent: navigator.userAgent || null,
      });
      customerId = customerRef.id;

      // Create conversation document
      const conversationRef = await db.collection('conversations').add({
        customerId: customerId,
        customerName: visitorName || 'Website Visitor',
        customerEmail: visitorEmail || null,
        channel: 'website',
        subject: bookingRef ? `Website Chat - ${bookingRef}` : 'Website Chat',
        status: 'active',
        hasUnread: false,
        unreadCount: 0,
        bookingIds: bookingRef ? [bookingRef.toUpperCase()] : [],
        messageIds: [],
        lastMessageAt: firebase.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: '',
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        channelMetadata: {
          website: {
            sessionId: sessionId,
            firstPageUrl: window.location.href,
            referrer: document.referrer || null,
            bookingRef: bookingRef || null,
          }
        },
        inboxEmail: 'website',
      });
      conversationId = conversationRef.id;

      // Create website_session document
      await db.collection('website_sessions').doc(sessionId).set({
        sessionId: sessionId,
        conversationId: conversationId,
        customerId: customerId,
        visitorName: null,
        visitorEmail: null,
        bookingRef: null,
        firstPageUrl: window.location.href,
        currentPageUrl: window.location.href,
        referrer: document.referrer || null,
        userAgent: navigator.userAgent || null,
        isOnline: true,
        lastSeen: firebase.firestore.FieldValue.serverTimestamp(),
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      });

      saveSession();
      startMessageListener();

      console.log('🌌 Chat session created via Firestore:', sessionId);
    } catch (error) {
      console.error('Error creating session:', error);
      showError('Unable to connect. Please try again.');
    }
  }

  function trackPageVisit() {
    if (!sessionId) return;

    // Update session with current page via Firestore
    const db = firebase.firestore();
    db.collection('website_sessions').doc(sessionId).update({
      currentPageUrl: window.location.href,
      lastSeen: firebase.firestore.FieldValue.serverTimestamp(),
      isOnline: true,
    }).catch(e => console.error('Error tracking page:', e));
  }

  // ========== Message Sending - Direct Firestore ==========

  async function handleSendMessage(e) {
    e.preventDefault();

    const content = inputElement.value.trim();
    if (!content) return;

    // Clear input immediately for better UX
    inputElement.value = '';
    autoResizeTextarea();

    // Capture any visitor info from form
    captureVisitorInfo();

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
      const db = firebase.firestore();

      // Create message document directly in Firestore
      const messageRef = await db.collection('messages').add({
        conversationId: conversationId,
        customerId: customerId,
        channel: 'website',
        direction: 'inbound',
        content: content,
        timestamp: firebase.firestore.FieldValue.serverTimestamp(),
        status: 'delivered',
        channelMetadata: {
          website: {
            sessionId: sessionId,
            pageUrl: window.location.href,
          }
        },
      });

      // Build conversation update with all visitor info
      const conversationUpdate = {
        lastMessageAt: firebase.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: content.substring(0, 100),
        hasUnread: true,
        unreadCount: firebase.firestore.FieldValue.increment(1),
        status: 'active',
        customerName: visitorName || 'Website Visitor',
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        messageIds: firebase.firestore.FieldValue.arrayUnion(messageRef.id),
      };

      // Add email if provided
      if (visitorEmail) {
        conversationUpdate.customerEmail = visitorEmail;
      }

      // Add booking ref if provided
      if (bookingRef) {
        conversationUpdate.bookingIds = firebase.firestore.FieldValue.arrayUnion(bookingRef.toUpperCase());
        conversationUpdate['channelMetadata.website.bookingRef'] = bookingRef.toUpperCase();
        conversationUpdate.subject = 'Website Chat - ' + bookingRef.toUpperCase();
      }

      // Update conversation
      await db.collection('conversations').doc(conversationId).update(conversationUpdate);

      // Update session last seen
      await db.collection('website_sessions').doc(sessionId).update({
        lastSeen: firebase.firestore.FieldValue.serverTimestamp(),
        isOnline: true,
        visitorName: visitorName || null,
        visitorEmail: visitorEmail || null,
      });

      // Update temp message with real ID
      const msgIndex = messages.findIndex(m => m.id === tempId);
      if (msgIndex >= 0) {
        messages[msgIndex].id = messageRef.id;
        messages[msgIndex].status = 'sent';
        saveSession();
      }

      console.log('✅ Message sent via Firestore:', messageRef.id);

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

    // Use Firestore SDK for real-time updates
    const db = firebase.firestore();

    // Query must include channel='website' to match security rules
    messageListener = db.collection('messages')
      .where('conversationId', '==', conversationId)
      .where('channel', '==', 'website')
      .orderBy('timestamp', 'asc')
      .onSnapshot((snapshot) => {
        snapshot.docChanges().forEach((change) => {
          if (change.type === 'added') {
            const doc = change.doc;
            const data = doc.data();

            // Only add staff replies (outbound messages)
            if (data.direction === 'outbound') {
              const msg = {
                id: doc.id,
                content: data.content || '',
                direction: 'outbound',
                timestamp: data.timestamp?.toDate?.()?.toISOString() || new Date().toISOString(),
                status: 'delivered'
              };

              // Avoid duplicates
              if (!messages.some(m => m.id === msg.id)) {
                addMessage(msg);
                console.log('📩 Staff reply received:', doc.id);
              }
            }
          }
        });
      }, (error) => {
        console.error('Message listener error:', error);
        // Fall back to polling on error
        setTimeout(() => startMessageListener(), 5000);
      });

    console.log('👂 Real-time message listener started for:', conversationId);
  }

  function stopMessageListener() {
    if (messageListener) {
      messageListener();
      messageListener = null;
    }
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

      // Update session on server
      if (sessionId && isAuthReady) {
        authenticatedFetch(`${FUNCTIONS_URL}/updateWebsiteSession`, {
          method: 'POST',
          body: JSON.stringify({
            sessionId,
            visitorName: name,
            visitorEmail: email
          })
        }).catch(e => console.error('Error updating visitor info:', e));
      }
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
