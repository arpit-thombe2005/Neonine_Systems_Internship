-- ============================================================================
-- NEONINE — Microsoft SQL Server (MSSQL) Database Schema
-- ============================================================================

-- 1. USERS TABLE
CREATE TABLE users (
    id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    full_name           NVARCHAR(100) NOT NULL,
    phone_number        VARCHAR(15) UNIQUE NOT NULL,     -- Format: "917208155789"
    aadhaar_hash        VARCHAR(64) UNIQUE NOT NULL,     -- SHA-256 hash of Aadhaar number
    user_type           VARCHAR(20) NOT NULL CHECK (user_type IN ('farmer', 'service_provider')),
    village_area        NVARCHAR(150),
    address             NVARCHAR(MAX),
    latitude            FLOAT,                           -- Last known GPS latitude
    longitude           FLOAT,                           -- Last known GPS longitude
    location_updated_at DATETIMEOFFSET,                  -- When location was last updated
    created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    updated_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

-- Index for phone number search
CREATE NONCLUSTERED INDEX idx_users_phone ON users (phone_number);

-- 2. SERVICE CATEGORIES TABLE
CREATE TABLE service_categories (
    id      INT IDENTITY(1,1) PRIMARY KEY,
    name    NVARCHAR(50) UNIQUE NOT NULL
);

-- Pre-populate categories
SET IDENTITY_INSERT service_categories ON;
INSERT INTO service_categories (id, name) VALUES
    (1, 'Tractor'),
    (2, 'Harvester'),
    (3, 'Rotavator'),
    (4, 'Seed Drill'),
    (5, 'Power Sprayer'),
    (6, 'Thresher');
SET IDENTITY_INSERT service_categories OFF;

-- 3. SERVICE PROVIDERS TABLE
CREATE TABLE service_providers (
    id              UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    user_id         UNIQUEIDENTIFIER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    service_name    NVARCHAR(150) NOT NULL,
    is_online       BIT NOT NULL DEFAULT 0,
    created_at      DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    updated_at      DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

-- 4. PROVIDER CATEGORIES TABLE
CREATE TABLE provider_categories (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    provider_id     UNIQUEIDENTIFIER NOT NULL REFERENCES service_providers(id) ON DELETE CASCADE,
    category_id     INT NOT NULL REFERENCES service_categories(id) ON DELETE CASCADE,
    CONSTRAINT UQ_Provider_Category UNIQUE (provider_id, category_id)
);

-- 5. SERVICE REQUESTS TABLE
CREATE TABLE service_requests (
    id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    farmer_id           UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id         UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE NO ACTION, -- Prevent cycles
    category_id         INT REFERENCES service_categories(id) ON DELETE SET NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'accepted', 'rejected', 'completed', 'cancelled')),
    message             NVARCHAR(MAX),
    farmer_latitude     FLOAT,
    farmer_longitude    FLOAT,
    created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    updated_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

GO

-- 6. VIEWS
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

GO

CREATE VIEW v_today_requests AS
SELECT
    provider_id,
    COUNT(*) AS request_count
FROM service_requests
WHERE created_at >= CAST(GETUTCDATE() AS DATE)
GROUP BY provider_id;

GO

-- 7. REVIEWS TABLE
CREATE TABLE reviews (
    id                  UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    request_id          UNIQUEIDENTIFIER UNIQUE NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
    farmer_id           UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE NO ACTION,
    provider_id         UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE NO ACTION,
    rating              INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text         NVARCHAR(MAX),
    created_at          DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
