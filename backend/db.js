const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Verify that the connection string is provided
if (!process.env.DATABASE_URL) {
  console.warn('\x1b[33m%s\x1b[0m', 'WARNING: DATABASE_URL is not set in environment variables or .env file!');
}

// Establish database pool with SSL configured for Neon serverless PostgreSQL
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL ? { rejectUnauthorized: false } : false,
});

/**
 * Automatically checks and executes the neon_schema.sql if tables do not exist.
 */
async function initializeDatabase() {
  if (!process.env.DATABASE_URL) {
    console.warn('\x1b[33m%s\x1b[0m', 'Skipping database migration: DATABASE_URL is empty.');
    return;
  }

  const client = await pool.connect();
  try {
    // Check if the 'users' table already exists
    const res = await client.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'users'
      );
    `);

    const usersTableExists = res.rows[0].exists;

    if (!usersTableExists) {
      console.log('\x1b[36m%s\x1b[0m', 'Database tables not found. Executing neon_schema.sql automatically...');
      
      // Read neon_schema.sql from the parent directory
      const schemaPath = path.join(__dirname, '..', 'neon_schema.sql');
      if (fs.existsSync(schemaPath)) {
        const sqlSchema = fs.readFileSync(schemaPath, 'utf8');
        
        // Execute the entire SQL schema
        await client.query(sqlSchema);
        console.log('\x1b[32m%s\x1b[0m', 'Successfully executed neon_schema.sql. Database is fully initialized!');
      } else {
        console.error('\x1b[31m%s\x1b[0m', `Migration failed: Could not find schema file at ${schemaPath}`);
      }
    } else {
      console.log('\x1b[32m%s\x1b[0m', 'Database tables are already initialized. Skipping migration.');
    }
  } catch (err) {
    console.error('\x1b[31m%s\x1b[0m', 'Error initializing database schema:', err.message);
  } finally {
    client.release();
  }
}

// Trigger initialization on module import
initializeDatabase();

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};
