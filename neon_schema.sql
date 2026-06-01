-- ============================================================================
-- NEONINE — Neon (PostgreSQL) Database Schema
-- ============================================================================
-- Run this SQL on your Neon database console to create all required tables.
-- Connection: Use the connection string from your Neon dashboard.
-- ============================================================================

-- Enable UUID extension for generating unique IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- 1. USERS TABLE
-- Stores all registered users (both farmers and service providers)
-- ============================================================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name       VARCHAR(100) NOT NULL,
    phone_number    VARCHAR(15) UNIQUE NOT NULL,     -- Format: "917208155789" (no +)
    user_type       VARCHAR(20) NOT NULL CHECK (user_type IN ('farmer', 'service_provider')),
    village_area    VARCHAR(150),
    address         TEXT,
    latitude        DOUBLE PRECISION,                 -- Last known GPS latitude
    longitude       DOUBLE PRECISION,                 -- Last known GPS longitude
    location_updated_at TIMESTAMPTZ,                  -- When location was last updated
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast phone number lookups during login
CREATE INDEX idx_users_phone ON users (phone_number);

-- Index for finding nearby providers by location
CREATE INDEX idx_users_location ON users (latitude, longitude) WHERE user_type = 'service_provider';

-- ============================================================================
-- 2. SERVICE CATEGORIES TABLE
-- Pre-populated list of available service categories
-- ============================================================================
CREATE TABLE service_categories (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(50) UNIQUE NOT NULL
);

-- Pre-populate with the required categories
INSERT INTO service_categories (name) VALUES
    ('Tractor'),
    ('Fertilizer'),
    ('Feed Supplier'),
    ('Machinery Rental'),
    ('Transport'),
    ('Other');

-- ============================================================================
-- 3. SERVICE PROVIDERS TABLE
-- Additional data for users with user_type = 'service_provider'
-- ============================================================================
CREATE TABLE service_providers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    service_name    VARCHAR(150) NOT NULL,             -- Name of the service they offer
    is_online       BOOLEAN NOT NULL DEFAULT FALSE,    -- Online/Offline toggle status
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_providers_user ON service_providers (user_id);
CREATE INDEX idx_providers_online ON service_providers (is_online) WHERE is_online = TRUE;

-- ============================================================================
-- 4. PROVIDER CATEGORIES TABLE (Junction / Many-to-Many)
-- Links service providers to their selected service categories
-- ============================================================================
CREATE TABLE provider_categories (
    id              SERIAL PRIMARY KEY,
    provider_id     UUID NOT NULL REFERENCES service_providers(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES service_categories(id) ON DELETE CASCADE,
    UNIQUE (provider_id, category_id)
);

CREATE INDEX idx_provider_cats_provider ON provider_categories (provider_id);
CREATE INDEX idx_provider_cats_category ON provider_categories (category_id);

-- ============================================================================
-- 5. SERVICE REQUESTS TABLE
-- Requests sent from farmers to service providers
-- ============================================================================
CREATE TABLE service_requests (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farmer_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id         INTEGER REFERENCES service_categories(id) ON DELETE SET NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'accepted', 'rejected', 'completed', 'cancelled')),
    message             TEXT,                          -- Optional message from farmer
    farmer_latitude     DOUBLE PRECISION,              -- Farmer's location at time of request
    farmer_longitude    DOUBLE PRECISION,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_requests_farmer ON service_requests (farmer_id);
CREATE INDEX idx_requests_provider ON service_requests (provider_id);
CREATE INDEX idx_requests_created ON service_requests (created_at);
-- Index for counting today's requests quickly
CREATE INDEX idx_requests_provider_date ON service_requests (provider_id, created_at DESC);

-- ============================================================================
-- 6. HELPER FUNCTION: Auto-update `updated_at` timestamp
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply auto-update trigger to all tables with updated_at
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_providers_updated_at
    BEFORE UPDATE ON service_providers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_requests_updated_at
    BEFORE UPDATE ON service_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 7. USEFUL VIEWS
-- ============================================================================

-- View: Online providers with their categories and location
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
    ARRAY_AGG(sc.name) AS categories
FROM users u
JOIN service_providers sp ON sp.user_id = u.id
LEFT JOIN provider_categories pc ON pc.provider_id = sp.id
LEFT JOIN service_categories sc ON sc.id = pc.category_id
WHERE sp.is_online = TRUE
GROUP BY u.id, u.full_name, u.phone_number, u.village_area, u.address,
         u.latitude, u.longitude, u.location_updated_at,
         sp.id, sp.service_name, sp.is_online;

-- View: Today's request count per provider
CREATE VIEW v_today_requests AS
SELECT
    provider_id,
    COUNT(*) AS request_count
FROM service_requests
WHERE created_at >= CURRENT_DATE
GROUP BY provider_id;
