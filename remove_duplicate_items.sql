-- SQL Script to Remove Duplicate Items
-- This script identifies and removes duplicate items based on multiple criteria
-- Run this script carefully and consider backing up your database first

-- Step 1: Identify duplicates based on name, type, and server
-- This query shows potential duplicates for review
SELECT 
    name,
    type,
    server_id,
    library_id,
    COUNT(*) as duplicate_count,
    STRING_AGG(id, ', ' ORDER BY date_created DESC) as item_ids
FROM items 
GROUP BY name, type, server_id, library_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- Step 2: Create a backup table (optional but recommended)
CREATE TABLE items_backup AS SELECT * FROM items;

-- Step 3: Remove duplicates - Keep the most recently created item
-- This uses a window function to identify duplicates and delete older ones
WITH duplicate_items AS (
    SELECT 
        id,
        ROW_NUMBER() OVER (
            PARTITION BY name, type, server_id, library_id 
            ORDER BY date_created DESC NULLS LAST, id DESC
        ) as row_num
    FROM items
)
DELETE FROM items 
WHERE id IN (
    SELECT id 
    FROM duplicate_items 
    WHERE row_num > 1
);

-- Step 4: Alternative approach - Remove duplicates based on exact name and server only
-- Uncomment this section if you want a less strict duplicate detection
/*
WITH name_duplicates AS (
    SELECT 
        id,
        ROW_NUMBER() OVER (
            PARTITION BY name, server_id 
            ORDER BY date_created DESC NULLS LAST, id DESC
        ) as row_num
    FROM items
)
DELETE FROM items 
WHERE id IN (
    SELECT id 
    FROM name_duplicates 
    WHERE row_num > 1
);
*/

-- Step 5: Remove duplicates with same etag (if etag represents unique content)
-- Uncomment if etag should be unique per server
/*
WITH etag_duplicates AS (
    SELECT 
        id,
        ROW_NUMBER() OVER (
            PARTITION BY etag, server_id 
            ORDER BY date_created DESC NULLS LAST, id DESC
        ) as row_num
    FROM items
    WHERE etag IS NOT NULL
)
DELETE FROM items 
WHERE id IN (
    SELECT id 
    FROM etag_duplicates 
    WHERE row_num > 1
);
*/

-- Step 6: Clean up orphaned references (optional)
-- Remove any sessions that reference deleted items
DELETE FROM sessions 
WHERE item_id NOT IN (SELECT id FROM items);

-- Remove any activities that reference deleted items
UPDATE activities 
SET item_id = NULL 
WHERE item_id IS NOT NULL 
AND item_id NOT IN (SELECT id FROM items);

-- Step 7: Verify results
SELECT 
    'Total items after cleanup' as description,
    COUNT(*) as count
FROM items
UNION ALL
SELECT 
    'Remaining duplicates (name, type, server)',
    COUNT(*)
FROM (
    SELECT name, type, server_id, library_id
    FROM items 
    GROUP BY name, type, server_id, library_id
    HAVING COUNT(*) > 1
) duplicates;

-- Step 8: Update statistics (PostgreSQL specific)
ANALYZE items;

-- Optional: Drop backup table after verification
-- DROP TABLE items_backup;
