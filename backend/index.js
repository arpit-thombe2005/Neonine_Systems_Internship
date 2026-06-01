const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
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

// ─── User Endpoints ──────────────────────────────────────────────────────────

/**
 * GET /api/users/phone/:phone
 * Checks if a user exists by phone number.
 * Returns combined user and service provider data if registered.
 */
app.get('/api/users/phone/:phone', async (req, res) => {
  const { phone } = req.params;

  try {
    const queryStr = `
      SELECT 
        u.id, 
        u.full_name, 
        u.phone_number, 
        u.user_type, 
        u.village_area, 
        u.address, 
        u.latitude, 
        u.longitude, 
        u.location_updated_at,
        sp.id AS provider_id, 
        sp.service_name, 
        sp.is_online,
        ARRAY(
          SELECT category_id FROM provider_categories WHERE provider_id = sp.id
        ) AS category_ids
      FROM users u
      LEFT JOIN service_providers sp ON sp.user_id = u.id
      WHERE u.phone_number = $1;
    `;

    const { rows } = await db.query(queryStr, [phone]);

    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    // Standardize category_ids into integers array
    const user = rows[0];
    if (user.category_ids) {
      user.category_ids = user.category_ids.map(Number);
    }

    return res.status(200).json(user);
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch user by phone number', err);
  }
});

/**
 * POST /api/users/register
 * Registers a new user (Farmer or Service Provider).
 * Uses a safe PostgreSQL Transaction to link tables.
 */
app.post('/api/users/register', async (req, res) => {
  const {
    full_name,
    phone_number,
    user_type,
    village_area,
    address,
    latitude,
    longitude,
    service_name,
    category_ids,
  } = req.body;

  if (!full_name || !phone_number || !user_type) {
    return sendError(res, 400, 'Missing required fields: full_name, phone_number, and user_type are mandatory.');
  }

  const client = await db.pool.connect();

  try {
    // Begin Database Transaction
    await client.query('BEGIN');

    // 1. Insert into 'users' table
    const userInsertQuery = `
      INSERT INTO users (full_name, phone_number, user_type, village_area, address, latitude, longitude, location_updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
      RETURNING id;
    `;
    const userResult = await client.query(userInsertQuery, [
      full_name,
      phone_number,
      user_type,
      village_area || null,
      address || null,
      latitude || null,
      longitude || null,
    ]);

    const userId = userResult.rows[0].id;

    // 2. Conditional insertion for Service Provider
    if (user_type === 'service_provider') {
      if (!service_name) {
        throw new Error('service_name is mandatory for service providers');
      }

      const spInsertQuery = `
        INSERT INTO service_providers (user_id, service_name, is_online)
        VALUES ($1, $2, FALSE)
        RETURNING id;
      `;
      const spResult = await client.query(spInsertQuery, [userId, service_name]);
      const providerId = spResult.rows[0].id;

      // 3. Map categories if provided
      if (category_ids && Array.isArray(category_ids) && category_ids.length > 0) {
        const pcInsertQuery = `
          INSERT INTO provider_categories (provider_id, category_id)
          VALUES ($1, $2);
        `;
        for (const catId of category_ids) {
          await client.query(pcInsertQuery, [providerId, catId]);
        }
      }
    }

    // Commit Transaction
    await client.query('COMMIT');

    // Fetch the newly created complete user record to return to the app
    const fetchQuery = `
      SELECT 
        u.id, 
        u.full_name, 
        u.phone_number, 
        u.user_type, 
        u.village_area, 
        u.address, 
        u.latitude, 
        u.longitude, 
        u.location_updated_at,
        sp.id AS provider_id, 
        sp.service_name, 
        sp.is_online,
        ARRAY(
          SELECT category_id FROM provider_categories WHERE provider_id = sp.id
        ) AS category_ids
      FROM users u
      LEFT JOIN service_providers sp ON sp.user_id = u.id
      WHERE u.id = $1;
    `;
    const fetchResult = await db.query(fetchQuery, [userId]);
    const registeredUser = fetchResult.rows[0];

    if (registeredUser.category_ids) {
      registeredUser.category_ids = registeredUser.category_ids.map(Number);
    }

    return res.status(201).json(registeredUser);
  } catch (err) {
    await client.query('ROLLBACK');
    return sendError(res, 500, 'Registration failed. Transaction rolled back.', err);
  } finally {
    client.release();
  }
});

// ─── Location Endpoints ──────────────────────────────────────────────────────

/**
 * PUT /api/users/:userId/location
 * Updates GPS location for a specific user.
 */
app.put('/api/users/:userId/location', async (req, res) => {
  const { userId } = req.params;
  const { latitude, longitude } = req.body;

  if (latitude === undefined || longitude === undefined) {
    return sendError(res, 400, 'Missing required fields: latitude and longitude are mandatory.');
  }

  try {
    const queryStr = `
      UPDATE users 
      SET latitude = $1, longitude = $2, location_updated_at = NOW() 
      WHERE id = $3 
      RETURNING id, full_name, latitude, longitude, location_updated_at;
    `;
    const { rows } = await db.query(queryStr, [latitude, longitude, userId]);

    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    return res.status(200).json(rows[0]);
  } catch (err) {
    return sendError(res, 500, 'Failed to update location coordinates', err);
  }
});

// ─── Service Provider Endpoints ──────────────────────────────────────────────

/**
 * PUT /api/providers/:userId/status
 * Toggles online/offline status for a service provider.
 * Note: accepts the user's ID as the parameter.
 */
app.put('/api/providers/:userId/status', async (req, res) => {
  const { userId } = req.params;
  const { is_online } = req.body;

  if (is_online === undefined) {
    return sendError(res, 400, 'Missing required field: is_online is mandatory.');
  }

  try {
    const queryStr = `
      UPDATE service_providers 
      SET is_online = $1 
      WHERE user_id = $2 
      RETURNING id, user_id, service_name, is_online, updated_at;
    `;
    const { rows } = await db.query(queryStr, [is_online, userId]);

    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Service provider not found for this user ID' });
    }

    return res.status(200).json(rows[0]);
  } catch (err) {
    return sendError(res, 500, 'Failed to toggle service provider online status', err);
  }
});

/**
 * GET /api/providers/nearby
 * Fetches online service providers near coordinates.
 * Utilizes the Haversine formula directly in SQL to perform precise distance sorting.
 */
app.get('/api/providers/nearby', async (req, res) => {
  const { lat, lng, radius, category } = req.query;

  if (!lat || !lng) {
    return sendError(res, 400, 'Missing query parameters: lat and lng are mandatory.');
  }

  const originLat = parseFloat(lat);
  const originLng = parseFloat(lng);
  const radiusKm = radius ? parseFloat(radius) : 25.0; // default to 25km

  try {
    // 6371 is the radius of the Earth in kilometers.
    // We wrap Haversine formula in a SELECT to compute 'distance' in km.
    let queryStr = `
      SELECT * FROM (
        SELECT 
          user_id,
          full_name,
          phone_number,
          village_area,
          address,
          latitude,
          longitude,
          location_updated_at,
          provider_id,
          service_name,
          is_online,
          categories,
          (6371 * acos(
            cos(radians($1)) * cos(radians(latitude)) * 
            cos(radians(longitude) - radians($2)) + 
            sin(radians($1)) * sin(radians(latitude))
          )) AS distance
        FROM v_online_providers
        WHERE latitude IS NOT NULL AND longitude IS NOT NULL
      ) AS nearby_providers
      WHERE distance <= $3
    `;

    const params = [originLat, originLng, radiusKm];

    // If category filter is supplied, check if the string matches any in the categories array
    if (category) {
      queryStr += ` AND $4 = ANY(categories)`;
      params.push(category);
    }

    queryStr += ` ORDER BY distance ASC;`;

    const { rows } = await db.query(queryStr, params);

    return res.status(200).json({
      success: true,
      providers: rows,
    });
  } catch (err) {
    // Graceful error handling for acos out-of-range or empty database
    return sendError(res, 500, 'Failed to fetch nearby service providers', err);
  }
});

// ─── Service Request Endpoints ───────────────────────────────────────────────

/**
 * GET /api/providers/:providerId/requests/today
 * Gets the count of requests a provider has received today.
 * Note: providerId is the user ID.
 */
app.get('/api/providers/:providerId/requests/today', async (req, res) => {
  const { providerId } = req.params;

  try {
    const queryStr = `
      SELECT COUNT(*) AS count 
      FROM service_requests 
      WHERE provider_id = $1 AND created_at >= CURRENT_DATE;
    `;
    const { rows } = await db.query(queryStr, [providerId]);
    const count = parseInt(rows[0].count, 10);

    return res.status(200).json({ success: true, count });
  } catch (err) {
    return sendError(res, 500, "Failed to retrieve today's request count", err);
  }
});

/**
 * GET /api/providers/:providerId/requests/today/list
 * Gets the detailed list of requests a provider received today.
 * Note: providerId is the user ID.
 */
app.get('/api/providers/:providerId/requests/today/list', async (req, res) => {
  const { providerId } = req.params;

  try {
    const queryStr = `
      SELECT 
        sr.id, 
        sr.farmer_id, 
        sr.category_id, 
        sr.status, 
        sr.message, 
        sr.farmer_latitude, 
        sr.farmer_longitude, 
        sr.created_at,
        u.full_name AS farmer_name, 
        u.phone_number AS farmer_phone
      FROM service_requests sr
      JOIN users u ON sr.farmer_id = u.id
      WHERE sr.provider_id = $1 AND sr.created_at >= CURRENT_DATE
      ORDER BY sr.created_at DESC;
    `;
    const { rows } = await db.query(queryStr, [providerId]);

    return res.status(200).json({ success: true, requests: rows });
  } catch (err) {
    return sendError(res, 500, "Failed to retrieve today's request list", err);
  }
});

/**
 * POST /api/requests
 * Creates a new service request from a farmer.
 */
app.post('/api/requests', async (req, res) => {
  const {
    farmer_id,
    provider_id,
    category_id,
    message,
    farmer_latitude,
    farmer_longitude,
  } = req.body;

  if (!farmer_id || !provider_id) {
    return sendError(res, 400, 'Missing required fields: farmer_id and provider_id are mandatory.');
  }

  try {
    const queryStr = `
      INSERT INTO service_requests 
        (farmer_id, provider_id, category_id, message, farmer_latitude, farmer_longitude, status)
      VALUES 
        ($1, $2, $3, $4, $5, $6, 'pending')
      RETURNING *;
    `;
    const { rows } = await db.query(queryStr, [
      farmer_id,
      provider_id,
      category_id || null,
      message || null,
      farmer_latitude || null,
      farmer_longitude || null,
    ]);

    return res.status(201).json(rows[0]);
  } catch (err) {
    return sendError(res, 500, 'Failed to create service request', err);
  }
});

// ─── Categories Endpoint ─────────────────────────────────────────────────────

/**
 * GET /api/categories
 * Returns list of all available service categories.
 */
app.get('/api/categories', async (req, res) => {
  try {
    const queryStr = 'SELECT id, name FROM service_categories ORDER BY id ASC;';
    const { rows } = await db.query(queryStr);
    return res.status(200).json({ success: true, categories: rows });
  } catch (err) {
    return sendError(res, 500, 'Failed to fetch service categories', err);
  }
});

// ─── Root & System Status ────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date(),
    uptime: process.uptime(),
  });
});

// ─── Start Server ────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`
  \x1b[32m╔════════════════════════════════════════════════════════════════╗\x1b[0m
  \x1b[32m║               NEONINE BACKEND RUNNING SUCCESSFULLY             ║\x1b[0m
  \x1b[32m╠════════════════════════════════════════════════════════════════╣\x1b[0m
  \x1b[32m║\x1b[0m  Local Server URL:   \x1b[36mhttp://localhost:${PORT}\x1b[0m                      \x1b[32m║\x1b[0m
  \x1b[32m║\x1b[0m  Health Check:       \x1b[36mhttp://localhost:${PORT}/health\x1b[0m               \x1b[32m║\x1b[0m
  \x1b[32m║\x1b[0m  Database Status:    \x1b[35mPool initialized, checking schema...\x1b[0m         \x1b[32m║\x1b[0m
  \x1b[32m╚════════════════════════════════════════════════════════════════╝\x1b[0m
  `);
});
