# Neonine Backend — Node.js & Express API Server

This is the central backend API server for the Neonine Flutter mobile application. It connects directly to your **Neon Serverless PostgreSQL Database** and provides robust endpoints for user profiles, real-time GPS tracking, nearby provider lookup, and service request counts.

---

## 🚀 Key Features

1. **Automatic Schema Migrations**: No need to run SQL files manually! The server automatically detects if the public tables exist. If not, it executes `neon_schema.sql` on startup to initialize your database instantly.
2. **Nearby Search (Haversine Formula)**: Searches for nearby online service providers using the Haversine formula computed directly inside SQL. This provides high-performance, real-time spatial calculations and distance sorting.
3. **Safe PostgreSQL Transactions**: User registrations are performed inside an ACID-compliant PostgreSQL transaction. This guarantees that service provider mappings and service categories are saved completely or not at all.
4. **Professional Morgan Logging**: Real-time HTTP request logging directly in your terminal console.

---

## 🛠️ Getting Started

### 1. Prerequisites
- **Node.js** (v18 or higher recommended)
- A **Neon PostgreSQL database** project (create one for free at [neon.tech](https://neon.tech))

### 2. Installation
Open your terminal inside this `backend` folder and install the required Node.js packages:
```bash
npm install
```

### 3. Database Configuration
Rename or edit the `.env` file inside this `backend` directory and set your Neon connection string:
```env
PORT=3000
DATABASE_URL="postgresql://<user>:<password>@<host>/<dbname>?sslmode=require"
```
*(You can copy this connection string directly from your Neon console dashboard).*

### 4. Running the Server

- **For Development (with Auto-Reload)**:
  ```bash
  npm run dev
  ```
- **For Production**:
  ```bash
  npm start
  ```

Once started, the database will be automatically checked and initialized! You should see:
```text
Database tables not found. Executing neon_schema.sql automatically...
Successfully executed neon_schema.sql. Database is fully initialized!
```

---

## 📡 API Endpoints Summary

### User & Auth
- `GET /api/users/phone/:phone` — Retrieve user profile and category/provider associations. Returns `404` if unregistered.
- `POST /api/users/register` — Register a new Farmer or Service Provider. Includes full user profiling.
- `PUT /api/users/:userId/location` — Real-time GPS coordinates update.

### Service Providers
- `PUT /api/providers/:userId/status` — Toggle a provider's online/offline visibility.
- `GET /api/providers/nearby?lat=...&lng=...&radius=...&category=...` — spatial querying to fetch nearby online providers.

### Service Requests
- `POST /api/requests` — Send a service request to a provider.
- `GET /api/providers/:providerId/requests/today` — Fetch request count for today.
- `GET /api/providers/:providerId/requests/today/list` — Fetch complete list of today's requests (with client details).

### System
- `GET /api/categories` — Get lists of pre-populated service categories (Tractor, Fertilizer, etc.).
- `GET /health` — Check system status, uptime, and database connection.
