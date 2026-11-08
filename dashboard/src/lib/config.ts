export type Cfg = { supabaseUrl: string; supabaseAnonKey: string; dashboardApiUrl: string; appName: string; accent: string };

// Membaca public/config.js (runtime, bukan env build). Menolak kunci rahasia supaya tidak pernah terekspos di web.
export function readConfig(): { cfg?: Cfg; problem?: string } {
  const c = (window as any).SMARTAC_CONFIG;
  if (!c) return { problem: "File config.js tidak termuat. Pastikan public/config.js ada." };
  const url = String(c.supabaseUrl ?? "").trim().replace(/\/$/, "");
  const key = String(c.supabaseAnonKey ?? "").trim();
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)) return { problem: "supabaseUrl belum diisi / formatnya salah (contoh: https://abcd1234.supabase.co)." };
  if (key.length < 20 || key.includes("ISI_")) return { problem: "supabaseAnonKey belum diisi." };
  if (key.startsWith("sb_secret_")) return { problem: "⛔ KUNCI RAHASIA terdeteksi di config.js (sb_secret_...). Hapus SEGERA dan ganti (rotate) kunci itu di Supabase. Pakai kunci publishable/anon." };
  const parts = key.split(".");
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
      if (payload.role === "service_role") return { problem: "⛔ KUNCI service_role terdeteksi di config.js. Hapus SEGERA dan ganti (rotate) kunci itu di Supabase. Pakai kunci anon/publishable." };
    } catch { /* bukan JWT: lanjut */ }
  }
  return { cfg: { supabaseUrl: url, supabaseAnonKey: key, dashboardApiUrl: String(c.dashboardApiUrl || `${url}/functions/v1/dashboard-api`), appName: String(c.appName || "Smart Anticheat"), accent: String(c.accent || "#4f8cff") } };
}
