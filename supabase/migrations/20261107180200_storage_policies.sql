CREATE POLICY "Users can read their own shelf photos" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'shelf-photos'::"text") AND (("storage"."foldername"("name"))[1] = ( SELECT ("auth"."uid"())::"text" AS "uid"))));



CREATE POLICY "Users can upload their own shelf photos" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'shelf-photos'::"text") AND (("storage"."foldername"("name"))[1] = ( SELECT ("auth"."uid"())::"text" AS "uid")) AND ("lower"("storage"."extension"("name")) = ANY (ARRAY['jpg'::"text", 'jpeg'::"text"]))));



CREATE POLICY "WhereIsIt users can read linked shelf photos" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'shelf-photos'::"text") AND "storage"."allow_only_operation"('object.get_authenticated'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."shelf_photos" "sp"
  WHERE ("sp"."image_path" = "objects"."name")))));

