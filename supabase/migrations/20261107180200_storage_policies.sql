
-- ============================================================
-- WhereIsIt - Supabase Storage Policies
-- Bucket: shelf-photos
--
-- 1. Users can read their own photographs.
-- 2. Users can upload photographs to their own folders.
-- 3. Authenticated users can retrieve photographs linked
--    to saved shelf-photo records.
-- ============================================================


-- Policy 1: Read photographs belonging to the current user.

CREATE POLICY "Users can read their own shelf photos"
ON "storage"."objects"
FOR SELECT
TO "authenticated"
USING (
    "bucket_id" = 'shelf-photos'::text
    AND ("storage"."foldername"("name"))[1] = (
        SELECT ("auth"."uid"())::text
    )
);


-- Policy 2: Upload JPEG photographs to the user's own folder.

CREATE POLICY "Users can upload their own shelf photos"
ON "storage"."objects"
FOR INSERT
TO "authenticated"
WITH CHECK (
    "bucket_id" = 'shelf-photos'::text
    AND ("storage"."foldername"("name"))[1] = (
        SELECT ("auth"."uid"())::text
    )
    AND "lower"("storage"."extension"("name")) = ANY (
        ARRAY['jpg'::text, 'jpeg'::text]
    )
);


-- Policy 3: Allow authenticated users to retrieve linked
-- shelf photographs contributed by other users.
--
-- Both operations are required:
--   object.get_authenticated
--   object.get_authenticated_info
--
-- The second operation resolved the "Object not found"
-- error encountered when viewing another user's photograph.

CREATE POLICY "WhereIsIt users can read linked shelf photos"
ON "storage"."objects"
FOR SELECT
TO "authenticated"
USING (
    "bucket_id" = 'shelf-photos'::text

    AND "storage"."allow_any_operation"(
        ARRAY[
            'object.get_authenticated',
            'object.get_authenticated_info'
        ]
    )

    AND EXISTS (
        SELECT 1
        FROM "public"."shelf_photos" AS "sp"
        WHERE "sp"."image_path" = "objects"."name"
    )
);
