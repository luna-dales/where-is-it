


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."link_shelf_photo"("p_photo_id" "uuid", "p_image_path" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
    v_user_id uuid;
BEGIN
    v_user_id := (SELECT auth.uid());

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Only allow files inside the authenticated user's folder.
    IF split_part(p_image_path, '/', 1) <> v_user_id::text
       OR p_image_path !~* '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
    THEN
        RAISE EXCEPTION 'Invalid photograph storage path';
    END IF;

    -- Verify the photograph really exists in private storage.
    IF NOT EXISTS (
        SELECT 1
        FROM storage.objects
        WHERE bucket_id = 'shelf-photos'
          AND name = p_image_path
          AND owner_id = v_user_id::text
    ) THEN
        RAISE EXCEPTION 'Photograph not found or not owned by user';
    END IF;

    -- Only the contributor can link an image to their observation.
    UPDATE public.shelf_photos
    SET image_path = p_image_path
    WHERE id = p_photo_id
      AND contributor_id = v_user_id
      AND image_path IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Photo record not found, not owned, or already linked';
    END IF;
END;
$_$;


ALTER FUNCTION "public"."link_shelf_photo"("p_photo_id" "uuid", "p_image_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_reviewed_observations"("p_store_id" "uuid", "p_aisle_number" "text", "p_shelf_side" "text", "p_products" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    v_user_id UUID;
    v_photo_id UUID;
    v_product_id UUID;
    v_item JSONB;
    v_brand TEXT;
    v_name TEXT;
    v_variety TEXT;
    v_package_size TEXT;
    v_identification TEXT;
    v_shelf INTEGER;
    v_x DOUBLE PRECISION;
    v_y DOUBLE PRECISION;
    v_width DOUBLE PRECISION;
    v_height DOUBLE PRECISION;
    v_count INTEGER := 0;
BEGIN
    -- The caller must be authenticated.
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Validate the store.
    IF NOT EXISTS (
        SELECT 1
        FROM public.stores
        WHERE id = p_store_id
    ) THEN
        RAISE EXCEPTION 'Invalid store';
    END IF;

    -- Validate the aisle and side.
    IF p_aisle_number IS NULL
       OR length(trim(p_aisle_number)) NOT BETWEEN 1 AND 20
       OR p_shelf_side IS NULL
       OR p_shelf_side NOT IN ('Left', 'Right')
    THEN
        RAISE EXCEPTION 'Invalid shelf location';
    END IF;

    -- Limit the number of products per contribution.
    IF p_products IS NULL
       OR jsonb_typeof(p_products) <> 'array'
       OR jsonb_array_length(p_products) NOT BETWEEN 1 AND 100
    THEN
        RAISE EXCEPTION 'Invalid product list';
    END IF;

    -- Create the contribution record.
    INSERT INTO public.shelf_photos (
        store_id,
        contributor_id,
        aisle_number,
        shelf_side
    )
    VALUES (
        p_store_id,
        v_user_id,
        trim(p_aisle_number),
        p_shelf_side
    )
    RETURNING id INTO v_photo_id;

    -- Process each reviewed product.
    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_products)
    LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RAISE EXCEPTION 'Invalid product object';
        END IF;

        v_brand := nullif(trim(v_item->>'brand'), '');
        v_name := nullif(trim(v_item->>'name'), '');
        v_variety := nullif(trim(v_item->>'variety'), '');
        v_package_size :=
            nullif(trim(v_item->>'packageSize'), '');

        IF v_name IS NULL OR length(v_name) > 200
           OR length(coalesce(v_brand, '')) > 200
           OR length(coalesce(v_variety, '')) > 200
           OR length(coalesce(v_package_size, '')) > 100
        THEN
            RAISE EXCEPTION 'Invalid product identification';
        END IF;

        v_identification := v_item->>'identification';

        IF v_identification IS NULL
           OR v_identification NOT IN (
               'readable', 'probable', 'uncertain'
           )
        THEN
            RAISE EXCEPTION 'Invalid identification status';
        END IF;

        -- Validate numeric values and bounding box.
        BEGIN
            v_shelf := (v_item->>'shelfFromTop')::INTEGER;
            v_x := (v_item->'boundingBox'->>'x')::DOUBLE PRECISION;
            v_y := (v_item->'boundingBox'->>'y')::DOUBLE PRECISION;
            v_width :=
                (v_item->'boundingBox'->>'width')::DOUBLE PRECISION;
            v_height :=
                (v_item->'boundingBox'->>'height')::DOUBLE PRECISION;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid product coordinates';
        END;

        IF v_shelf IS NULL OR v_shelf NOT BETWEEN 1 AND 20
           OR v_x IS NULL OR v_y IS NULL
           OR v_width IS NULL OR v_height IS NULL
           OR v_x NOT BETWEEN 0 AND 1
           OR v_y NOT BETWEEN 0 AND 1
           OR v_width <= 0 OR v_height <= 0
           OR v_width > 1 OR v_height > 1
           OR v_x + v_width > 1.000001
           OR v_y + v_height > 1.000001
        THEN
            RAISE EXCEPTION 'Invalid product bounding box';
        END IF;

        -- Reuse a matching catalog entry when available.
        SELECT id INTO v_product_id
        FROM public.products
        WHERE lower(coalesce(brand, '')) =
              lower(coalesce(v_brand, ''))
          AND lower(name) = lower(v_name)
          AND lower(coalesce(variety, '')) =
              lower(coalesce(v_variety, ''))
          AND lower(coalesce(package_size, '')) =
              lower(coalesce(v_package_size, ''))
        ORDER BY created_at
        LIMIT 1;

        IF v_product_id IS NULL THEN
            INSERT INTO public.products (
                brand, name, variety, package_size
            )
            VALUES (
                v_brand, v_name, v_variety, v_package_size
            )
            RETURNING id INTO v_product_id;
        END IF;

        INSERT INTO public.product_observations (
            photo_id,
            product_id,
            shelf_from_top,
            bounding_x,
            bounding_y,
            bounding_width,
            bounding_height,
            identification
        )
        VALUES (
            v_photo_id,
            v_product_id,
            v_shelf,
            v_x,
            v_y,
            v_width,
            v_height,
            v_identification
        );

        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'photoId', v_photo_id,
        'savedCount', v_count
    );
END;
$$;


ALTER FUNCTION "public"."save_reviewed_observations"("p_store_id" "uuid", "p_aisle_number" "text", "p_shelf_side" "text", "p_products" "jsonb") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."product_observations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "photo_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "shelf_from_top" integer NOT NULL,
    "bounding_x" double precision NOT NULL,
    "bounding_y" double precision NOT NULL,
    "bounding_width" double precision NOT NULL,
    "bounding_height" double precision NOT NULL,
    "identification" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_observations_identification_check" CHECK (("identification" = ANY (ARRAY['readable'::"text", 'probable'::"text", 'uncertain'::"text"]))),
    CONSTRAINT "product_observations_shelf_from_top_check" CHECK (("shelf_from_top" > 0))
);


ALTER TABLE "public"."product_observations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand" "text",
    "name" "text" NOT NULL,
    "variety" "text",
    "package_size" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shelf_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "store_id" "uuid" NOT NULL,
    "contributor_id" "uuid" NOT NULL,
    "aisle_number" "text" NOT NULL,
    "shelf_side" "text" NOT NULL,
    "image_path" "text",
    "captured_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "shelf_photos_shelf_side_check" CHECK (("shelf_side" = ANY (ARRAY['Left'::"text", 'Right'::"text"])))
);


ALTER TABLE "public"."shelf_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "city" "text",
    "state" "text",
    "postal_code" "text",
    "latitude" double precision,
    "longitude" double precision,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."stores" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."product_locations" WITH ("security_invoker"='true') AS
 SELECT "p"."id" AS "product_id",
    "p"."name" AS "product_name",
    "p"."brand",
    "p"."variety",
    "p"."package_size",
    "s"."id" AS "store_id",
    "s"."name" AS "store_name",
    "sp"."aisle_number",
    "sp"."shelf_side",
    "po"."shelf_from_top",
    "po"."created_at" AS "last_seen",
    "po"."id" AS "observation_id",
    "sp"."image_path",
    "po"."bounding_x",
    "po"."bounding_y",
    "po"."bounding_width",
    "po"."bounding_height"
   FROM ((("public"."product_observations" "po"
     JOIN "public"."products" "p" ON (("po"."product_id" = "p"."id")))
     JOIN "public"."shelf_photos" "sp" ON (("po"."photo_id" = "sp"."id")))
     JOIN "public"."stores" "s" ON (("sp"."store_id" = "s"."id")));


ALTER VIEW "public"."product_locations" OWNER TO "postgres";


ALTER TABLE ONLY "public"."product_observations"
    ADD CONSTRAINT "product_observations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shelf_photos"
    ADD CONSTRAINT "shelf_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stores"
    ADD CONSTRAINT "stores_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_observations_product" ON "public"."product_observations" USING "btree" ("product_id");



CREATE INDEX "idx_products_brand" ON "public"."products" USING "btree" ("brand");



CREATE INDEX "idx_products_name" ON "public"."products" USING "btree" ("name");



CREATE INDEX "idx_shelf_photos_store" ON "public"."shelf_photos" USING "btree" ("store_id");



ALTER TABLE ONLY "public"."product_observations"
    ADD CONSTRAINT "product_observations_photo_id_fkey" FOREIGN KEY ("photo_id") REFERENCES "public"."shelf_photos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_observations"
    ADD CONSTRAINT "product_observations_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."shelf_photos"
    ADD CONSTRAINT "shelf_photos_contributor_id_fkey" FOREIGN KEY ("contributor_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."shelf_photos"
    ADD CONSTRAINT "shelf_photos_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id");



CREATE POLICY "Authenticated users can read observations" ON "public"."product_observations" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read products" ON "public"."products" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read shelf photos" ON "public"."shelf_photos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read stores" ON "public"."stores" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."product_observations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shelf_photos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stores" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."link_shelf_photo"("p_photo_id" "uuid", "p_image_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."link_shelf_photo"("p_photo_id" "uuid", "p_image_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."link_shelf_photo"("p_photo_id" "uuid", "p_image_path" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_reviewed_observations"("p_store_id" "uuid", "p_aisle_number" "text", "p_shelf_side" "text", "p_products" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_reviewed_observations"("p_store_id" "uuid", "p_aisle_number" "text", "p_shelf_side" "text", "p_products" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_reviewed_observations"("p_store_id" "uuid", "p_aisle_number" "text", "p_shelf_side" "text", "p_products" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."product_observations" TO "anon";
GRANT ALL ON TABLE "public"."product_observations" TO "authenticated";
GRANT ALL ON TABLE "public"."product_observations" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."shelf_photos" TO "anon";
GRANT ALL ON TABLE "public"."shelf_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."shelf_photos" TO "service_role";



GRANT ALL ON TABLE "public"."stores" TO "anon";
GRANT ALL ON TABLE "public"."stores" TO "authenticated";
GRANT ALL ON TABLE "public"."stores" TO "service_role";



GRANT ALL ON TABLE "public"."product_locations" TO "anon";
GRANT ALL ON TABLE "public"."product_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."product_locations" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







