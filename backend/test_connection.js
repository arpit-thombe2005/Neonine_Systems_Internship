const sql = require('mssql');
require('dotenv').config();

const configs = [
  {
    name: '1) 127.0.0.1 with Port 1433 (No Instance)',
    config: {
      server: '127.0.0.1',
      port: 1433,
      database: process.env.MSSQL_DATABASE || 'neonine',
      user: process.env.MSSQL_USER || 'sa',
      password: process.env.MSSQL_PASSWORD,
      options: {
        encrypt: false,
        trustServerCertificate: true,
      },
      connectionTimeout: 5000,
    }
  },
  {
    name: '2) localhost with Port 1433 (No Instance)',
    config: {
      server: 'localhost',
      port: 1433,
      database: process.env.MSSQL_DATABASE || 'neonine',
      user: process.env.MSSQL_USER || 'sa',
      password: process.env.MSSQL_PASSWORD,
      options: {
        encrypt: false,
        trustServerCertificate: true,
      },
      connectionTimeout: 5000,
    }
  },
  {
    name: '3) localhost with SQLEXPRESS Instance (No Port)',
    config: {
      server: 'localhost',
      database: process.env.MSSQL_DATABASE || 'neonine',
      user: process.env.MSSQL_USER || 'sa',
      password: process.env.MSSQL_PASSWORD,
      options: {
        instanceName: 'SQLEXPRESS',
        encrypt: false,
        trustServerCertificate: true,
      },
      connectionTimeout: 5000,
    }
  },
  {
    name: '4) 127.0.0.1 with SQLEXPRESS Instance (No Port)',
    config: {
      server: '127.0.0.1',
      database: process.env.MSSQL_DATABASE || 'neonine',
      user: process.env.MSSQL_USER || 'sa',
      password: process.env.MSSQL_PASSWORD,
      options: {
        instanceName: 'SQLEXPRESS',
        encrypt: false,
        trustServerCertificate: true,
      },
      connectionTimeout: 5000,
    }
  }
];

async function runTests() {
  console.log('Testing SQL Server connection configurations...\n');
  
  for (const item of configs) {
    console.log(`Trying config: ${item.name}...`);
    try {
      const pool = await sql.connect(item.config);
      console.log(`✅ SUCCESS: Connected using ${item.name}!\n`);
      await sql.close();
      process.exit(0);
    } catch (err) {
      console.log(`❌ FAILED: ${err.message}\n`);
    }
  }
  
  console.log('All connection configurations failed.');
  process.exit(1);
}

runTests();
