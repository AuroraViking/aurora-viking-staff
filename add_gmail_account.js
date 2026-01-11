// Script to add a new Gmail account to Aurora Viking Unified Inbox
// Run with: node add_gmail_account.js

const { google } = require('googleapis');
const http = require('http');
const url = require('url');
const admin = require('firebase-admin');

// Dynamic import for ESM 'open' package
let openBrowser;

// OAuth credentials - get from Firebase secrets or environment
// Run: firebase functions:secrets:get GMAIL_CLIENT_ID
// Run: firebase functions:secrets:get GMAIL_CLIENT_SECRET
const CLIENT_ID = process.env.GMAIL_CLIENT_ID || 'YOUR_CLIENT_ID';
const CLIENT_SECRET = process.env.GMAIL_CLIENT_SECRET || 'YOUR_CLIENT_SECRET';
const REDIRECT_URI = 'http://localhost:3000/callback';

if (CLIENT_ID === 'YOUR_CLIENT_ID' || CLIENT_SECRET === 'YOUR_CLIENT_SECRET') {
  console.error('❌ Please set GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET environment variables');
  console.log('   You can get these from Firebase: firebase functions:secrets:get GMAIL_CLIENT_ID');
  process.exit(1);
}

const SCOPES = [
  'https://www.googleapis.com/auth/gmail.readonly',
  'https://www.googleapis.com/auth/gmail.send',
  'https://www.googleapis.com/auth/gmail.modify',
];

// Initialize Firebase Admin
admin.initializeApp({
  projectId: 'aurora-viking-staff'
});
const db = admin.firestore();

async function addGmailAccount() {
  console.log('\n🔐 Aurora Viking - Add Gmail Account\n');
  console.log('This will open a browser to authorize a new Gmail account.');
  console.log('Make sure to sign in with the account you want to add (e.g., photo@auroraviking.com)\n');
  
  // Load open dynamically (ESM module)
  openBrowser = (await import('open')).default;
  
  const oauth2Client = new google.auth.OAuth2(CLIENT_ID, CLIENT_SECRET, REDIRECT_URI);
  
  // Generate auth URL
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    scope: SCOPES,
    prompt: 'consent',  // Force consent to get refresh token
  });
  
  return new Promise((resolve, reject) => {
    // Create local server to receive callback
    const server = http.createServer(async (req, res) => {
      try {
        const queryParams = url.parse(req.url, true).query;
        
        if (queryParams.code) {
          console.log('\n✅ Authorization code received!');
          
          // Exchange code for tokens
          const { tokens } = await oauth2Client.getToken(queryParams.code);
          oauth2Client.setCredentials(tokens);
          
          // Get email address
          const gmail = google.gmail({ version: 'v1', auth: oauth2Client });
          const profile = await gmail.users.getProfile({ userId: 'me' });
          const email = profile.data.emailAddress;
          
          console.log(`📧 Account: ${email}`);
          
          // Save to Firestore
          const emailId = email.replace(/[@.]/g, '_');
          await db.collection('system').doc('gmail_accounts').collection('accounts').doc(emailId).set({
            email,
            accessToken: tokens.access_token,
            refreshToken: tokens.refresh_token,
            expiryDate: tokens.expiry_date,
            lastCheckTimestamp: Date.now(),
            addedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          
          console.log(`\n✅ Account ${email} added successfully!`);
          console.log(`   Firestore path: system/gmail_accounts/accounts/${emailId}`);
          
          // Get all accounts to show
          const accountsSnapshot = await db.collection('system').doc('gmail_accounts').collection('accounts').get();
          console.log(`\n📫 Total connected accounts: ${accountsSnapshot.size}`);
          accountsSnapshot.forEach(doc => {
            console.log(`   - ${doc.data().email}`);
          });
          
          res.writeHead(200, { 'Content-Type': 'text/html' });
          res.end(`
            <html>
              <head><title>Account Added!</title></head>
              <body style="font-family: Arial; max-width: 600px; margin: 50px auto; text-align: center;">
                <h1>✅ Gmail Account Added!</h1>
                <p>Email: <strong>${email}</strong></p>
                <p>The inbox will start receiving emails from this account on the next poll (within 1 minute).</p>
                <p>You can close this window.</p>
              </body>
            </html>
          `);
          
          server.close();
          resolve();
        } else if (queryParams.error) {
          console.error('❌ Authorization error:', queryParams.error);
          res.writeHead(400, { 'Content-Type': 'text/html' });
          res.end(`<h1>Error: ${queryParams.error}</h1>`);
          server.close();
          reject(new Error(queryParams.error));
        }
      } catch (error) {
        console.error('❌ Error:', error.message);
        res.writeHead(500, { 'Content-Type': 'text/html' });
        res.end(`<h1>Error: ${error.message}</h1>`);
        server.close();
        reject(error);
      }
    });
    
    server.listen(3000, () => {
      console.log('🌐 Local server started at http://localhost:3000');
      console.log('\n📱 Opening browser for authorization...\n');
      openBrowser(authUrl);
    });
  });
}

addGmailAccount()
  .then(() => {
    console.log('\n🎉 Done! The new account will be polled within 1 minute.');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Failed:', error.message);
    process.exit(1);
  });

