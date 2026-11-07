
import { withSupabase } from "npm:@supabase/server@1";

const MODEL = "gpt-5.4";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

const schema = {
  type: "object",
  properties: {
    products: {
      type: "array",
      items: {
        type: "object",
        properties: {
          brand: { type: ["string", "null"] },
          name: { type: "string" },
          variety: { type: ["string", "null"] },
          packageSize: { type: ["string", "null"] },
          shelfFromTop: { type: "integer" },
          identification: {
            type: "string",
            enum: ["readable", "probable", "uncertain"],
          },
          boundingBox: {
            type: "object",
            properties: {
              x: { type: "number" },
              y: { type: "number" },
              width: { type: "number" },
              height: { type: "number" },
            },
            required: ["x", "y", "width", "height"],
            additionalProperties: false,
          },
        },
        required: [
          "brand",
          "name",
          "variety",
          "packageSize",
          "shelfFromTop",
          "identification",
          "boundingBox",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["products"],
  additionalProperties: false,
};


const instructions = `
You are analyzing a grocery-store shelf photograph.

Your tasks are:
1. Identify visible grocery products.
2. Determine which shelf each product occupies.
3. Locate each product accurately within the image.

PRODUCT IDENTIFICATION

- Identify the brand and product name.
- Identify the variety only when supported by readable
  text or clear visual evidence.
- Include package size only when clearly readable.
- Never invent product details.
- Use null when information cannot be determined.
- Use "readable" when identifying text is clearly legible.
- Use "probable" when identification relies partly on
  recognizable packaging.
- Use "uncertain" when identification is ambiguous.
- Include only products actually visible in the image.

SHELF IDENTIFICATION

- Identify horizontal shelf rows from top to bottom.
- The top visible shelf row is shelf 1.
- Shelf numbers increase downward.
- A product must be assigned to the shelf row on which
  it physically rests.
- Do not confuse the shelf below a product with the shelf
  supporting that product.

BOUNDING BOXES

Bounding-box accuracy is extremely important.

Each bounding box must describe the actual visible
product packaging, not its surrounding shelf area.

Coordinates use the ORIGINAL IMAGE dimensions:

- x: fractional distance from the LEFT edge to the
  LEFT edge of the product.
- y: fractional distance from the TOP edge to the
  TOP edge of the product.
- width: fractional width of the product.
- height: fractional height of the product.

All coordinates must be normalized between 0 and 1.

For example:
- x = 0.25 means 25% across the image from the left.
- y = 0.20 means 20% down from the top.
- width = 0.10 means 10% of the image width.
- height = 0.15 means 15% of the image height.

IMPORTANT BOUNDING-BOX RULES

1. Locate the TOP edge of the visible product first.
2. Locate the BOTTOM edge of the visible product.
3. Locate the LEFT and RIGHT edges.
4. Calculate the normalized bounding rectangle.

5. The bounding box must not extend into the shelf
   below the product.

6. Do not include empty shelf space, price labels,
   shelf brackets, or neighboring products.

7. Boxes should fit closely around the visible
   packaging.

8. If identical products have multiple adjacent
   facings, consolidate them into one rectangle
   covering only that contiguous group.

9. Do not combine products on different shelf rows.

10. All bounding boxes must satisfy:
    x >= 0
    y >= 0
    width > 0
    height > 0
    x + width <= 1
    y + height <= 1

11. Before returning the result, check every box
    against the image. Verify that it surrounds
    the intended product rather than the shelf
    below it.

Return the structured product data.
`;


function jsonResponse(
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

function validImage(base64: string): boolean {
  return (
    base64.length > 0 &&
    base64.length <= MAX_IMAGE_BYTES * 4 / 3 + 8 &&
    /^[A-Za-z0-9+/]*={0,2}$/.test(base64) &&
    base64.length % 4 === 0
  );
}

export default {
  fetch: withSupabase(
    { auth: "user" },
    async (req: Request) => {
      if (req.method !== "POST") {
        return jsonResponse(
          { error: "POST required" },
          405,
        );
      }

      const apiKey = Deno.env.get("OPENAI_API_KEY");

      if (!apiKey) {
        return jsonResponse(
          { error: "OpenAI API key is not configured" },
          500,
        );
      }

      let body: {
        imageBase64?: string;
        mimeType?: string;
      };

      try {
        body = await req.json();
      } catch {
        return jsonResponse(
          { error: "Invalid JSON request" },
          400,
        );
      }

      const { imageBase64, mimeType } = body;

      if (
        typeof imageBase64 !== "string" ||
        !validImage(imageBase64) ||
        !["image/jpeg", "image/png", "image/webp"]
          .includes(mimeType ?? "")
      ) {
        return jsonResponse(
          { error: "Invalid or oversized image" },
          400,
        );
      }

      try {
        const openAIResponse = await fetch(
          "https://api.openai.com/v1/responses",
          {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${apiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model: MODEL,
              store: false,
              input: [
                {
                  role: "user",
                  content: [
                    {
                      type: "input_text",
                      text: instructions,
                    },
                    {
                      type: "input_image",
                      image_url:
                        `data:${mimeType};base64,${imageBase64}`,
                      detail: "high",
                    },
                  ],
                },
              ],
              text: {
                format: {
                  type: "json_schema",
                  name: "grocery_recognition",
                  strict: true,
                  schema,
                },
              },
            }),
          },
        );

        if (!openAIResponse.ok) {
          console.error(
            "OpenAI request failed:",
            openAIResponse.status,
          );

          return jsonResponse(
            { error: "Product recognition failed" },
            502,
          );
        }

        const result = await openAIResponse.json();

        const outputText = result.output
          ?.flatMap((item: {
            content?: Array<{
              type: string;
              text?: string;
            }>;
          }) => item.content ?? [])
          .filter((item: {
            type: string;
          }) => item.type === "output_text")
          .map((item: {
            text?: string;
          }) => item.text ?? "")
          .join("");

        if (!outputText) {
          return jsonResponse(
            { error: "No recognition data returned" },
            502,
          );
        }

        const parsed = JSON.parse(outputText);

        if (!Array.isArray(parsed.products)) {
          throw new Error("Unexpected recognition format");
        }

        return jsonResponse({
          model: MODEL,
          productCount: parsed.products.length,
          products: parsed.products,
        });
      } catch (error) {
        console.error("Recognition error:", error);

        return jsonResponse(
          { error: "Unable to process photograph" },
          500,
        );
      }
    },
  ),
};
