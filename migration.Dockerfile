# Stage 1: Build database package
FROM node:23-alpine AS builder

# Install dependencies
RUN apk add --no-cache libc6-compat

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy workspace files
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY packages/database/package.json ./packages/database/

# Install dependencies
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --no-frozen-lockfile

# Copy database source and build
COPY packages/database ./packages/database
RUN pnpm --filter @streamystats/database build

# Stage 2: Runtime
FROM node:23-alpine AS runner

# Install runtime dependencies
RUN apk add --no-cache libc6-compat postgresql-client

WORKDIR /app

# Create minimal package.json for migration dependencies
RUN echo '{"name":"migrate","version":"1.0.0"}' > package.json

# Install packages one by one to minimize memory usage
RUN npm config set maxsockets 1 && \
    npm install --no-audit --no-fund drizzle-kit@0.31.1 && \
    npm install --no-audit --no-fund drizzle-orm@0.43.1 && \
    npm install --no-audit --no-fund postgres@^3.4.3 && \
    npm install --no-audit --no-fund dotenv@^16.3.1

# Copy migration files and config
COPY --from=builder /app/packages/database/drizzle ./packages/database/drizzle
COPY --from=builder /app/packages/database/drizzle.config.ts ./packages/database/drizzle.config.ts

# Create migration script
COPY <<'MIGRATION_SCRIPT' /app/run-migrations.sh
#!/bin/sh
set -e

echo "=== Database Migration Script ==="
echo "Starting at: $(date)"

# Function to check if PostgreSQL is ready
wait_for_postgres() {
    echo "Waiting for PostgreSQL to be ready..."
    until pg_isready -h "${DB_HOST:-vectorchord}" -p "${DB_PORT:-5432}" -U "${POSTGRES_USER:-postgres}"; do
        echo "PostgreSQL is not ready yet. Waiting..."
        sleep 2
    done
    echo "PostgreSQL is ready!"
}

# Function to check if database exists
check_database() {
    echo "Checking if database '${POSTGRES_DB:-streamystats}' exists..."
    if psql -h "${DB_HOST:-vectorchord}" -U "${POSTGRES_USER:-postgres}" -lqt | cut -d'|' -f1 | grep -qw "${POSTGRES_DB:-streamystats}"; then
        echo "Database '${POSTGRES_DB:-streamystats}' exists."
        return 0
    else
        echo "Database '${POSTGRES_DB:-streamystats}' does not exist."
        return 1
    fi
}

# Function to create database
create_database() {
    echo "Creating database '${POSTGRES_DB:-streamystats}'..."
    createdb -h "${DB_HOST:-vectorchord}" -U "${POSTGRES_USER:-postgres}" "${POSTGRES_DB:-streamystats}"
    echo "Database '${POSTGRES_DB:-streamystats}' created successfully!"
}

# Function to create extensions
create_extensions() {
    echo "Creating required PostgreSQL extensions..."
    
    # Create vector extension
    psql -h "${DB_HOST:-vectorchord}" -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-streamystats}" \
        -c "CREATE EXTENSION IF NOT EXISTS vector;" || {
        echo "Warning: Failed to create vector extension"
    }
    
    # Create uuid-ossp extension
    psql -h "${DB_HOST:-vectorchord}" -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-streamystats}" \
        -c 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";' || {
        echo "Warning: Failed to create uuid-ossp extension"
    }
    
    echo "Extensions created."
}

# Main execution
main() {
    # Extract connection details from DATABASE_URL if provided
    if [ -n "$DATABASE_URL" ]; then
        # Parse DATABASE_URL to extract components
        # Format: postgresql://user:password@host:port/database
        export PGPASSWORD=$(echo $DATABASE_URL | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
        export POSTGRES_USER=$(echo $DATABASE_URL | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
        export DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
        export DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
        export POSTGRES_DB=$(echo $DATABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')
    fi

    # Set defaults
    export DB_HOST="${DB_HOST:-vectorchord}"
    export DB_PORT="${DB_PORT:-5432}"
    export POSTGRES_USER="${POSTGRES_USER:-postgres}"
    export POSTGRES_DB="${POSTGRES_DB:-streamystats}"
    export PGPASSWORD="${PGPASSWORD:-${POSTGRES_PASSWORD:-postgres}}"

    echo "Configuration:"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT"
    echo "  User: $POSTGRES_USER"
    echo "  Database: $POSTGRES_DB"

    # Wait for PostgreSQL
    wait_for_postgres

    # Check and create database if needed
    if ! check_database; then
        create_database
    fi

    # Create extensions
    create_extensions

    # Run Drizzle migrations
    echo "Running database migrations with Drizzle..."
    cd /app/packages/database
    
    # Use npx to run drizzle-kit from node_modules
    npx drizzle-kit migrate

    echo "Migrations completed successfully!"

    echo "=== Migration script finished at: $(date) ==="
}

# Run main function
main
MIGRATION_SCRIPT

RUN chmod +x /app/run-migrations.sh

# Set environment variables
ENV NODE_ENV=production

# Run the migration script
CMD ["/app/run-migrations.sh"] 