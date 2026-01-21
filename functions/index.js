/**
 * Aurora Viking Cloud Functions - MODULAR ENTRY POINT
 * 
 * This file imports and re-exports all functions from their modules.
 * Each domain has its own file for easier maintenance.
 * 
 * Module Structure:
 * - config.js               - Shared constants
 * - utils/firebase.js       - Firebase admin init
 * - utils/google_auth.js    - Google Auth & Sheets helpers
 * - utils/bokun_client.js   - Bokun API client
 * - utils/notifications.js  - Push notification helpers
 * - modules/reports.js      - Report generation & triggers
 * - modules/bokun_proxy.js  - Bokun API proxy
 * - modules/booking_management.js - Reschedule, cancel, pickup
 * - modules/inbox_core.js   - Unified inbox core
 * - modules/gmail.js        - Gmail integration
 * - modules/website_chat.js - Website chat widget
 * - modules/ai_assist.js    - AI draft & booking assist
 */

// ============================================
// REPORTS MODULE
// ============================================
const reports = require('./modules/reports');
exports.onEndOfShiftSubmitted = reports.onEndOfShiftSubmitted;
exports.onPickupAssignmentsChanged = reports.onPickupAssignmentsChanged;
exports.onBusAssignmentChanged = reports.onBusAssignmentChanged;
exports.generateTourReport = reports.generateTourReport;
exports.generateTourReportManual = reports.generateTourReportManual;

// ============================================
// BOKUN PROXY MODULE
// ============================================
const bokunProxy = require('./modules/bokun_proxy');
exports.getBookings = bokunProxy.getBookings;

// ============================================
// BOOKING MANAGEMENT MODULE
// ============================================
const bookingMgmt = require('./modules/booking_management');
exports.getBookingDetails = bookingMgmt.getBookingDetails;
exports.rescheduleBooking = bookingMgmt.rescheduleBooking;
exports.onRescheduleRequest = bookingMgmt.onRescheduleRequest;
exports.checkRescheduleAvailability = bookingMgmt.checkRescheduleAvailability;
exports.getPickupPlaces = bookingMgmt.getPickupPlaces;
exports.updatePickupLocation = bookingMgmt.updatePickupLocation;
exports.cancelBooking = bookingMgmt.cancelBooking;

// ============================================
// INBOX CORE MODULE
// ============================================
const inboxCore = require('./modules/inbox_core');
exports.processGmailMessage = inboxCore.processGmailMessage;
exports.sendInboxMessage = inboxCore.sendInboxMessage;
exports.markConversationRead = inboxCore.markConversationRead;
exports.updateConversationStatus = inboxCore.updateConversationStatus;
exports.createTestInboxMessage = inboxCore.createTestInboxMessage;

// ============================================
// GMAIL MODULE
// ============================================
const gmail = require('./modules/gmail');
exports.gmailOAuthStart = gmail.gmailOAuthStart;
exports.gmailOAuthCallback = gmail.gmailOAuthCallback;
exports.pollGmailInbox = gmail.pollGmailInbox;
exports.sendGmailReply = gmail.sendGmailReply;
exports.triggerGmailPoll = gmail.triggerGmailPoll;
exports.gmailStatus = gmail.gmailStatus;
exports.onOutboundMessageCreated = gmail.onOutboundMessageCreated;
exports.migrateGmailToMultiAccount = gmail.migrateGmailToMultiAccount;

// ============================================
// WEBSITE CHAT MODULE
// ============================================
const websiteChat = require('./modules/website_chat');
exports.createWebsiteSession = websiteChat.createWebsiteSession;
exports.updateWebsiteSession = websiteChat.updateWebsiteSession;
exports.sendWebsiteMessage = websiteChat.sendWebsiteMessage;
exports.updateWebsitePresence = websiteChat.updateWebsitePresence;
exports.sendWebsiteChatReply = websiteChat.sendWebsiteChatReply;
exports.onWebsiteChatMessage = websiteChat.onWebsiteChatMessage;

// ============================================
// AI ASSIST MODULE
// ============================================
const aiAssist = require('./modules/ai_assist');
exports.generateAiDraft = aiAssist.generateAiDraft;
exports.generateBookingAiAssist = aiAssist.generateBookingAiAssist;

// ============================================
// AURORA ADVISOR (already separate)
// ============================================
const auroraAdvisor = require('./aurora_advisor');
const auroraLearning = require('./aurora_learning_pipeline');

exports.getAuroraAdvisorRecommendation = auroraAdvisor.getAuroraAdvisorRecommendation;
exports.getQuickAuroraAssessment = auroraAdvisor.getQuickAuroraAssessment;
exports.runLearningPipeline = auroraLearning.runLearningPipeline;
exports.triggerLearningPipeline = auroraLearning.triggerLearningPipeline;
exports.createSightingFromShiftReport = auroraLearning.createSightingFromShiftReport;
exports.getLearningsContext = auroraLearning.getLearningsContext;
