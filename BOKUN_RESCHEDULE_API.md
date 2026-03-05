# Bokun Internal API Reference: ActivityChangeDateAction

## Overview

This is Bokun's **internal booking edit API** that can reschedule **any booking** — including OTA bookings from GetYourGuide, Viator, TripAdvisor, etc. This is the same API Bokun uses in their own admin UI when you drag-and-drop bookings between dates.

> **This works for ALL booking types** — direct, OTA, backend, manual.

## Endpoint

```
POST https://api.bokun.io/booking.json/edit
```

## Authentication

Uses the standard Bokun HMAC-SHA1 signing:

```javascript
const crypto = require('crypto');
const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
const editPath = '/booking.json/edit';
const editMessage = editDate + accessKey + 'POST' + editPath;
const editSignature = crypto.createHmac('sha1', secretKey).update(editMessage).digest('base64');
```

**Headers:**
```
Content-Type: application/json;charset=UTF-8
X-Bokun-AccessKey: <your access key>
X-Bokun-Date: <editDate>
X-Bokun-Signature: <editSignature>
```

## Request Body

The body is a **JSON array** of edit actions. For rescheduling:

```json
[{
    "type": "ActivityChangeDateAction",
    "activityBookingId": 12345678,
    "date": "2026-03-15",
    "startTimeId": 67890
}]
```

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | string | Yes | Must be `"ActivityChangeDateAction"` |
| `activityBookingId` | integer | Yes | The `productBookings[0].id` from the booking object (NOT the booking ID) |
| `date` | string | Yes | New date in `YYYY-MM-DD` format |
| `startTimeId` | integer | No | The time slot ID. Include if the booking has one (from `productBookings[0].startTimeId`) |

## Where to Find the activityBookingId

When you fetch a booking via `GET /booking.json/{bookingId}`, the response contains:

```json
{
    "id": 80518744,           // <-- This is the BOOKING ID (not what we need)
    "productBookings": [{
        "id": 90123456,       // <-- This is the ACTIVITY BOOKING ID ✅
        "startTimeId": 67890, // <-- Include this if present
        "startDate": {...}
    }]
}
```

## Full Example (Node.js)

```javascript
const https = require('https');
const crypto = require('crypto');

async function rescheduleBooking(activityBookingId, newDate, startTimeId, accessKey, secretKey) {
    const editPath = '/booking.json/edit';
    const editDate = new Date().toISOString().replace('T', ' ').substring(0, 19);
    const editMessage = editDate + accessKey + 'POST' + editPath;
    const editSignature = crypto.createHmac('sha1', secretKey).update(editMessage).digest('base64');

    const changeDateActions = [{
        type: 'ActivityChangeDateAction',
        activityBookingId: parseInt(activityBookingId),
        date: newDate,
        ...(startTimeId && { startTimeId: parseInt(startTimeId) }),
    }];

    return new Promise((resolve, reject) => {
        const body = JSON.stringify(changeDateActions);
        const req = https.request({
            hostname: 'api.bokun.io',
            path: editPath,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json;charset=UTF-8',
                'Content-Length': Buffer.byteLength(body),
                'X-Bokun-AccessKey': accessKey,
                'X-Bokun-Date': editDate,
                'X-Bokun-Signature': editSignature,
            },
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 400) {
                    resolve({ success: true, data });
                } else {
                    reject(new Error(`Failed: ${res.statusCode} - ${data}`));
                }
            });
        });
        req.on('error', reject);
        req.write(body);
        req.end();
    });
}
```

## Where It's Used

| File | Function | Context |
|---|---|---|
| `functions/modules/booking_portal.js` | `portalRescheduleBooking` | Customer self-service portal (line ~690) |
| `functions/modules/booking_management.js` | `onRescheduleRequest` | Admin reschedule trigger (line ~530) |

## Important Notes

- **Response codes**: `200-399` = success, anything else = failure
- **OTA bookings**: Works for Viator, GetYourGuide, TripAdvisor — all OTA channels
- **No availability check**: This API does NOT check availability. The booking will be moved even if the new date is "full"
- **Secrets needed**: `BOKUN_ACCESS_KEY` and `BOKUN_SECRET_KEY`
- **Rate limits**: Unknown, but we add 500ms delays between batch operations to be safe
