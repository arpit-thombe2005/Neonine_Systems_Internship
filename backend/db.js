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

    // Programmatically update users.user_type check constraint to exclude 'agent' (keep only 'farmer', 'service_provider')
    await p.request().query(`
      -- Clean up any legacy agent users first so the constraint validation succeeds
      DELETE FROM users WHERE user_type = 'agent';

      DECLARE @ConstraintName NVARCHAR(200)
      SELECT @ConstraintName = name
      FROM sys.check_constraints
      WHERE parent_object_id = OBJECT_ID('users')
        AND definition LIKE '%user_type%'

      IF @ConstraintName IS NOT NULL
      BEGIN
          EXEC('ALTER TABLE users DROP CONSTRAINT ' + @ConstraintName)
      END

      IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('users') AND name = 'CK_users_user_type')
      BEGIN
          ALTER TABLE users ADD CONSTRAINT CK_users_user_type CHECK (user_type IN ('farmer', 'service_provider'));
      END
    `);

    // Programmatically ensure service categories are farming equipment
    await p.request().query(`
      IF EXISTS (SELECT * FROM service_categories WHERE id = 1)
        UPDATE service_categories SET name = 'Tractor' WHERE id = 1;
      ELSE
      BEGIN
        SET IDENTITY_INSERT service_categories ON;
        INSERT INTO service_categories (id, name) VALUES (1, 'Tractor');
        SET IDENTITY_INSERT service_categories OFF;
      END
      
      IF EXISTS (SELECT * FROM service_categories WHERE id = 2)
        UPDATE service_categories SET name = 'Harvester' WHERE id = 2;
      ELSE
      BEGIN
        SET IDENTITY_INSERT service_categories ON;
        INSERT INTO service_categories (id, name) VALUES (2, 'Harvester');
        SET IDENTITY_INSERT service_categories OFF;
      END

      IF EXISTS (SELECT * FROM service_categories WHERE id = 3)
        UPDATE service_categories SET name = 'Rotavator' WHERE id = 3;
      ELSE
      BEGIN
        SET IDENTITY_INSERT service_categories ON;
        INSERT INTO service_categories (id, name) VALUES (3, 'Rotavator');
        SET IDENTITY_INSERT service_categories OFF;
      END

      IF EXISTS (SELECT * FROM service_categories WHERE id = 4)
        UPDATE service_categories SET name = 'Seed Drill' WHERE id = 4;
      ELSE
      BEGIN
        SET IDENTITY_INSERT service_categories ON;
        INSERT INTO service_categories (id, name) VALUES (4, 'Seed Drill');
        SET IDENTITY_INSERT service_categories OFF;
      END

      IF EXISTS (SELECT * FROM service_categories WHERE id = 5)
        UPDATE service_categories SET name = 'Power Sprayer' WHERE id = 5;
      ELSE
      BEGIN
        SET IDENTITY_INSERT service_categories ON;
        INSERT INTO service_categories (id, name) VALUES (5, 'Power Sprayer');
        SET IDENTITY_INSERT service_categories OFF;
      END

      IF EXISTS (SELECT * FROM service_categories WHERE id = 6)
        UPDATE service_categories SET name = 'Thresher' WHERE id = 6;
      ELSE
      BEGIN
        SET IDENTITY_INSERT service_categories ON;
        INSERT INTO service_categories (id, name) VALUES (6, 'Thresher');
        SET IDENTITY_INSERT service_categories OFF;
      END
    `);

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

    // Programmatically ensure the equipment table is created if it doesn't exist
    await p.request().query(`
      IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'equipment')
      BEGIN
        CREATE TABLE equipment (
          id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
          provider_id         UNIQUEIDENTIFIER NOT NULL REFERENCES service_providers(id) ON DELETE CASCADE,
          name                NVARCHAR(100) NOT NULL,
          category_id         INT NOT NULL REFERENCES service_categories(id),
          price_per_hour      DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
          availability_status VARCHAR(20) NOT NULL DEFAULT 'available'
                              CHECK (availability_status IN ('available', 'rented', 'maintenance')),
          created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );
      END
    `);

    // Programmatically ensure the payments table is created if it doesn't exist
    await p.request().query(`
      IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'payments')
      BEGIN
        CREATE TABLE payments (
          id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
          request_id          UNIQUEIDENTIFIER UNIQUE NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
          amount              DECIMAL(10, 2) NOT NULL,
          payment_status      VARCHAR(20) NOT NULL DEFAULT 'unpaid'
                              CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
          transaction_id      VARCHAR(100),
          created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );
      END
    `);

    // Programmatically ensure the chat_messages table is created if it doesn't exist
    await p.request().query(`
      IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'chat_messages')
      BEGIN
        CREATE TABLE chat_messages (
          id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
          request_id          UNIQUEIDENTIFIER NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
          sender_id           UNIQUEIDENTIFIER NOT NULL REFERENCES users(id),
          message_text        NVARCHAR(MAX) NOT NULL,
          created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );
      END
    `);

    // Programmatically ensure the notifications table is created if it doesn't exist
    await p.request().query(`
      IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'notifications')
      BEGIN
        CREATE TABLE notifications (
          id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
          user_id             UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          title               NVARCHAR(100) NOT NULL,
          message             NVARCHAR(500) NOT NULL,
          is_read             BIT NOT NULL DEFAULT 0,
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
