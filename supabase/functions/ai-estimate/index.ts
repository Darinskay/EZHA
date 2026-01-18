import { serve } from "https://deno.land/std@0.203.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let payload: RequestPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonError("Invalid JSON payload.");
  }

  const text = typeof payload.text === "string" ? payload.text.trim() : "";
  if (!text) {
    return jsonError("Missing required field: text");
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAiKey) {
    return jsonError("Missing required field: OPENAI_API_KEY");
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const tokenMatch = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!tokenMatch) {
    return jsonError("Missing required field: Authorization");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonError("Missing required field: SUPABASE_URL or SUPABASE_ANON_KEY");
  }

  const authResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${tokenMatch[1]}`,
      apikey: supabaseAnonKey,
    },
  });

  if (!authResponse.ok) {
    return jsonError("Invalid JWT");
  }

  const model = payload.model ??
    Deno.env.get("OPENAI_MODEL") ??
    "gpt-4o-mini";
  const baseUrl = Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1";

  const parsedWeight = extractWeight(text);
  const prompt = buildPrompt(text, parsedWeight);

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openAiKey}`,
    },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            "You are a nutrition assistant. Return only valid JSON. " +
            "If the user description is unclear, estimate a typical portion and explain in notes.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
    }),
  });

  if (!response.ok) {
    return jsonError(`OpenAI request failed with status ${response.status}.`);
  }

  let content = "";
  try {
    const data = await response.json();
    content = data?.choices?.[0]?.message?.content ?? "";
  } catch {
    return jsonError("Invalid OpenAI response.");
  }

  let result: AIResult;
  try {
    result = JSON.parse(content);
  } catch {
    return jsonError("OpenAI returned invalid JSON.");
  }

  if (result.error) {
    return jsonError(result.error);
  }

  const missingFields = requiredFields.filter((field) =>
    result[field] === undefined || result[field] === null
  );
  if (missingFields.length > 0) {
    return jsonError(`Missing required field: ${missingFields.join(", ")}`);
  }

  if (!allowedSources.includes(result.source)) {
    return jsonError("Missing required field: source");
  }

  const normalized = {
    calories: Number(result.calories),
    protein: Number(result.protein),
    carbs: Number(result.carbs),
    fat: Number(result.fat),
    confidence: result.confidence === undefined ? undefined : Number(result.confidence),
    source: result.source,
    notes: result.notes,
  };

  if (
    [normalized.calories, normalized.protein, normalized.carbs, normalized.fat].some((value) =>
      Number.isNaN(value)
    )
  ) {
    return jsonError("OpenAI returned invalid numeric values.");
  }

  return new Response(JSON.stringify(normalized), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

type RequestPayload = {
  text: string;
  inputType?: string;
  model?: string;
};

type AIResult = {
  calories?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
  confidence?: number;
  source?: string;
  notes?: string;
  error?: string;
};

type ParsedWeight = {
  value: number;
  unit: string;
  grams?: number;
};

const requiredFields: Array<keyof AIResult> = [
  "calories",
  "protein",
  "carbs",
  "fat",
  "source",
  "notes",
];

const allowedSources = ["food_photo", "label_photo", "unknown"];

function jsonError(message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function extractWeight(text: string): ParsedWeight | null {
  const match = text.match(
    /(\d+(?:\.\d+)?)\s*(g|gram|grams|kg|oz|lb|lbs|pound|pounds)\b/i,
  );
  if (!match) {
    return null;
  }

  const value = Number(match[1]);
  const unit = match[2].toLowerCase();
  if (Number.isNaN(value)) {
    return null;
  }

  return {
    value,
    unit,
    grams: normalizeToGrams(value, unit),
  };
}

function normalizeToGrams(value: number, unit: string): number | undefined {
  switch (unit) {
    case "g":
    case "gram":
    case "grams":
      return value;
    case "kg":
      return value * 1000;
    case "oz":
      return value * 28.3495;
    case "lb":
    case "lbs":
    case "pound":
    case "pounds":
      return value * 453.592;
    default:
      return undefined;
  }
}

function buildPrompt(text: string, parsedWeight: ParsedWeight | null): string {
  const weightLine = parsedWeight
    ? `Parsed weight: ${parsedWeight.value} ${parsedWeight.unit}` +
      (parsedWeight.grams ? ` (~${Math.round(parsedWeight.grams)} g)` : "")
    : "Parsed weight: none";

  return [
    "Estimate calories and macros for the following food description.",
    "Use the parsed weight if present; otherwise, assume a typical portion.",
    "Return JSON with fields in this exact order:",
    "calories, protein, carbs, fat, confidence, source, notes.",
    "Use source = \"unknown\" for text-only input.",
    `User text: ${text}`,
    weightLine,
  ].join("\n");
}
