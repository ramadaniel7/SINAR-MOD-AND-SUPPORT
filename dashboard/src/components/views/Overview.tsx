"use client";
import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { Tilt } from "../ui";

const count = async (table: string, col: string, val: string) =>
  (await sb().from(table).select("id", { count: "exact", head: true }).eq(col, val)).count ?? null;

export default function Overview({ me }: any) {
  const [s, setS] = useState<Record<string, number | null>>({});
  useEffect(() => {
    (async () => {
      const can = (p: string) => me.perms.has(p);
      const [reports, viol, pend, queue] = await Promise.all([
        can("reports.read") ? count("reports", "status", "open") : null,
        can("violations.read") ? count("violations", "status", "open") : null,
        can("players.history.read") ? count("moderation_actions", "status", "pending_approval") : null,
        can("commands.read") ? count("command_queue", "status", "pending") : null,
      ]);
      setS({ reports, viol, pend, queue });
    })();
  }, [me]);
  const cards = [["Report terbuka", s.reports], ["Insiden belum ditinjau", s.viol], ["Menunggu persetujuan", s.pend], ["Command pending", s.queue]] as const;
  return (
    <>
      <div><h1>Ringkasan</h1><p className="sub">Role lu: <b>{me.role}</b>. Angka “—” = role lu tidak punya izin melihatnya.</p></div>
      <div className="grid4">{cards.map(([l, n]) => <Tilt key={l} className="stat"><div className="n">{n ?? "—"}</div><div className="l">{l}</div></Tilt>)}</div>
      <div className="glass panel"><p className="sub">Anti-cheat berjalan dalam mode <b>detect-only</b>: hanya mencatat &amp; melapor, tidak ada hukuman otomatis. Staf yang memutuskan tindakan.</p></div>
    </>
  );
}
