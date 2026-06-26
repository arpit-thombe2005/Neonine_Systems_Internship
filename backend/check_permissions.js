const sql = require('mssql');
require('dotenv').config();

const config = {
  server: process.env.MSSQL_SERVER || '127.0.0.1',
  database: process.env.MSSQL_DATABASE || 'neonine',
  user: process.env.MSSQL_USER || 'neonine_admin',
  password: process.env.MSSQL_PASSWORD || 'Neonine@2026',
  port: parseInt(process.env.MSSQL_PORT || '1433', 10),
  options: {
    encrypt: process.env.MSSQL_ENCRYPT === 'true',
    trustServerCertificate: process.env.MSSQL_TRUST_CERT !== 'false',
  },
  connectionTimeout: 5000,
};

async function checkPermissions() {
  console.log(`Connecting to SQL Server at ${config.server}:${config.port}...`);
  console.log(`Database: ${config.database}`);
  console.log(`User: ${config.user}\n`);

  let pool;
  try {
    pool = await sql.connect(config);
    console.log('✅ Connection Successful!');
  } catch (err) {
    console.error('❌ Connection Failed!');
    console.error(`Error message: ${err.message}`);
    console.log('\nPossible causes:');
    if (err.message.includes('login failed') || err.message.includes('Login failed')) {
      console.log(`1. The password for user "${config.user}" is incorrect.`);
      console.log(`2. The login "${config.user}" does not exist in SQL Server.`);
      console.log('3. SQL Server is set to Windows Authentication mode only. It needs "SQL Server and Windows Authentication mode" enabled.');
    } else if (err.message.includes('Cannot open database')) {
      console.log(`1. The database "${config.database}" does not exist.`);
      console.log(`2. The user "${config.user}" has no access permissions to database "${config.database}".`);
    }
    process.exit(1);
  }

  try {
    // 1. Check current database and user context
    const contextResult = await pool.request().query(`
      SELECT 
        DB_NAME() AS current_db, 
        SUSER_NAME() AS server_login, 
        USER_NAME() AS db_user;
    `);
    const context = contextResult.recordset[0];
    console.log(`Context info:`);
    console.log(` - Current Database: ${context.current_db}`);
    console.log(` - Server Login Name: ${context.server_login}`);
    console.log(` - Database User Name: ${context.db_user}\n`);

    // 2. Check Database Roles
    const rolesResult = await pool.request().query(`
      SELECT r.name AS role_name
      FROM sys.database_role_members rm
      JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
      JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
      WHERE m.name = USER_NAME();
    `);
    
    console.log('Database Roles assigned to user:');
    if (rolesResult.recordset.length === 0) {
      console.log(' - (None) [Standard user with public access]');
    } else {
      rolesResult.recordset.forEach(row => {
        console.log(` - ${row.role_name}`);
      });
    }
    console.log('');

    // 3. Test Table Creation permissions by executing a temporary table creation
    console.log('Testing write permissions (creating a temporary test table)...');
    try {
      await pool.request().query(`
        IF OBJECT_ID('temp_permission_test_table', 'U') IS NOT NULL
          DROP TABLE temp_permission_test_table;
        
        CREATE TABLE temp_permission_test_table (
          id INT PRIMARY KEY,
          test_col VARCHAR(10)
        );
        
        DROP TABLE temp_permission_test_table;
      `);
      console.log('✅ Success: User has table creation (DDL) and deletion privileges!\n');
    } catch (createErr) {
      console.error('❌ Failed: User does NOT have privileges to create tables.');
      console.error(`Error: ${createErr.message}\n`);
    }

  } catch (err) {
    console.error(`❌ Error retrieving permissions: ${err.message}`);
  } finally {
    await sql.close();
  }
}

checkPermissions();
