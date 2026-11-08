import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Cfg } from "./config";

let client: SupabaseClient | null = null;
let cfgRef: Cfg | null = null;
export function initSupabase(cfg: Cfg) {
  cfgRef = cfg;
  client = createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } });
  return client;
}
export const sb = (): SupabaseClient => { if (!client) throw new Error("Supabase belum diinisialisasi"); return client; };

// Aksi berotorisasi dikirim ke Edge Function dengan JWT login staf (tanpa kunci bersama apa pun).
export async function callApi(kind: string, body: Record<string, unknown> = {}): Promise<any> {
  if (!cfgRef) throw new Error("Konfigurasi belum siap");
  const { data } = await sb().auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { ok: false, error: "unauthorized" };
  try {
    const res = await fetch(cfgRef.dashboardApiUrl, {
      method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${token}` }, body: JSON.stringify({ kind, ...body }),
    });
    return await res.json().catch(() => ({ ok: false, error: `bad_response_${res.status}` }));
  } catch { return { ok: false, error: "network" }; }
}
