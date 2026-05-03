/**
 * Firebase Cloud Functions for Smart Helmet SMS Emergency Alerts
 * 
 * This module provides a secure backend for sending SMS messages
 * via Twilio API. Handles emergency alerts from the Smart Helmet app.
 * 
 * Required Environment Variables (set in .env file):
 * - TWILIO_ACCOUNT_SID: Your Twilio Account SID
 * - TWILIO_AUTH_TOKEN: Your Twilio Auth Token  
 * - TWILIO_PHONE_NUMBER: Your Twilio Phone Number (e.g., +18152485891)
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const twilio = require('twilio');

// Initialize Firebase Admin
admin.initializeApp();

// Initialize Firestore
const db = admin.firestore();

/**
 * Send SMS message via Twilio
 * HTTP Callable Function
 * 
 * Request body: { to: string, message: string }
 * Response: { success: boolean, messageSid?: string, error?: string }
 */
exports.sendSMS = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const { to, message } = req.body;

    // Validate input
    if (!to || !message) {
      res.status(400).json({ 
        success: false, 
        error: 'Missing required fields: to, message' 
      });
      return;
    }

    // Get Twilio credentials from environment variables
    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const fromNumber = process.env.TWILIO_PHONE_NUMBER;

    if (!accountSid || !authToken) {
      console.error('Twilio credentials not configured');
      res.status(500).json({ 
        success: false, 
        error: 'Server configuration error: Twilio not configured' 
      });
      return;
    }

    // Initialize Twilio client
    const client = twilio(accountSid, authToken);

    // Format phone number (E.164 format required)
    const toFormatted = to.startsWith('+') ? to : `+${to.replace(/\D/g, '')}`;
    const fromFormatted = fromNumber.startsWith('+') ? fromNumber : `+${fromNumber.replace(/\D/g, '')}`;

    console.log(`Sending SMS to: ${toFormatted} from: ${fromFormatted}`);

    // Send SMS via Twilio
    const twilioMessage = await client.messages.create({
      body: message,
      from: fromFormatted,
      to: toFormatted,
    });

    console.log(`Message sent successfully. SID: ${twilioMessage.sid}`);

    // Log emergency alert to Firestore
    await db.collection('emergency_alerts').add({
      type: 'SMS_SOS',
      recipient: to,
      messageSid: twilioMessage.sid,
      status: twilioMessage.status,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      delivered: twilioMessage.status === 'delivered' || twilioMessage.status === 'sent',
    });

    res.status(200).json({
      success: true,
      messageSid: twilioMessage.sid,
      status: twilioMessage.status,
    });

  } catch (error) {
    console.error('Error sending SMS:', error);
    
    // Log failed attempt
    try {
      await db.collection('emergency_alerts').add({
        type: 'SMS_SOS_FAILED',
        recipient: req.body?.to || 'unknown',
        error: error.message,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        delivered: false,
      });
    } catch (logError) {
      console.error('Failed to log error:', logError);
    }

    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * Send SMS to multiple contacts
 * HTTP Callable Function
 * 
 * Request body: { 
 *   contacts: string[], 
 *   message: string,
 *   riderName?: string,
 *   location?: { lat: number, lng: number }
 * }
 */
exports.sendBulkSMS = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const { contacts, message, riderName, location } = req.body;

    if (!contacts || !Array.isArray(contacts) || contacts.length === 0 || !message) {
      res.status(400).json({ 
        success: false, 
        error: 'Missing required fields: contacts (array), message' 
      });
      return;
    }

    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const fromNumber = process.env.TWILIO_PHONE_NUMBER;

    if (!accountSid || !authToken) {
      res.status(500).json({ 
        success: false, 
        error: 'Server configuration error' 
      });
      return;
    }

    const client = twilio(accountSid, authToken);
    const fromFormatted = fromNumber.startsWith('+') ? fromNumber : `+${fromNumber.replace(/\D/g, '')}`;

    const results = [];

    // Send to all contacts
    for (const contact of contacts) {
      try {
        const toFormatted = contact.startsWith('+') ? contact : `+${contact.replace(/\D/g, '')}`;
        
        const twilioMessage = await client.messages.create({
          body: message,
          from: fromFormatted,
          to: toFormatted,
        });

        results.push({
          contact: contact,
          success: true,
          messageSid: twilioMessage.sid,
          status: twilioMessage.status,
        });

        console.log(`Sent to ${contact}: ${twilioMessage.sid}`);

      } catch (contactError) {
        results.push({
          contact: contact,
          success: false,
          error: contactError.message,
        });

        console.error(`Failed to send to ${contact}:`, contactError.message);
      }
    }

    // Log bulk alert
    await db.collection('emergency_alerts').add({
      type: 'SMS_BULK_SOS',
      recipients: contacts,
      riderName: riderName || 'Unknown',
      location: location || null,
      results: results,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      allSuccessful: results.every(r => r.success),
    });

    const allSuccessful = results.every(r => r.success);

    res.status(200).json({
      success: allSuccessful,
      results: results,
      totalSent: results.filter(r => r.success).length,
      totalFailed: results.filter(r => !r.success).length,
    });

  } catch (error) {
    console.error('Bulk send error:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * Test function to verify Twilio configuration
 * HTTP Callable Function
 */
exports.testTwilioConfig = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_PHONE_NUMBER;

  res.status(200).json({
    configured: !!(accountSid && authToken && fromNumber),
    hasAccountSid: !!accountSid,
    hasAuthToken: !!authToken,
    hasFromNumber: !!fromNumber,
    phoneNumber: fromNumber ? `${fromNumber.substring(0, 8)}...` : null,
  });
});
