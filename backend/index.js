const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const crypto = require('crypto');
const db = require('./db');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// ─── Middleware ──────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Helper for sending standard API error responses
const sendError = (res, statusCode, message, error = null) => {
  console.error(`[API Error] Status ${statusCode}: ${message}`, error || '');
  return res.status(statusCode).json({
    success: false,
    message,
    error: error ? error.message : undefined,
  });
};

// ─── Aadhaar Helpers ─────────────────────────────────────────────────────────

function hashAadhaar(aadhaarNumber) {
  return crypto.createHash('sha256').update(aadhaarNumber.trim()).digest('hex');
}

// Verhoeff algorithm tables
const verhoeffD = [
  [0,1,2,3,4,5,6,7,8,9],[1,2,3,4,0,6,7,8,9,5],[2,3,4,0,1,7,8,9,5,6],
  [3,4,0,1,2,8,9,5,6,7],[4,0,1,2,3,9,5,6,7,8],[5,9,8,7,6,0,4,3,2,1],
  [6,5,9,8,7,1,0,4,3,2],[7,6,5,9,8,2,1,0,4,3],[8,7,6,5,9,3,2,1,0,4],
  [9,8,7,6,5,4,3,2,1,0],
];
const verhoeffP = [
  [0,1,2,3,4,5,6,7,8,9],[1,5,7,6,2,8,3,0,9,4],[5,8,0,3,7,9,6,1,4,2],
  [8,9,1,6,0,4,3,5,2,7],[9,4,5,3,1,2,6,8,7,0],[4,2,8,6,5,7,3,9,0,1],
  [2,7,9,3,8,0,6,4,1,5],[7,0,4,6,9,1,3,2,5,8],
];

function isValidAadhaar(aadhaarNumber) {
  const num = aadhaarNumber.replace(/\s/g, '');
  if (!/^\d{12}$/.test(num)) return false;
  if (num[0] === '0' || num[0] === '1') return false;
  let c = 0;
  const digits = num.split('').map(Number).reverse();
  for (let i = 0; i < digits.length; i++) {
    c = verhoeffD[c][verhoeffP[i % 8][digits[i]]];
  }
  return c === 0;
}

// ─── User Endpoints ──────────────────────────────────────────────────────────

app.get('/api/users/phone/:phone', async (req, res) => {
  const { phone } = req.params;

  try {
    const result = await db.query(`
      SELECT 
        u.id, u.full_name, u.phone_number, u.user_type, u.village_area, 
        u.address, u.latitude, u.longitude, u.location_updated_at, u.aadhaar_hash,
        sp.id AS provider_id, sp.service_name, sp.is_online,
        (SELECT STUFF((
           SELECT ',' + CAST(pc.category_id AS VARCHAR)
           FROM provider_categories pc WHERE pc.provider_id = sp.id
           FOR XML PATH('')
         ), 1, 1, '')
        ) AS category_ids_str
      FROM users u
      LEFT JOIN service_providers sp ON sp.user_id = u.id
      WHERE u.phone_number = @phone;
    `, { phone });

    if (result.recordset.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const user = result.recordset[0];
    user.category_ids = user.category_ids_str
      ? user.category_ids_str.split(',').map(Number) : [];
    delete user.category_ids_str;
    if (user.is_online !== null && user.is_online !== undefined)
      user.is_online = !!user.is_online;

    return res.status(200).json(user);
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch user by phone number', err);
  }
});

app.post('/api/users/register', async (req, res) => {
  const {
    full_name, phone_number, aadhaar_number, user_type,
    village_area, address, latitude, longitude,
    service_name, category_ids,
  } = req.body;

  if (!full_name || !phone_number || !user_type) {
    return sendError(res, 400, 'Missing required fields: full_name, phone_number, and user_type are mandatory.');
  }
  if (!aadhaar_number) {
    return sendError(res, 400, 'Aadhaar card number is mandatory.');
  }

  const cleanAadhaar = aadhaar_number.replace(/\s/g, '');
  if (!/^\d{12}$/.test(cleanAadhaar)) {
    return sendError(res, 400, 'Aadhaar number must be exactly 12 digits.');
  }
  if (!isValidAadhaar(cleanAadhaar)) {
    return sendError(res, 400, 'Invalid Aadhaar number. Please enter a valid Aadhaar card number.');
  }

  const aadhaarHash = hashAadhaar(cleanAadhaar);

  try {
    const existingAadhaar = await db.query(
      'SELECT id FROM users WHERE aadhaar_hash = @hash;', { hash: aadhaarHash }
    );
    if (existingAadhaar.recordset.length > 0) {
      return sendError(res, 409, 'This Aadhaar card number is already registered. Duplicate Aadhaar entries are not allowed.');
    }
  } catch (err) {
    return sendError(res, 500, 'Failed to verify Aadhaar uniqueness.', err);
  }

  const pool = await db.getPool();
  const transaction = pool.transaction();

  try {
    await transaction.begin();

    const userRequest = transaction.request();
    userRequest.input('full_name', full_name);
    userRequest.input('phone_number', phone_number);
    userRequest.input('aadhaar_hash', aadhaarHash);
    userRequest.input('user_type', user_type);
    userRequest.input('village_area', village_area || null);
    userRequest.input('address', address || null);
    userRequest.input('latitude', latitude || null);
    userRequest.input('longitude', longitude || null);

    const userResult = await userRequest.query(`
      INSERT INTO users (full_name, phone_number, aadhaar_hash, user_type, village_area, address, latitude, longitude, location_updated_at)
      OUTPUT INSERTED.id
      VALUES (@full_name, @phone_number, @aadhaar_hash, @user_type, @village_area, @address, @latitude, @longitude, SYSDATETIMEOFFSET());
    `);
    const userId = userResult.recordset[0].id;

    if (user_type === 'service_provider') {
      if (!service_name) throw new Error('service_name is mandatory for service providers');

      const spRequest = transaction.request();
      spRequest.input('user_id', userId);
      spRequest.input('service_name', service_name);
      const spResult = await spRequest.query(`
        INSERT INTO service_providers (user_id, service_name, is_online)
        OUTPUT INSERTED.id
        VALUES (@user_id, @service_name, 0);
      `);
      const providerId = spResult.recordset[0].id;

      if (category_ids && Array.isArray(category_ids) && category_ids.length > 0) {
        for (const catId of category_ids) {
          const pcRequest = transaction.request();
          pcRequest.input('provider_id', providerId);
          pcRequest.input('category_id', catId);
          await pcRequest.query(`
            INSERT INTO provider_categories (provider_id, category_id)
            VALUES (@provider_id, @category_id);
          `);
        }
      }
    }

    await transaction.commit();

    const fetchResult = await db.query(`
      SELECT 
        u.id, u.full_name, u.phone_number, u.user_type, u.village_area, 
        u.address, u.latitude, u.longitude, u.location_updated_at, u.aadhaar_hash,
        sp.id AS provider_id, sp.service_name, sp.is_online,
        (SELECT STUFF((
           SELECT ',' + CAST(pc.category_id AS VARCHAR)
           FROM provider_categories pc WHERE pc.provider_id = sp.id
           FOR XML PATH('')
         ), 1, 1, '')
        ) AS category_ids_str
      FROM users u
      LEFT JOIN service_providers sp ON sp.user_id = u.id
      WHERE u.id = @userId;
    `, { userId });

    const registeredUser = fetchResult.recordset[0];
    registeredUser.category_ids = registeredUser.category_ids_str
      ? registeredUser.category_ids_str.split(',').map(Number) : [];
    delete registeredUser.category_ids_str;
    if (registeredUser.is_online !== null && registeredUser.is_online !== undefined)
      registeredUser.is_online = !!registeredUser.is_online;

    return res.status(201).json(registeredUser);
  } catch (err) {
    try { await transaction.rollback(); } catch (_) {}
    return sendError(res, 500, 'Registration failed. Transaction rolled back.', err);
  }
});

app.post('/api/validate/aadhaar', async (req, res) => {
  const { aadhaar_number } = req.body;
  if (!aadhaar_number) return res.status(400).json({ valid: false, message: 'Aadhaar number is required.' });

  const clean = aadhaar_number.replace(/\s/g, '');
  if (!/^\d{12}$/.test(clean)) return res.status(400).json({ valid: false, message: 'Aadhaar must be exactly 12 digits.' });
  if (!isValidAadhaar(clean)) return res.status(400).json({ valid: false, message: 'Invalid Aadhaar number (checksum failed).' });

  try {
    const hash = hashAadhaar(clean);
    const existing = await db.query('SELECT id FROM users WHERE aadhaar_hash = @hash;', { hash });
    if (existing.recordset.length > 0) return res.status(409).json({ valid: false, message: 'This Aadhaar is already registered.' });
    return res.status(200).json({ valid: true, message: 'Aadhaar number is valid and available.' });
  } catch (err) {
    return sendError(res, 500, 'Failed to validate Aadhaar.', err);
  }
});

// ─── Location Endpoints ──────────────────────────────────────────────────────

app.put('/api/users/:userId/location', async (req, res) => {
  const { userId } = req.params;
  const { latitude, longitude } = req.body;

  if (latitude === undefined || longitude === undefined) {
    return sendError(res, 400, 'Missing required fields: latitude and longitude are mandatory.');
  }

  try {
    const result = await db.query(`
      UPDATE users SET latitude = @latitude, longitude = @longitude, location_updated_at = SYSDATETIMEOFFSET() WHERE id = @userId;
      SELECT id, full_name, latitude, longitude, location_updated_at FROM users WHERE id = @userId;
    `, { latitude, longitude, userId });

    const rows = result.recordset;
    if (rows.length === 0) return res.status(404).json({ success: false, message: 'User not found' });
    return res.status(200).json(rows[0]);
  } catch (err) {
    return sendError(res, 500, 'Failed to update location coordinates', err);
  }
});

// ─── Service Provider Endpoints ──────────────────────────────────────────────

app.put('/api/providers/:userId/status', async (req, res) => {
  const { userId } = req.params;
  const { is_online } = req.body;

  if (is_online === undefined) {
    return sendError(res, 400, 'Missing required field: is_online is mandatory.');
  }

  try {
    const onlineBit = is_online ? 1 : 0;
    const result = await db.query(`
      UPDATE service_providers SET is_online = @is_online WHERE user_id = @userId;
      SELECT id, user_id, service_name, is_online, updated_at FROM service_providers WHERE user_id = @userId;
    `, { is_online: onlineBit, userId });

    const rows = result.recordset;
    if (rows.length === 0) return res.status(404).json({ success: false, message: 'Service provider not found for this user ID' });
    const row = rows[0];
    row.is_online = !!row.is_online;
    return res.status(200).json(row);
  } catch (err) {
    return sendError(res, 500, 'Failed to toggle service provider online status', err);
  }
});

app.get('/api/providers/nearby', async (req, res) => {
  const { lat, lng, radius, category } = req.query;
  if (!lat || !lng) return sendError(res, 400, 'Missing query parameters: lat and lng are mandatory.');

  const originLat = parseFloat(lat);
  const originLng = parseFloat(lng);
  const radiusKm = radius ? parseFloat(radius) : 25.0;

  try {
    let queryStr = `
      SELECT * FROM (
        SELECT user_id, full_name, phone_number, village_area, address,
          latitude, longitude, location_updated_at, provider_id, service_name, is_online, categories,
          (6371 * ACOS(
            COS(RADIANS(@originLat)) * COS(RADIANS(latitude)) * 
            COS(RADIANS(longitude) - RADIANS(@originLng)) + 
            SIN(RADIANS(@originLat)) * SIN(RADIANS(latitude))
          )) AS distance
        FROM v_online_providers
        WHERE latitude IS NOT NULL AND longitude IS NOT NULL
      ) AS nearby_providers
      WHERE distance <= @radiusKm
    `;
    const params = { originLat, originLng, radiusKm };

    if (category) {
      queryStr += ` AND ',' + categories + ',' LIKE '%,' + @category + ',%'`;
      params.category = category;
    }
    queryStr += ` ORDER BY distance ASC;`;

    const result = await db.query(queryStr, params);
    const providers = result.recordset.map(row => {
      row.is_online = !!row.is_online;
      row.categories = row.categories ? row.categories.split(',') : [];
      return row;
    });

    return res.status(200).json({ success: true, providers });
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch nearby service providers', err);
  }
});

// ─── Service Request Endpoints ───────────────────────────────────────────────

app.get('/api/providers/:providerId/requests/today', async (req, res) => {
  const { providerId } = req.params;
  try {
    const result = await db.query(`
      SELECT COUNT(*) AS count FROM service_requests 
      WHERE provider_id = @providerId AND CAST(created_at AS DATE) = CAST(GETUTCDATE() AS DATE);
    `, { providerId });
    return res.status(200).json({ success: true, count: result.recordset[0].count });
  } catch (err) {
    return sendError(res, 500, "Failed to retrieve today's request count", err);
  }
});

app.get('/api/providers/:providerId/requests/today/list', async (req, res) => {
  const { providerId } = req.params;
  try {
    const result = await db.query(`
      SELECT sr.id, sr.farmer_id, sr.category_id, sr.status, sr.message, 
        sr.farmer_latitude, sr.farmer_longitude, sr.created_at,
        u.full_name AS farmer_name, u.phone_number AS farmer_phone,
        p.payment_status, p.amount AS payment_amount, p.transaction_id
      FROM service_requests sr
      JOIN users u ON sr.farmer_id = u.id
      LEFT JOIN payments p ON p.request_id = sr.id
      WHERE sr.provider_id = @providerId AND CAST(sr.created_at AS DATE) = CAST(GETUTCDATE() AS DATE)
      ORDER BY sr.created_at DESC;
    `, { providerId });
    return res.status(200).json({ success: true, requests: result.recordset });
  } catch (err) {
    return sendError(res, 500, "Failed to retrieve today's request list", err);
  }
});

app.post('/api/requests', async (req, res) => {
  const { farmer_id, provider_id, category_id, message, farmer_latitude, farmer_longitude } = req.body;
  if (!farmer_id || !provider_id) {
    return sendError(res, 400, 'Missing required fields: farmer_id and provider_id are mandatory.');
  }
  try {
    const farmerRes = await db.query('SELECT full_name FROM users WHERE id = @farmer_id;', { farmer_id });
    const farmerName = farmerRes.recordset.length > 0 ? farmerRes.recordset[0].full_name : 'A Farmer';

    const result = await db.query(`
      INSERT INTO service_requests (farmer_id, provider_id, category_id, message, farmer_latitude, farmer_longitude, status)
      OUTPUT INSERTED.*
      VALUES (@farmer_id, @provider_id, @category_id, @message, @farmer_latitude, @farmer_longitude, 'pending');
    `, {
      farmer_id, provider_id,
      category_id: category_id || null, message: message || null,
      farmer_latitude: farmer_latitude || null, farmer_longitude: farmer_longitude || null,
    });

    const createdRequest = result.recordset[0];

    // Trigger Notification for Provider
    await db.query(`
      INSERT INTO notifications (user_id, title, message)
      VALUES (@provider_id, @notifTitle, @notifMessage);
    `, {
      provider_id,
      notifTitle: 'New Service Request',
      notifMessage: `${farmerName} has sent you a new service request.`
    });

    return res.status(201).json(createdRequest);
  } catch (err) {
    return sendError(res, 500, 'Failed to create service request', err);
  }
});

app.put('/api/requests/:id/status', async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  if (!status) {
    return sendError(res, 400, 'Missing required parameter: status.');
  }
  const allowedStatuses = ['pending', 'accepted', 'rejected', 'completed', 'cancelled'];
  if (!allowedStatuses.includes(status)) {
    return sendError(res, 400, `Invalid status: must be one of ${allowedStatuses.join(', ')}`);
  }
  try {
    const result = await db.query(`
      UPDATE service_requests
      SET status = @status, updated_at = SYSDATETIMEOFFSET()
      OUTPUT INSERTED.*
      WHERE id = @id;
    `, { id, status });
    if (result.rowsAffected[0] === 0) {
      return sendError(res, 404, 'Service request not found.');
    }
    const updatedRequest = result.recordset[0];
    const farmerId = updatedRequest.farmer_id;
    const providerId = updatedRequest.provider_id;

    const providerRes = await db.query('SELECT full_name FROM users WHERE id = @providerId;', { providerId });
    const providerName = providerRes.recordset.length > 0 ? providerRes.recordset[0].full_name : 'Provider';

    let notifTitle = 'Request Update';
    let notifMessage = `Your request status was updated to ${status}.`;
    if (status === 'accepted') {
      notifTitle = 'Request Accepted';
      notifMessage = `${providerName} has accepted your service request.`;
    } else if (status === 'rejected') {
      notifTitle = 'Request Rejected';
      notifMessage = `${providerName} has rejected your service request.`;
    } else if (status === 'completed') {
      notifTitle = 'Service Completed';
      notifMessage = `${providerName} has completed your service request.`;
    }

    // Trigger Notification for Farmer
    await db.query(`
      INSERT INTO notifications (user_id, title, message)
      VALUES (@farmerId, @notifTitle, @notifMessage);
    `, { farmerId, notifTitle, notifMessage });

    return res.status(200).json({ success: true, request: updatedRequest });
  } catch (err) {
    return sendError(res, 500, 'Failed to update service request status', err);
  }
});

app.get('/api/farmers/:farmerId/requests', async (req, res) => {
  const { farmerId } = req.params;
  try {
    const result = await db.query(`
      SELECT sr.id, sr.farmer_id, sr.provider_id, sr.category_id, sr.status, sr.message,
        sr.farmer_latitude, sr.farmer_longitude, sr.created_at,
        u.full_name AS provider_name, u.phone_number AS provider_phone,
        sp.service_name,
        rev.rating AS review_rating, rev.review_text AS review_text,
        p.payment_status, p.amount AS payment_amount, p.transaction_id
      FROM service_requests sr
      JOIN users u ON sr.provider_id = u.id
      JOIN service_providers sp ON sp.user_id = u.id
      LEFT JOIN reviews rev ON rev.request_id = sr.id
      LEFT JOIN payments p ON p.request_id = sr.id
      WHERE sr.farmer_id = @farmerId
      ORDER BY sr.created_at DESC;
    `, { farmerId });
    return res.status(200).json({ success: true, requests: result.recordset });
  } catch (err) {
    return sendError(res, 500, 'Failed to retrieve farmer service requests', err);
  }
});

app.post('/api/reviews', async (req, res) => {
  const { request_id, farmer_id, provider_id, rating, review_text } = req.body;
  if (!request_id || !farmer_id || !provider_id || !rating) {
    return sendError(res, 400, 'Missing required fields: request_id, farmer_id, provider_id, and rating are mandatory.');
  }
  const ratingInt = parseInt(rating, 10);
  if (isNaN(ratingInt) || ratingInt < 1 || ratingInt > 5) {
    return sendError(res, 400, 'Invalid rating: must be an integer between 1 and 5.');
  }

  try {
    const reqCheck = await db.query('SELECT status FROM service_requests WHERE id = @request_id;', { request_id });
    if (reqCheck.recordset.length === 0) {
      return sendError(res, 404, 'Service request not found.');
    }
    if (reqCheck.recordset[0].status !== 'completed') {
      return sendError(res, 400, 'Cannot rate/review a request that is not yet completed.');
    }

    const result = await db.query(`
      INSERT INTO reviews (request_id, farmer_id, provider_id, rating, review_text)
      OUTPUT INSERTED.*
      VALUES (@request_id, @farmer_id, @provider_id, @ratingInt, @review_text);
    `, {
      request_id, farmer_id, provider_id, ratingInt, review_text: review_text || null
    });
    return res.status(201).json({ success: true, review: result.recordset[0] });
  } catch (err) {
    if (err.message.includes('UNIQUE') || err.message.includes('violates unique constraint')) {
      return sendError(res, 400, 'This service request has already been reviewed.');
    }
    return sendError(res, 500, 'Failed to submit review', err);
  }
});

// ─── Categories Endpoint ─────────────────────────────────────────────────────

app.get('/api/categories', async (req, res) => {
  try {
    const result = await db.query('SELECT id, name FROM service_categories ORDER BY id ASC;');
    return res.status(200).json({ success: true, categories: result.recordset });
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch service categories', err);
  }
});

// ─── Chat Messages Endpoints ──────────────────────────────────────────────────

app.get('/api/requests/:requestId/messages', async (req, res) => {
  const { requestId } = req.params;
  try {
    const result = await db.query(`
      SELECT cm.id, cm.request_id, cm.sender_id, cm.message_text, cm.created_at,
        u.full_name AS sender_name
      FROM chat_messages cm
      JOIN users u ON cm.sender_id = u.id
      WHERE cm.request_id = @requestId
      ORDER BY cm.created_at ASC;
    `, { requestId });
    return res.status(200).json({ success: true, messages: result.recordset });
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch chat messages', err);
  }
});

app.post('/api/requests/:requestId/messages', async (req, res) => {
  const { requestId } = req.params;
  const { sender_id, message_text } = req.body;
  if (!sender_id || !message_text) {
    return sendError(res, 400, 'Missing required fields: sender_id and message_text are mandatory.');
  }
  try {
    // Insert chat message
    const result = await db.query(`
      INSERT INTO chat_messages (request_id, sender_id, message_text)
      OUTPUT INSERTED.*
      VALUES (@requestId, @sender_id, @message_text);
    `, { requestId, sender_id, message_text });

    const message = result.recordset[0];

    // Find recipient and sender info
    const reqInfo = await db.query('SELECT farmer_id, provider_id FROM service_requests WHERE id = @requestId;', { requestId });
    if (reqInfo.recordset.length > 0) {
      const { farmer_id, provider_id } = reqInfo.recordset[0];
      const recipientId = sender_id === farmer_id ? provider_id : farmer_id;

      const senderRes = await db.query('SELECT full_name FROM users WHERE id = @sender_id;', { sender_id });
      const senderName = senderRes.recordset.length > 0 ? senderRes.recordset[0].full_name : 'Someone';

      // Insert notification
      await db.query(`
        INSERT INTO notifications (user_id, title, message)
        VALUES (@recipientId, @notifTitle, @notifMessage);
      `, {
        recipientId,
        notifTitle: 'New Chat Message',
        notifMessage: `${senderName}: ${message_text.length > 50 ? message_text.substring(0, 50) + '...' : message_text}`
      });
    }

    return res.status(201).json({ success: true, message });
  } catch (err) {
    return sendError(res, 500, 'Failed to send message', err);
  }
});

// ─── Payment Endpoints ────────────────────────────────────────────────────────

app.post('/api/requests/:requestId/pay', async (req, res) => {
  const { requestId } = req.params;
  const { amount } = req.body;
  if (amount === undefined) {
    return sendError(res, 400, 'Missing required fields: amount is mandatory.');
  }
  try {
    const txnId = 'TXN-' + crypto.randomBytes(4).toString('hex').toUpperCase();

    // Check if payment already exists
    const checkPayment = await db.query('SELECT id FROM payments WHERE request_id = @requestId;', { requestId });
    if (checkPayment.recordset.length > 0) {
      return sendError(res, 400, 'This request has already been paid.');
    }

    // Insert payment
    const paymentResult = await db.query(`
      INSERT INTO payments (request_id, amount, payment_status, transaction_id)
      OUTPUT INSERTED.*
      VALUES (@requestId, @amount, 'paid', @txnId);
    `, { requestId, amount, txnId });

    // Also transition status to completed automatically upon payment
    await db.query(`
      UPDATE service_requests SET status = 'completed', updated_at = SYSDATETIMEOFFSET() WHERE id = @requestId;
    `, { requestId });

    // Notify provider
    const reqInfo = await db.query('SELECT farmer_id, provider_id FROM service_requests WHERE id = @requestId;', { requestId });
    if (reqInfo.recordset.length > 0) {
      const { provider_id } = reqInfo.recordset[0];
      await db.query(`
        INSERT INTO notifications (user_id, title, message)
        VALUES (@provider_id, 'Payment Received', @notifMessage);
      `, {
        provider_id,
        notifMessage: `Farmer paid ₹${amount} for service request. Transaction: ${txnId}`
      });
    }

    return res.status(201).json({ success: true, payment: paymentResult.recordset[0] });
  } catch (err) {
    return sendError(res, 500, 'Failed to process payment checkout', err);
  }
});

// ─── Notifications Endpoints ──────────────────────────────────────────────────

app.get('/api/notifications/:userId', async (req, res) => {
  const { userId } = req.params;
  try {
    const result = await db.query(`
      SELECT id, user_id, title, message, is_read, created_at
      FROM notifications
      WHERE user_id = @userId
      ORDER BY created_at DESC;
    `, { userId });
    return res.status(200).json({ success: true, notifications: result.recordset });
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch notifications', err);
  }
});

app.put('/api/notifications/:userId/read', async (req, res) => {
  const { userId } = req.params;
  try {
    await db.query(`
      UPDATE notifications SET is_read = 1 WHERE user_id = @userId;
    `, { userId });
    return res.status(200).json({ success: true, message: 'All notifications marked as read' });
  } catch (err) {
    return sendError(res, 500, 'Failed to mark notifications as read', err);
  }
});

// ─── Equipment Listing Endpoints ──────────────────────────────────────────────

app.get('/api/equipment', async (req, res) => {
  const { provider_id } = req.query;
  try {
    let queryStr = `
      SELECT eq.*, sp.user_id, sc.name AS category_name
      FROM equipment eq
      JOIN service_providers sp ON eq.provider_id = sp.id
      JOIN service_categories sc ON eq.category_id = sc.id
    `;
    const params = {};
    if (provider_id) {
      queryStr += ` WHERE sp.id = @provider_id OR sp.user_id = @provider_id`;
      params.provider_id = provider_id;
    }
    queryStr += ` ORDER BY eq.created_at DESC;`;

    const result = await db.query(queryStr, params);
    return res.status(200).json({ success: true, equipment: result.recordset });
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch equipment listings', err);
  }
});

app.post('/api/equipment', async (req, res) => {
  const { provider_id, name, category_id, price_per_hour } = req.body;
  if (!provider_id || !name || !category_id || price_per_hour === undefined) {
    return sendError(res, 400, 'Missing required fields: provider_id, name, category_id, price_per_hour are mandatory.');
  }
  try {
    // Resolve service_providers.id from provider_id (which could be a user ID or service_provider.id)
    const spCheck = await db.query('SELECT id FROM service_providers WHERE id = @provider_id OR user_id = @provider_id;', { provider_id });
    if (spCheck.recordset.length === 0) {
      return sendError(res, 404, 'Service provider profile not found.');
    }
    const actualSpId = spCheck.recordset[0].id;

    const result = await db.query(`
      INSERT INTO equipment (provider_id, name, category_id, price_per_hour, availability_status)
      OUTPUT INSERTED.*
      VALUES (@actualSpId, @name, @category_id, @price_per_hour, 'available');
    `, {
      actualSpId,
      name,
      category_id: parseInt(category_id, 10),
      price_per_hour: parseFloat(price_per_hour)
    });

    return res.status(201).json({ success: true, equipment: result.recordset[0] });
  } catch (err) {
    return sendError(res, 500, 'Failed to add equipment listing', err);
  }
});

app.delete('/api/equipment/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const result = await db.query(`
      DELETE FROM equipment
      OUTPUT DELETED.*
      WHERE id = @id;
    `, { id });
    if (result.rowsAffected[0] === 0) {
      return sendError(res, 404, 'Equipment listing not found.');
    }
    return res.status(200).json({ success: true, message: 'Equipment listing removed successfully.', equipment: result.recordset[0] });
  } catch (err) {
    return sendError(res, 500, 'Failed to delete equipment listing', err);
  }
});

// ─── Root & System Status ────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', database: 'mssql', timestamp: new Date(), uptime: process.uptime() });
});

// ─── Start Server ────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`
  \x1b[32m╔════════════════════════════════════════════════════════════════╗\x1b[0m
  \x1b[32m║               NEONINE BACKEND RUNNING SUCCESSFULLY             ║\x1b[0m
  \x1b[32m╠════════════════════════════════════════════════════════════════╣\x1b[0m
  \x1b[32m║\x1b[0m  Local Server URL:   \x1b[36mhttp://localhost:${PORT}\x1b[0m                      \x1b[32m║\x1b[0m
  \x1b[32m║\x1b[0m  Health Check:       \x1b[36mhttp://localhost:${PORT}/health\x1b[0m               \x1b[32m║\x1b[0m
  \x1b[32m║\x1b[0m  Database Engine:    \x1b[35mMicrosoft SQL Server (MSSQL)\x1b[0m                 \x1b[32m║\x1b[0m
  \x1b[32m╚════════════════════════════════════════════════════════════════╝\x1b[0m
  `);
});
