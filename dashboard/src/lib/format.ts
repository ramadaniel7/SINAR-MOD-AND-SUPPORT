export const fmt = (iso?: string | null) => (iso ? new Date(iso).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" }) : "-");
export const dur = (a: any) => (a.is_permanent ? "Permanen" : a.duration_seconds ? `${Math.round(a.duration_seconds / 86400)} hari` : "-");
export const CATEGORY: Record<string, string> = { cheating: "Cheat / Exploit", fail_roleplay: "Fail Roleplay", harassment: "Pelecehan", other: "Lainnya" };
export const ERR: Record<string, string> = {
  forbidden: "Role lu tidak punya izin untuk ini.", not_staff: "Akun ini belum terdaftar sebagai staf aktif.", unauthorized: "Sesi habis, login ulang.",
  player_not_found: "Akun Roblox tidak ditemukan.", target_outranks_actor: "Target setara/lebih tinggi dari role lu.", duration_exceeds_role_limit: "Durasi melebihi batas role lu.",
  duration_not_allowed: "Durasi tidak diizinkan.", invalid_reason: "Alasan harus 3-400 karakter (catatan privat 3-2000).", not_pending: "Sudah diproses.",
  self_approval_not_allowed: "Tidak boleh menyetujui permintaan sendiri.", not_open: "Sudah diproses.", network: "Gagal terhubung ke backend.", target_not_online: "Pemain tidak online (kick/warn butuh online).",
};
export const errText = (c?: string) => ERR[c ?? ""] ?? `Gagal (${c ?? "unknown"}).`;
