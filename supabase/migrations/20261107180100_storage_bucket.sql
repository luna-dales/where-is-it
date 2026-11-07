
-- WhereIsIt: private storage bucket for grocery shelf photographs.
-- Maximum photograph size: 8 MB.
-- Accepted format: JPEG.

INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'shelf-photos',
    'shelf-photos',
    false,
    8388608,
    ARRAY['image/jpeg']
)
ON CONFLICT (id) DO UPDATE
SET
    name = EXCLUDED.name,
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;
