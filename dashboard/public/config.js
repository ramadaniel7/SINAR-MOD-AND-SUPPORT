/*
  KONFIGURASI DASHBOARD — satu-satunya file yang perlu lu edit.
  Isi HANYA nilai PUBLIK. JANGAN PERNAH menaruh kunci rahasia di sini (kunci service role, secret key Supabase, atau kunci bot/staf).
  Dashboard otomatis menolak berjalan, dan build GitHub gagal, kalau mendeteksi kunci rahasia.

  Supabase → Project Settings → API:
    supabaseUrl      = "Project URL"
    supabaseAnonKey  = kunci "anon" / "publishable" (sb_publishable_...)  <- aman publik, dilindungi RLS
*/
window.SMARTAC_CONFIG = {
  supabaseUrl: "https://cfxyebultkgskxowelxn.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmeHllYnVsdGtnc2t4b3dlbHhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwNzk2NjAsImV4cCI6MjEwOTY1NTY2MH0.iO-CybOj1lxmT9ZtsJ9B_HRUU9099f9ckNFZn1mMkgo",
  appName: "SINAR RP Staff",
  accent: "#4f8cff"
};
