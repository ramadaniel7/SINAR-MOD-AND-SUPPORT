"use client";
import { useState } from "react";
import { sb } from "@/lib/supabase";
import { dur, fmt } from "@/lib/format";
import { Badge, Table } from "../ui";

export default function Players({ me }: any) {
  const [q, setQ] = useState(""); const [data, setData] = useState<any>(null); const [busy, setBusy] = useState(false);
  const search = async (e: React.FormEvent) => {
    e.preventDefault(); const term = q.trim(); if (!term) return;
    setBusy(true);
    const isId = /^\d{1,13}$/.test(term);
    const { data: p } = isId ? await sb().from("players").select("*").eq("roblox_user_id", Number(term)).maybeSingle()
      : await sb().from("players").select("*").ilike("username", term.replace(/[%_]/g, "")).limit(1).maybeSingle();
    if (!p) { setData({ none: true }); setBusy(false); return; }
    const [sessions, actions, v] = await Promise.all([
      sb().from("sessions").select("id,job_id,started_at,ended_at").eq("roblox_user_id", p.roblox_user_id).order("started_at", { ascending: false }).limit(8),
      me.perms.has("players.history.read") ? sb().from("moderation_actions").select("id,action_type,status,public_reason,created_at,is_permanent,duration_seconds").eq("target_user_id", p.roblox_user_id).order("created_at", { ascending: false }).limit(15) : Promise.resolve({ data: [] as any[] }),
      me.perms.has("violations.read") ? sb().from("violations").select("id", { count: "exact", head: true }).eq("roblox_user_id", p.roblox_user_id) : Promise.resolve({ count: null as any }),
    ]);
    setData({ p, sessions: sessions.data ?? [], actions: actions.data ?? [], violations: (v as any).count });
    setBusy(false);
  };
  return (
    <>
      <div><h1>Pemain</h1><p className="sub">Cari berdasarkan UserId atau username (pemain yang pernah masuk game).</p></div>
      <form className="row" onSubmit={search}><input style={{ maxWidth: 320 }} value={q} onChange={(e) => setQ(e.target.value)} placeholder="UserId / username" /><button className="btn primary" disabled={busy}>Cari</button></form>
      {data?.none && <div className="glass panel"><p className="sub">Pemain tidak ditemukan di database (belum pernah masuk game).</p></div>}
      {data?.p && <>
        <div className="glass panel"><dl className="kv"><dt>Username</dt><dd>{data.p.username}</dd><dt>UserId</dt><dd>{data.p.roblox_user_id} · <a href={`https://www.roblox.com/users/${data.p.roblox_user_id}/profile`} target="_blank" rel="noreferrer">profil</a></dd>
          <dt>Pertama terlihat</dt><dd>{fmt(data.p.first_seen_at)}</dd><dt>Terakhir terlihat</dt><dd>{fmt(data.p.last_seen_at)}</dd>{data.violations !== null && <><dt>Insiden anti-cheat</dt><dd>{data.violations}</dd></>}</dl></div>
        <div className="glass panel"><h3>Riwayat moderasi</h3><Table head={["Aksi", "Durasi", "Alasan", "Status", "Waktu"]} empty="Bersih." rows={data.actions.map((a: any) => <tr key={a.id}><td>{a.action_type}</td><td>{dur(a)}</td><td>{a.public_reason}</td><td><Badge v={a.status} /></td><td>{fmt(a.created_at)}</td></tr>)} /></div>
        <div className="glass panel"><h3>Sesi terakhir</h3><Table head={["Server", "Mulai", "Selesai"]} empty="Tidak ada." rows={data.sessions.map((s: any) => <tr key={s.id}><td className="mono">{s.job_id}</td><td>{fmt(s.started_at)}</td><td>{s.ended_at ? fmt(s.ended_at) : "online"}</td></tr>)} /></div></>}
    </>
  );
}
