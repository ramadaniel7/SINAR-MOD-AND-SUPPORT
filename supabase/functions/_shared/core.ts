// Shared helpers for Edge Functions (Deno).
import { createClient } from "npm:@supabase/supabase-js@2";

// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by Supabase.
export const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

/** Constant-time string comparison (avoid leaking secret length/prefix via timing). */
export function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const x = enc.encode(a), y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export class HttpError extends Error {
  constructor(public status: number, public code: string, message?: string) {
    super(message ?? code);
  }
}

/** Read a JSON body with a hard size cap. */
export async function readJson(req: Request, maxBytes = 131072): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.length > maxBytes) throw new HttpError(413, "payload_too_large");
  try {
    const v = JSON.parse(text);
    if (v === null || typeof v !== "object" || Array.isArray(v)) throw new Error();
    return v as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "invalid_json");
  }
}

export function requireSecret(req: Request, header: string, envName: string) {
  const expected = Deno.env.get(envName);
  if (!expected || expected.length < 24) {
    // Fail closed: a missing/weak secret must never mean "open".
    throw new HttpError(500, "server_misconfigured");
  }
  const got = req.headers.get(header) ?? "";
  if (!safeEqual(got, expected)) throw new HttpError(401, "unauthorized");
}

export const isUserId = (v: unknown): v is number =>
  typeof v === "number" && Number.isInteger(v) && v > 0 && v < 1e13;

export const str = (v: unknown, min: number, max: number): string | null =>
  typeof v === "string" && v.length >= min && v.length <= max ? v : null;

export function handle(fn: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    try {
      if (req.method !== "POST") throw new HttpError(405, "method_not_allowed");
      return await fn(req);
    } catch (e) {
      if (e instanceof HttpError) return json({ ok: false, error: e.code }, e.status);
      console.error("unhandled", e instanceof Error ? e.message : e);
      return json({ ok: false, error: "internal_error" }, 500);
    }
  };
}

// ---- CORS (hanya untuk fungsi yang dipanggil dari browser, mis. dashboard-api) ----
export function corsHeaders(req: Request): Record<string, string> {
  const allowed = (Deno.env.get("DASHBOARD_ORIGINS") ?? "").split(",").map((x) => x.trim()).filter(Boolean);
  const origin = req.headers.get("origin") ?? "";
  const h: Record<string, string> = { "Vary": "Origin" };
  if (origin && allowed.includes(origin)) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Headers"] = "authorization, content-type";
    h["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    h["Access-Control-Max-Age"] = "600";
  }
  return h;
}
