
import { createClient } from "npm:@supabase/supabase-js@2";

type BoundingBox = {
  x: number;
  y: number;
  width: number;
  height: number;
};

type ReviewedProduct = {
  brand: string | null;
  name: string;
  variety: string | null;
  packageSize: string | null;
  shelfFromTop: number;
  identification: "readable" | "probable" | "uncertain";
  boundingBox: BoundingBox;
};

type SaveRequest = {
  storeId: string;
  aisleNumber: string;
  shelfSide: "Left" | "Right";
  products: ReviewedProduct[];
};

function response(
  data: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function optionalString(value: unknown): boolean {
  return (
    value === null ||
    value === undefined ||
    (typeof value === "string" && value.length <= 200)
  );
}

function validProduct(value: unknown): boolean {
  if (!value || typeof value !== "object") {
    return false;
  }

  const p = value as Record<string, unknown>;

  if (!optionalString(p.brand) ||
      !optionalString(p.variety) ||
      !optionalString(p.packageSize) ||
      typeof p.name !== "string" ||
      p.name.trim().length === 0 ||
      p.name.length > 200 ||
      !Number.isInteger(p.shelfFromTop) ||
      (p.shelfFromTop as number) < 1 ||
      (p.shelfFromTop as number) > 20 ||
      !["readable", "probable", "uncertain"]
        .includes(String(p.identification))) {
    return false;
  }

  const box = p.boundingBox as BoundingBox | undefined;

  if (!box || typeof box !== "object") {
    return false;
  }

  const values = [box.x, box.y, box.width, box.height];

  if (!values.every(
    (n) => typeof n === "number" &&
      Number.isFinite(n)
  )) {
    return false;
  }

  return (
    box.x >= 0 &&
    box.y >= 0 &&
    box.width > 0 &&
    box.height > 0 &&
    box.x + box.width <= 1.000001 &&
    box.y + box.height <= 1.000001
  );
}

function validRequest(value: unknown): value is SaveRequest {
  if (!value || typeof value !== "object") {
    return false;
  }

  const r = value as Record<string, unknown>;

  return (
    typeof r.storeId === "string" &&
    UUID_PATTERN.test(r.storeId) &&
    typeof r.aisleNumber === "string" &&
    r.aisleNumber.trim().length >= 1 &&
    r.aisleNumber.trim().length <= 20 &&
    (r.shelfSide === "Left" || r.shelfSide === "Right") &&
    Array.isArray(r.products) &&
    r.products.length >= 1 &&
    r.products.length <= 100 &&
    r.products.every(validProduct)
  );
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return response({ error: "POST required" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseKey =
    Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

  if (!supabaseURL || !supabaseKey) {
    return response(
      { error: "Backend configuration missing" },
      500,
    );
  }

  const authorization =
    req.headers.get("Authorization") ?? "";

  if (!authorization.startsWith("Bearer ")) {
    return response(
      { error: "Authentication required" },
      401,
    );
  }

  const token = authorization.slice(7).trim();

  if (!token) {
    return response(
      { error: "Authentication required" },
      401,
    );
  }

  // Use the signed-in user's token, not a service-role key.
  const supabase = createClient(
    supabaseURL,
    supabaseKey,
    {
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );

  try {
    // Verify the user session with Supabase Auth.
    const { data: userData, error: authError } =
      await supabase.auth.getUser(token);

    if (authError || !userData.user) {
      return response(
        { error: "Invalid or expired session" },
        401,
      );
    }

    const contentLength = Number(
      req.headers.get("content-length") ?? 0
    );

    if (contentLength > 128 * 1024) {
      return response(
        { error: "Request too large" },
        413,
      );
    }

    let body: unknown;

    try {
      const raw = await req.text();

      if (new TextEncoder().encode(raw).length >
          128 * 1024) {
        return response(
          { error: "Request too large" },
          413,
        );
      }

      body = JSON.parse(raw);
    } catch {
      return response(
        { error: "Invalid JSON request" },
        400,
      );
    }

    if (!validRequest(body)) {
      return response(
        { error: "Invalid contribution data" },
        400,
      );
    }

    const { data, error } = await supabase.rpc(
      "save_reviewed_observations",
      {
        p_store_id: body.storeId,
        p_aisle_number: body.aisleNumber.trim(),
        p_shelf_side: body.shelfSide,
        p_products: body.products,
      },
    );

    if (error) {
      console.error("Database save error:", error.code);
      return response(
        { error: "Unable to save contribution" },
        500,
      );
    }

    return response({
      success: true,
      photoId: data.photoId,
      savedCount: data.savedCount,
    });
  } catch (error) {
    console.error("Unexpected save error:", error);
    return response(
      { error: "Unable to process contribution" },
      500,
    );
  }
});
