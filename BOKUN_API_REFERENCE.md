# Bokun API Reference - Aurora Viking Staff App

This document explains which Bokun API endpoints work and how to use them correctly.
Based on hard-won trial and error! 📚

## Authentication

**All API calls use HMAC-SHA1 authentication:**
```javascript
const message = bokunDate + accessKey + method + path;
const signature = crypto.createHmac('sha1', secretKey).update(message).digest('base64');

// Headers:
{
  'Content-Type': 'application/json;charset=UTF-8',
  'X-Bokun-AccessKey': accessKey,
  'X-Bokun-Date': bokunDate,  // Format: '2024-01-14 14:30:00'
  'X-Bokun-Signature': signature,
}
```

---

## ✅ Working Endpoints

### 1. Get Pickup Places for a Product
**Endpoint:** `GET /activity.json/{productId}/pickup-places`

Returns array of available pickup locations for a product.

**Response:**
```json
[
  { "id": 10247, "title": "Canopy by Hilton Reykjavik", "address": {...} },
  { "id": 10245, "title": "CenterHotel Miðgarður", "address": {...} }
]
```

---

### 2. Update Pickup Location on Existing Booking
**Endpoint:** `POST /booking.json/edit`

#### ⚠️ CRITICAL: Request Body Format
The body must be an **ARRAY of actions directly** - NOT wrapped in `{ actions: [...] }`

✅ **Correct:**
```json
[{
  "type": "ActivityPickupAction",
  "activityBookingId": 123456789,
  "pickup": true,
  "pickupPlaceId": 10247,
  "description": "Canopy by Hilton"
}]
```

❌ **Wrong (will fail with validation error):**
```json
{
  "actions": [{
    "type": "ActivityPickupAction",
    ...
  }]
}
```

#### Key Fields:
| Field | Description |
|-------|-------------|
| `type` | Must be `ActivityPickupAction` |
| `activityBookingId` | The `productBooking.id` (NOT parent booking ID!) |
| `pickup` | Boolean, set to `true` |
| `pickupPlaceId` | ID from `/pickup-places` endpoint |
| `description` | Optional pickup place name/description |

---

### 3. Search Bookings
**Endpoint:** `POST /booking.json/booking-search`

**Request Body:**
```json
{
  "bookingId": 82240027
}
```

**Response structure:**
```json
{
  "items": [{
    "id": 82240027,        // Parent booking ID
    "confirmationCode": "AVT-123456",
    "productBookings": [{
      "id": 123456789,     // THIS is the activityBookingId you need!
      "product": { "id": 728888 },
      "startDate": "2024-02-15",
      "fields": {
        "pickup": true,
        "pickupPlaceId": 10247,
        "pickupPlace": { "title": "Canopy by Hilton" }
      }
    }]
  }]
}
```

---

## ❌ Action Types That DON'T Work

These were tried and failed with validation errors:

| Action Type | Error |
|-------------|-------|
| `SET_PICKUP` | "Invalid property" |
| `EDIT_PRODUCT_BOOKING` | "Invalid property" |
| `EditBookingPickupAction` | "Invalid property" |

Only `ActivityPickupAction` works!

---

## 🚫 GraphQL API - NOT for Internal Apps

The Bokun GraphQL API requires:
- OAuth 2.0 authentication
- Partner account registration
- App Store app approval

**Don't use it** for internal staff apps. REST API with HMAC-SHA1 is correct.

---

## Important: Booking ID vs Activity Booking ID

```
Booking Search Response:
{
  "items": [{
    "id": 82240027,           ← PARENT Booking ID (used for search)
    "productBookings": [{
      "id": 123456789,        ← ACTIVITY Booking ID (use for edit actions!)
      ...
    }]
  }]
}
```

**When calling `/booking.json/edit`:**
- Use `productBookings[0].id` as `activityBookingId`
- NOT the parent booking `id`

---

## Cloud Function Secrets

Required in Firebase:
- `BOKUN_ACCESS_KEY`
- `BOKUN_SECRET_KEY`
- `BOKUN_OCTO_TOKEN` (for OCTO API operations)

---

## Related Files

- `functions/index.js` - Cloud Functions (getPickupPlaces, updatePickupLocation)
- `lib/modules/admin/booking_service.dart` - Flutter service methods
- `lib/modules/admin/booking_detail_screen.dart` - UI dialogs

---

*Last updated: 2024-01-14 after successfully implementing Change Pickup Location feature*
