/**
 * Gmail Integration Module
 * Handles Gmail OAuth, polling, and sending emails
 */
const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { google } = require('googleapis');
const { admin, db } = require('../utils/firebase');
const { GMAIL_REDIRECT_URI, GMAIL_SCOPES } = require('../config');
const { findOrCreateCustomer, findOrCreateConversation, extractBookingReferences } = require('./inbox_core');

// ============================================
// GMAIL HELPER FUNCTIONS
// ============================================

/**
 * Get Gmail OAuth2 client
 */
function getGmailOAuth2Client(clientId, clientSecret) {
    return new google.auth.OAuth2(clientId, clientSecret, GMAIL_REDIRECT_URI);
}

/**
 * Store Gmail tokens in Firestore (supports multiple accounts)
 * Each account is stored in system/gmail_accounts/{emailId}
 */
async function storeGmailTokens(email, tokens) {
    const emailId = email.replace(/[@.]/g, '_');

    await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set({
        email,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        expiryDate: tokens.expiry_date,
        lastCheckTimestamp: Date.now(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log(`✅ Gmail tokens stored for ${email}`);
}

/**
 * Get Gmail tokens for a specific email from Firestore
 * Checks both new location (gmail_accounts) and old location (gmail_tokens) for backwards compatibility
 */
async function getGmailTokens(email) {
    const emailId = email.replace(/[@.]/g, '_');

    // Try new location first
    const newDoc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
    if (newDoc.exists) {
        return { ...newDoc.data(), id: emailId };
    }

    // Fallback to old location (system/gmail_tokens)
    console.log(`📍 Checking legacy token location for ${email}`);
    const oldDoc = await db.collection('system').doc('gmail_tokens').get();
    if (oldDoc.exists) {
        const data = oldDoc.data();
        if (data.email === email || email === 'info@auroraviking.is') {
            console.log(`✅ Found tokens in legacy location for ${email}`);
            return { ...data, id: emailId };
        }
    }

    return null;
}

/**
 * Get all connected Gmail accounts
 */
async function getAllGmailAccounts() {
    const snapshot = await db.collection('system').doc('gmail_accounts').collection('accounts').get();
    if (snapshot.empty) {
        return [];
    }
    return snapshot.docs.map(doc => ({ ...doc.data(), id: doc.id }));
}

/**
 * Update sync state for a specific Gmail account
 */
async function updateGmailSyncState(email, updates) {
    const emailId = email.replace(/[@.]/g, '_');
    await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).update({
        ...updates,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

/**
 * Auto-migrate legacy Gmail account to new multi-account structure
 */
async function autoMigrateLegacyGmailAccount() {
    try {
        const oldTokensDoc = await db.collection('system').doc('gmail_tokens').get();
        if (!oldTokensDoc.exists) {
            console.log('No legacy gmail_tokens found');
            return false;
        }

        const oldTokens = oldTokensDoc.data();
        console.log(`📧 Found legacy account: ${oldTokens.email}`);

        const oldSyncDoc = await db.collection('system').doc('gmail_sync').get();
        const oldSync = oldSyncDoc.exists ? oldSyncDoc.data() : {};

        const emailId = oldTokens.email.replace(/[@.]/g, '_');

        const existingDoc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
        if (existingDoc.exists) {
            console.log('Account already migrated');
            return true;
        }

        const newAccountData = {
            email: oldTokens.email,
            accessToken: oldTokens.accessToken,
            refreshToken: oldTokens.refreshToken,
            expiryDate: oldTokens.expiryDate,
            lastCheckTimestamp: oldSync.lastCheckTimestamp || Date.now(),
            lastPollAt: oldSync.lastPollAt || null,
            lastPollCount: oldSync.lastPollCount || 0,
            lastProcessedCount: oldSync.lastProcessedCount || 0,
            lastError: null,
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set(newAccountData);
        console.log(`✅ Auto-migrated ${oldTokens.email} to new structure`);

        return true;
    } catch (error) {
        console.error('❌ Auto-migration error:', error);
        return false;
    }
}

/**
 * Get authenticated Gmail client for a specific email account
 */
async function getGmailClient(email, clientId, clientSecret) {
    const tokens = await getGmailTokens(email);
    if (!tokens) {
        throw new Error(`Gmail account ${email} not authorized. Please complete OAuth flow first.`);
    }

    const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
    oauth2Client.setCredentials({
        access_token: tokens.accessToken,
        refresh_token: tokens.refreshToken,
        expiry_date: tokens.expiryDate,
    });

    oauth2Client.on('tokens', async (newTokens) => {
        console.log(`🔄 Gmail tokens refreshed for ${email}`);
        await storeGmailTokens(tokens.email, {
            access_token: newTokens.access_token || tokens.accessToken,
            refresh_token: newTokens.refresh_token || tokens.refreshToken,
            expiry_date: newTokens.expiry_date,
        });
    });

    return google.gmail({ version: 'v1', auth: oauth2Client });
}

/**
 * Poll a single Gmail account for new messages
 */
async function pollSingleGmailAccount(account, clientId, clientSecret) {
    const gmail = await getGmailClient(account.email, clientId, clientSecret);

    const lastCheck = account.lastCheckTimestamp || (Date.now() - 86400000);
    const afterTimestamp = Math.floor(lastCheck / 1000);
    const query = `after:${afterTimestamp} in:inbox`;

    console.log(`🔍 Searching: ${query}`);

    const listResponse = await gmail.users.messages.list({
        userId: 'me',
        q: query,
        maxResults: 50,
    });

    const messages = listResponse.data.messages || [];
    console.log(`📧 Found ${messages.length} new messages`);

    let processedCount = 0;

    for (const msg of messages) {
        const existingMsg = await db.collection('messages')
            .where('channelMetadata.gmail.messageId', '==', msg.id)
            .limit(1)
            .get();

        if (!existingMsg.empty) {
            console.log(`⏭️ Skipping already processed: ${msg.id}`);
            continue;
        }

        const fullMessage = await gmail.users.messages.get({
            userId: 'me',
            id: msg.id,
            format: 'full',
        });

        await processGmailMessageData(fullMessage.data, account.email);
        processedCount++;
    }

    await updateGmailSyncState(account.email, {
        lastCheckTimestamp: Date.now(),
        lastPollAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPollCount: messages.length,
        lastProcessedCount: processedCount,
        lastError: null,
    });

    console.log(`✅ Processed ${processedCount} from ${account.email}`);
    return processedCount;
}

/**
 * Process a Gmail message and create Firestore records
 */
async function processGmailMessageData(gmailMessage, inboxEmail = 'info@auroraviking.is') {
    const headers = gmailMessage.payload.headers;

    const getHeader = (name) => {
        const header = headers.find(h => h.name.toLowerCase() === name.toLowerCase());
        return header ? header.value : null;
    };

    const from = getHeader('From');
    const to = getHeader('To');
    const subject = getHeader('Subject') || '(No Subject)';
    const messageId = gmailMessage.id;
    const threadId = gmailMessage.threadId;
    const internalDate = parseInt(gmailMessage.internalDate);

    const emailMatch = from.match(/<([^>]+)>/);
    const fromEmail = emailMatch ? emailMatch[1] : from;
    const fromName = emailMatch ? from.replace(/<[^>]+>/, '').trim() : null;

    let bodyPlain = '';
    let bodyHtml = '';

    function extractBodiesFromPart(part, results = { plain: '', html: '' }) {
        if (!part) return results;

        if (part.body && part.body.data) {
            const decoded = Buffer.from(part.body.data, 'base64').toString('utf-8');
            if (part.mimeType === 'text/plain' && !results.plain) {
                results.plain = decoded;
            } else if (part.mimeType === 'text/html' && !results.html) {
                results.html = decoded;
            }
        }

        if (part.parts) {
            for (const subPart of part.parts) {
                extractBodiesFromPart(subPart, results);
            }
        }

        return results;
    }

    const bodies = extractBodiesFromPart(gmailMessage.payload);
    bodyHtml = bodies.html || '';
    bodyPlain = bodies.plain || '';

    if (!bodyPlain && bodyHtml) {
        bodyPlain = bodyHtml
            .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
            .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
            .replace(/<[^>]*>/g, ' ')
            .replace(/&nbsp;/g, ' ')
            .replace(/&amp;/g, '&')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/\s+/g, ' ')
            .trim();
    }

    let body = bodyPlain || bodyHtml;

    console.log(`📝 Extracted body: plain=${bodyPlain.length} chars, html=${bodyHtml.length} chars`);

    if (body.length > 10000) {
        body = body.substring(0, 10000) + '... [truncated]';
    }
    if (bodyHtml.length > 50000) {
        bodyHtml = bodyHtml.substring(0, 50000) + '... [truncated]';
    }

    console.log(`📨 Processing email from: ${fromEmail}, subject: ${subject}`);

    const detectedBookingNumbers = extractBookingReferences(body + ' ' + subject);

    const customerId = await findOrCreateCustomer('gmail', fromEmail, fromName);

    const conversationId = await findOrCreateConversation(
        customerId,
        'gmail',
        threadId,
        subject,
        body.substring(0, 200),
        inboxEmail
    );

    const messageData = {
        conversationId,
        customerId,
        channel: 'gmail',
        direction: 'inbound',
        subject,
        content: body,
        contentHtml: bodyHtml || null,
        timestamp: new Date(internalDate),
        channelMetadata: {
            gmail: {
                threadId,
                messageId,
                from: fromEmail,
                fromName: fromName,
                to: to ? to.split(',').map(t => t.trim()) : [inboxEmail],
                inboxEmail: inboxEmail,
            },
        },
        bookingIds: [],
        detectedBookingNumbers,
        status: 'pending',
        flaggedForReview: false,
        priority: 'normal',
    };

    const msgRef = await db.collection('messages').add(messageData);
    console.log(`📨 Message created: ${msgRef.id}`);

    await db.collection('conversations').doc(conversationId).update({
        messageIds: admin.firestore.FieldValue.arrayUnion(msgRef.id),
        bookingIds: admin.firestore.FieldValue.arrayUnion(...detectedBookingNumbers),
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessagePreview: body.substring(0, 100),
        unreadCount: admin.firestore.FieldValue.increment(1),
    });

    return { messageId: msgRef.id, conversationId, customerId };
}

// ============================================
// CLOUD FUNCTIONS
// ============================================

/**
 * Gmail OAuth - Step 1: Generate authorization URL
 */
const gmailOAuthStart = onRequest(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    },
    async (req, res) => {
        const clientId = process.env.GMAIL_CLIENT_ID;
        const clientSecret = process.env.GMAIL_CLIENT_SECRET;

        const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);

        const authUrl = oauth2Client.generateAuthUrl({
            access_type: 'offline',
            scope: GMAIL_SCOPES,
            prompt: 'consent',
        });

        res.send(`
      <html>
        <head>
          <title>Aurora Viking - Gmail Authorization</title>
          <style>
            body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }
            .btn { display: inline-block; background: #4285f4; color: white; padding: 12px 24px; 
                   text-decoration: none; border-radius: 4px; font-size: 16px; }
            .btn:hover { background: #3367d6; }
          </style>
        </head>
        <body>
          <h1>🌌 Aurora Viking - Gmail Setup</h1>
          <p>Click the button below to authorize Gmail access for the Unified Inbox.</p>
          <p>This will allow the app to:</p>
          <ul>
            <li>Read incoming emails</li>
            <li>Send replies on your behalf</li>
            <li>Mark emails as read</li>
          </ul>
          <p><a href="${authUrl}" class="btn">Authorize Gmail Access</a></p>
        </body>
      </html>
    `);
    }
);

/**
 * Gmail OAuth - Step 2: Handle callback and store tokens
 */
const gmailOAuthCallback = onRequest(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    },
    async (req, res) => {
        const code = req.query.code;

        if (!code) {
            res.status(400).send('Missing authorization code');
            return;
        }

        try {
            const clientId = process.env.GMAIL_CLIENT_ID;
            const clientSecret = process.env.GMAIL_CLIENT_SECRET;

            const oauth2Client = getGmailOAuth2Client(clientId, clientSecret);
            const { tokens } = await oauth2Client.getToken(code);

            oauth2Client.setCredentials(tokens);

            const gmail = google.gmail({ version: 'v1', auth: oauth2Client });
            const profile = await gmail.users.getProfile({ userId: 'me' });
            const email = profile.data.emailAddress;

            await storeGmailTokens(email, tokens);

            const accounts = await getAllGmailAccounts();

            res.send(`
        <html>
          <head>
            <title>Gmail Connected!</title>
            <style>
              body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; text-align: center; }
              .success { color: #34a853; font-size: 48px; }
              .accounts { background: #f5f5f5; padding: 15px; border-radius: 8px; margin-top: 20px; }
            </style>
          </head>
          <body>
            <div class="success">✅</div>
            <h1>Gmail Connected Successfully!</h1>
            <p>Email: <strong>${email}</strong></p>
            <p>The Aurora Viking Staff app will now receive emails from this inbox.</p>
            <div class="accounts">
              <strong>Connected Accounts (${accounts.length}):</strong><br/>
              ${accounts.map(a => a.email).join('<br/>')}
            </div>
            <p style="margin-top: 20px;">You can close this window.</p>
          </body>
        </html>
      `);
        } catch (error) {
            console.error('OAuth callback error:', error);
            res.status(500).send(`
        <html>
          <body>
            <h1>❌ Error</h1>
            <p>${error.message}</p>
          </body>
        </html>
      `);
        }
    }
);

/**
 * Poll Gmail for new messages (runs every 1 minute)
 */
const pollGmailInbox = onSchedule(
    {
        schedule: 'every 1 minutes',
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
        timeoutSeconds: 60,
    },
    async () => {
        console.log('📬 Polling all Gmail inboxes...');

        try {
            const clientId = process.env.GMAIL_CLIENT_ID;
            const clientSecret = process.env.GMAIL_CLIENT_SECRET;

            let accounts = await getAllGmailAccounts();

            if (accounts.length === 0) {
                console.log('🔄 No accounts in new structure, checking for legacy accounts...');
                const migrated = await autoMigrateLegacyGmailAccount();
                if (migrated) {
                    accounts = await getAllGmailAccounts();
                }
            }

            if (accounts.length === 0) {
                console.log('⚠️ No Gmail accounts authorized yet. Skipping poll.');
                return;
            }

            console.log(`📫 Found ${accounts.length} connected Gmail account(s)`);

            let totalProcessed = 0;

            for (const account of accounts) {
                try {
                    console.log(`\n📧 Polling: ${account.email}`);
                    const processedCount = await pollSingleGmailAccount(account, clientId, clientSecret);
                    totalProcessed += processedCount;
                } catch (accountError) {
                    console.error(`❌ Error polling ${account.email}:`, accountError.message);
                    await updateGmailSyncState(account.email, {
                        lastError: accountError.message,
                        lastErrorAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            }

            console.log(`\n✅ Gmail poll complete. Processed ${totalProcessed} new messages across ${accounts.length} account(s).`);
        } catch (error) {
            console.error('❌ Gmail poll error:', error);
        }
    }
);

/**
 * Send email via Gmail (called when staff replies)
 */
const sendGmailReply = onCall(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    },
    async (request) => {
        const { conversationId, content, messageId } = request.data;

        if (!conversationId || !content) {
            throw new Error('Missing required fields: conversationId, content');
        }

        try {
            const clientId = process.env.GMAIL_CLIENT_ID;
            const clientSecret = process.env.GMAIL_CLIENT_SECRET;

            const convDoc = await db.collection('conversations').doc(conversationId).get();
            if (!convDoc.exists) {
                throw new Error('Conversation not found');
            }
            const conv = convDoc.data();

            const customerDoc = await db.collection('customers').doc(conv.customerId).get();
            if (!customerDoc.exists) {
                throw new Error('Customer not found');
            }
            const customer = customerDoc.data();

            const toEmail = customer.email || customer.channels?.gmail;
            if (!toEmail) {
                throw new Error('Customer email not found');
            }

            const inboxEmail = conv.inboxEmail || conv.channelMetadata?.gmail?.inbox || 'info@auroraviking.is';
            const gmail = await getGmailClient(inboxEmail, clientId, clientSecret);

            const subject = conv.subject?.startsWith('Re:') ? conv.subject : `Re: ${conv.subject || 'Your inquiry'}`;
            const threadId = conv.channelMetadata?.gmail?.threadId;

            let inReplyTo = '';
            let references = '';
            if (messageId) {
                const origMsg = await db.collection('messages').doc(messageId).get();
                if (origMsg.exists) {
                    const origData = origMsg.data();
                    inReplyTo = origData.channelMetadata?.gmail?.messageId || '';
                    references = inReplyTo;
                }
            }

            const emailLines = [
                `From: ${inboxEmail}`,
                `To: ${toEmail}`,
                `Subject: ${subject}`,
                `Content-Type: text/plain; charset=utf-8`,
            ];

            if (inReplyTo) {
                emailLines.push(`In-Reply-To: <${inReplyTo}>`);
                emailLines.push(`References: <${references}>`);
            }

            emailLines.push('', content);

            const rawMessage = Buffer.from(emailLines.join('\r\n')).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

            const sendResponse = await gmail.users.messages.send({
                userId: 'me',
                requestBody: {
                    raw: rawMessage,
                    threadId: threadId,
                },
            });

            console.log(`📤 Email sent: ${sendResponse.data.id}`);

            const outboundMsg = {
                conversationId,
                customerId: conv.customerId,
                channel: 'gmail',
                direction: 'outbound',
                subject,
                content,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                channelMetadata: {
                    gmail: {
                        messageId: sendResponse.data.id,
                        threadId: sendResponse.data.threadId,
                        from: inboxEmail,
                        to: [toEmail],
                    },
                },
                bookingIds: [],
                detectedBookingNumbers: extractBookingReferences(content),
                status: 'sent',
                handledBy: request.auth?.uid || 'unknown',
                handledAt: admin.firestore.FieldValue.serverTimestamp(),
                gmailMessageId: sendResponse.data.id,
            };

            const outMsgRef = await db.collection('messages').add(outboundMsg);

            await convDoc.ref.update({
                lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
                lastMessagePreview: content.substring(0, 100),
                messageIds: admin.firestore.FieldValue.arrayUnion(outMsgRef.id),
                unreadCount: 0,
                status: 'active',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return {
                success: true,
                messageId: outMsgRef.id,
                gmailMessageId: sendResponse.data.id,
            };
        } catch (error) {
            console.error('❌ Error sending Gmail reply:', error);
            throw new Error(`Failed to send email: ${error.message}`);
        }
    }
);

/**
 * Manual trigger to poll Gmail (for testing)
 */
const triggerGmailPoll = onRequest(
    {
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    },
    async (req, res) => {
        console.log('📬 Manual Gmail poll triggered...');

        try {
            const clientId = process.env.GMAIL_CLIENT_ID;
            const clientSecret = process.env.GMAIL_CLIENT_SECRET;

            const accounts = await getAllGmailAccounts();
            if (accounts.length === 0) {
                res.status(400).send('No Gmail accounts authorized. Visit /gmailOAuthStart first.');
                return;
            }

            const allResults = [];

            for (const account of accounts) {
                try {
                    const gmail = await getGmailClient(account.email, clientId, clientSecret);

                    const listResponse = await gmail.users.messages.list({
                        userId: 'me',
                        q: 'in:inbox',
                        maxResults: 10,
                    });

                    const messages = listResponse.data.messages || [];
                    const results = [];

                    for (const msg of messages) {
                        const existingMsg = await db.collection('messages')
                            .where('channelMetadata.gmail.messageId', '==', msg.id)
                            .limit(1)
                            .get();

                        if (!existingMsg.empty) {
                            results.push({ id: msg.id, status: 'already_processed' });
                            continue;
                        }

                        const fullMessage = await gmail.users.messages.get({
                            userId: 'me',
                            id: msg.id,
                            format: 'full',
                        });

                        const result = await processGmailMessageData(fullMessage.data, account.email);
                        results.push({ id: msg.id, status: 'processed', ...result });
                    }

                    await updateGmailSyncState(account.email, {
                        lastCheckTimestamp: Date.now(),
                        lastManualPollAt: admin.firestore.FieldValue.serverTimestamp(),
                    });

                    allResults.push({
                        email: account.email,
                        messagesFound: messages.length,
                        results,
                    });
                } catch (accountError) {
                    allResults.push({
                        email: account.email,
                        error: accountError.message,
                    });
                }
            }

            res.json({
                success: true,
                accountsPolled: accounts.length,
                results: allResults,
            });
        } catch (error) {
            console.error('❌ Manual poll error:', error);
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Check Gmail connection status
 */
const gmailStatus = onRequest(
    {
        region: 'us-central1',
    },
    async (req, res) => {
        try {
            const accounts = await getAllGmailAccounts();

            res.json({
                connected: accounts.length > 0,
                accountCount: accounts.length,
                accounts: accounts.map(a => ({
                    email: a.email,
                    lastPollAt: a.lastPollAt,
                    lastPollCount: a.lastPollCount,
                    lastError: a.lastError,
                })),
            });
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    }
);

/**
 * Firestore trigger: Auto-send email when outbound message is created
 */
const onOutboundMessageCreated = onDocumentCreated(
    {
        document: 'messages/{messageId}',
        region: 'us-central1',
        secrets: ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET'],
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) {
            console.log('No data in message document');
            return;
        }

        const messageData = snapshot.data();
        const messageId = event.params.messageId;

        if (messageData.direction !== 'outbound' || messageData.channel !== 'gmail') {
            return;
        }

        if (messageData.status === 'sent' || messageData.gmailMessageId) {
            console.log(`Message ${messageId} already sent, skipping`);
            return;
        }

        console.log(`📤 Sending outbound message: ${messageId}`);

        try {
            const clientId = process.env.GMAIL_CLIENT_ID;
            const clientSecret = process.env.GMAIL_CLIENT_SECRET;

            const convDoc = await db.collection('conversations').doc(messageData.conversationId).get();
            if (!convDoc.exists) {
                console.error(`Conversation ${messageData.conversationId} not found`);
                await snapshot.ref.update({ status: 'failed', error: 'Conversation not found' });
                return;
            }
            const conv = convDoc.data();

            const customerDoc = await db.collection('customers').doc(messageData.customerId).get();
            if (!customerDoc.exists) {
                console.error(`Customer ${messageData.customerId} not found`);
                await snapshot.ref.update({ status: 'failed', error: 'Customer not found' });
                return;
            }
            const customer = customerDoc.data();

            const toEmail = customer.email || customer.channels?.gmail;
            if (!toEmail) {
                console.error('Customer email not found');
                await snapshot.ref.update({ status: 'failed', error: 'No customer email' });
                return;
            }

            const inboxEmail = conv.inboxEmail || conv.channelMetadata?.gmail?.inbox || 'info@auroraviking.is';

            const tokens = await getGmailTokens(inboxEmail);
            if (!tokens) {
                console.error(`No tokens found for inbox: ${inboxEmail}`);
                await snapshot.ref.update({ status: 'failed', error: `No tokens for ${inboxEmail}` });
                return;
            }

            const gmail = await getGmailClient(inboxEmail, clientId, clientSecret);

            const subject = conv.subject?.startsWith('Re:') ? conv.subject : `Re: ${conv.subject || 'Your inquiry'}`;
            const threadId = conv.channelMetadata?.gmail?.threadId;

            const emailLines = [
                `From: ${inboxEmail}`,
                `To: ${toEmail}`,
                `Subject: ${subject}`,
                `Content-Type: text/plain; charset=utf-8`,
                '',
                messageData.content,
            ];

            const rawMessage = Buffer.from(emailLines.join('\r\n')).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

            const sendResponse = await gmail.users.messages.send({
                userId: 'me',
                requestBody: {
                    raw: rawMessage,
                    threadId: threadId,
                },
            });

            await snapshot.ref.update({
                status: 'sent',
                gmailMessageId: sendResponse.data.id,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                'channelMetadata.gmail.messageId': sendResponse.data.id,
                'channelMetadata.gmail.threadId': sendResponse.data.threadId,
            });

            console.log(`📧 Message ${messageId} sent successfully to ${toEmail}`);
        } catch (error) {
            console.error(`❌ Error sending message ${messageId}:`, error);

            await snapshot.ref.update({
                status: 'failed',
                error: error.message,
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    }
);

/**
 * Migration: Move existing Gmail account to new multi-account structure
 */
const migrateGmailToMultiAccount = onRequest(
    {
        region: 'us-central1',
    },
    async (req, res) => {
        console.log('🔄 Migrating Gmail account to new structure...');

        try {
            const oldTokensDoc = await db.collection('system').doc('gmail_tokens').get();
            if (!oldTokensDoc.exists) {
                res.send('No old gmail_tokens document found. Nothing to migrate.');
                return;
            }

            const oldTokens = oldTokensDoc.data();
            console.log(`Found old tokens for: ${oldTokens.email}`);

            const emailId = oldTokens.email.replace(/[@.]/g, '_');

            const existingDoc = await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).get();
            if (existingDoc.exists) {
                res.send(`Account ${oldTokens.email} already migrated.`);
                return;
            }

            const oldSyncDoc = await db.collection('system').doc('gmail_sync').get();
            const oldSync = oldSyncDoc.exists ? oldSyncDoc.data() : {};

            const newAccountData = {
                email: oldTokens.email,
                accessToken: oldTokens.accessToken,
                refreshToken: oldTokens.refreshToken,
                expiryDate: oldTokens.expiryDate,
                lastCheckTimestamp: oldSync.lastCheckTimestamp || Date.now(),
                lastPollAt: oldSync.lastPollAt || null,
                migratedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set(newAccountData);

            res.send(`
        <html>
          <body>
            <h1>✅ Migration Complete!</h1>
            <p>Migrated ${oldTokens.email} to new multi-account structure.</p>
            <hr/>
            <p style="color: #666;">You can now add more accounts by visiting <a href="/gmailOAuthStart">/gmailOAuthStart</a></p>
          </body>
        </html>
      `);
        } catch (error) {
            console.error('❌ Migration error:', error);
            res.status(500).send(`Migration error: ${error.message}`);
        }
    }
);

module.exports = {
    // Helper functions (for other modules)
    getGmailOAuth2Client,
    storeGmailTokens,
    getGmailTokens,
    getAllGmailAccounts,
    updateGmailSyncState,
    autoMigrateLegacyGmailAccount,
    getGmailClient,
    pollSingleGmailAccount,
    processGmailMessageData,
    // Cloud Functions
    gmailOAuthStart,
    gmailOAuthCallback,
    pollGmailInbox,
    sendGmailReply,
    triggerGmailPoll,
    gmailStatus,
    onOutboundMessageCreated,
    migrateGmailToMultiAccount,
};
