const db = require('./db');

async function createViews() {
  console.log('Connecting to database and creating views...');
  try {
    const pool = await db.getPool();

    // Drop v_online_providers if it exists
    console.log('Dropping existing v_online_providers view if any...');
    await pool.request().query(`
      IF OBJECT_ID('v_online_providers', 'V') IS NOT NULL
        DROP VIEW v_online_providers;
    `);

    // Create v_online_providers view
    console.log('Creating v_online_providers view...');
    await pool.request().query(`
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
          ), 1, 1, '') AS categories
      FROM users u
      JOIN service_providers sp ON sp.user_id = u.id
      WHERE sp.is_online = 1;
    `);
    console.log('✅ Successfully created v_online_providers view!');

    // Drop v_today_requests if it exists
    console.log('Dropping existing v_today_requests view if any...');
    await pool.request().query(`
      IF OBJECT_ID('v_today_requests', 'V') IS NOT NULL
        DROP VIEW v_today_requests;
    `);

    // Create v_today_requests view
    console.log('Creating v_today_requests view...');
    await pool.request().query(`
      CREATE VIEW v_today_requests AS
      SELECT
          provider_id,
          COUNT(*) AS request_count
      FROM service_requests
      WHERE created_at >= CAST(GETUTCDATE() AS DATE)
      GROUP BY provider_id;
    `);
    console.log('✅ Successfully created v_today_requests view!');

    console.log('\nAll database views are fully initialized and ready!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Failed to create views:', err.message);
    process.exit(1);
  }
}

createViews();
