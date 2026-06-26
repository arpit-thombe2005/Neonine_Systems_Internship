const sql = require('mssql');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// ─── Connection Configuration ────────────────────────────────────────────────
const config = {
  server: process.env.MSSQL_SERVER || 'localhost',
  database: process.env.MSSQL_DATABASE || 'neonine',
  user: process.env.MSSQL_USER || 'sa',
  password: process.env.MSSQL_PASSWORD || '',
  port: parseInt(process.env.MSSQL_PORT || '1433', 10),
  options: {
    encrypt: process.env.MSSQL_ENCRYPT === 'true',
    trustServerCertificate: process.env.MSSQL_TRUST_CERT !== 'false',
    enableArithAbort: true,
    instanceName: process.env.MSSQL_INSTANCE || undefined,
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

if (!process.env.MSSQL_SERVER) {
  console.warn('\x1b[33m%s\x1b[0m', 'WARNING: MSSQL_SERVER is not set in .env file!');
}

// ─── Connection Pool ─────────────────────────────────────────────────────────
let pool;

async function getPool() {
  if (!pool) {
    try {
      pool = await sql.connect(config);
      console.log('\x1b[32m%s\x1b[0m', 'Connected to MSSQL database successfully.');
    } catch (err) {
      console.error('\x1b[31m%s\x1b[0m', 'Failed to connect to MSSQL database:', err.message);
      throw err;
    }
  }
  return pool;
}

// ─── Query Helper ────────────────────────────────────────────────────────────
async function query(queryText, params = {}) {
  const p = await getPool();
  const request = p.request();

  for (const [key, val] of Object.entries(params)) {
    if (val && typeof val === 'object' && val.type) {
      request.input(key, val.type, val.value);
    } else {
      request.input(key, val);
    }
  }

  return request.query(queryText);
}

// ─── Database Initialization ─────────────────────────────────────────────────
async function initializeDatabase() {
  if (!process.env.MSSQL_SERVER) {
    console.warn('\x1b[33m%s\x1b[0m', 'Skipping database migration: MSSQL is not configured.');
    return;
  }

  try {
    const p = await getPool();

    const res = await p.request().query(`
      SELECT CASE WHEN EXISTS (
        SELECT * FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'users'
      ) THEN 1 ELSE 0 END AS table_exists;
    `);

    const usersTableExists = res.recordset[0].table_exists === 1;

    if (!usersTableExists) {
      console.log('\x1b[36m%s\x1b[0m', 'Database tables not found. Executing mssql_schema.sql automatically...');

      const schemaPath = path.join(__dirname, '..', 'mssql_schema.sql');
      if (fs.existsSync(schemaPath)) {
        const sqlSchema = fs.readFileSync(schemaPath, 'utf8');
        const batches = sqlSchema.split(/^\s*GO\s*$/im).filter(b => b.trim());
        for (const batch of batches) {
          await p.request().query(batch);
        }
        console.log('\x1b[32m%s\x1b[0m', 'Successfully executed mssql_schema.sql. Database is fully initialized!');
      } else {
        console.error('\x1b[31m%s\x1b[0m', `Migration failed: Could not find schema file at ${schemaPath}`);
      }
    } else {
      console.log('\x1b[32m%s\x1b[0m', 'Database tables are already initialized. Skipping migration.');
    }

    // Programmatically ensure the reviews table is created if it doesn't exist
    await p.request().query(`
      IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'reviews')
      BEGIN
        CREATE TABLE reviews (
          id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
          request_id          UNIQUEIDENTIFIER UNIQUE NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
          farmer_id           UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE NO ACTION,
          provider_id         UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE NO ACTION,
          rating              INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
          review_text         NVARCHAR(MAX),
          created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );
      END
    `);

    // Programmatically recreate v_online_providers view to add average ratings
    await p.request().query(`
      IF OBJECT_ID('v_online_providers', 'V') IS NOT NULL
        DROP VIEW v_online_providers;
    `);
    await p.request().query(`
      CREATE VIEW v_online_providers AS
      SELECT
          u.id AS user_id,
          u.full_name,
          u.phone_number,
          u.village_area,
          u.address,
          u.latitude,
          u.longitude,
          u.location_updated_at,
          sp.id AS provider_id,
          sp.service_name,
          sp.is_online,
          STUFF((
              SELECT ',' + sc2.name
              FROM provider_categories pc2
              JOIN service_categories sc2 ON sc2.id = pc2.category_id
              WHERE pc2.provider_id = sp.id
              FOR XML PATH('')
          ), 1, 1, '') AS categories,
          COALESCE((SELECT AVG(CAST(rating AS FLOAT)) FROM reviews WHERE provider_id = u.id), 0.0) AS avg_rating,
          (SELECT COUNT(*) FROM reviews WHERE provider_id = u.id) AS review_count
      FROM users u
      JOIN service_providers sp ON sp.user_id = u.id
      WHERE sp.is_online = 1;
    `);
  } catch (err) {
    console.error('\x1b[31m%s\x1b[0m', 'Error initializing database schema:', err.message);
  }
}

initializeDatabase();

module.exports = {
  query,
  getPool,
  sql,
};
