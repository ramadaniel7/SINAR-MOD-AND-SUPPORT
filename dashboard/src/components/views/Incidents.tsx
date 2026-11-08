"use client";
import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { fmt } from "@/lib/format";
import { Badge, Modal, PAGE, Pager, Table } from "../ui";

export default function Incidents() {
  const [rows, setRows] = useState<any[]>([]); const [page, setPage] = useState(1); const [sel, setSel] = useState<any>(null);
  useEffect(() => { void sb().from("violations").select("id,roblox_user_id,detector,severity,score,mode,mitigation,status,evidence,created_at,job_id")
    .order("created_at", { ascending: false }).range((page - 1) * PAGE, page * PAGE).then(({ data }) => setRows(data ?? [])); }, [page]);
  return (
    <>
      <div><h1>Insiden Anti-Cheat</h1><p className="sub">Sinyal otomatis, bukan vonis. Mode detect-only = hanya mencatat.</p></div>
      <div className="glass panel"><Table head={["Pemain", "Detector", "Sev", "Skor", "Mode", "Status", "Waktu"]} empty="Belum ada insiden."
        rows={rows.slice(0, PAGE).map((v) => <tr key={v.id} className="click" onClick={() => setSel(v)}>
          <td>{v.roblox_user_id}</td><td className="mono">{v.detector}</td><td>{v.severity}</td><td>{v.score}</td><td>{v.mode}</td><td><Badge v={v.status} /></td><td>{fmt(v.created_at)}</td></tr>)} /></div>
      <Pager page={page} hasMore={rows.length > PAGE} onPage={setPage} />
      {sel && <Modal onClose={() => setSel(null)}><h1>{sel.detector}</h1>
        <dl className="kv"><dt>Pemain</dt><dd>{sel.roblox_user_id}</dd><dt>Severity / skor</dt><dd>{sel.severity} / {sel.score}</dd><dt>Waktu</dt><dd>{fmt(sel.created_at)}</dd>
          {sel.job_id && <><dt>Server</dt><dd className="mono">{sel.job_id}<br /><code>;goserver {sel.job_id}</code></dd></>}</dl>
        <h3>Bukti</h3><pre>{JSON.stringify(sel.evidence, null, 2)}</pre><div className="row" style={{ marginTop: 12 }}><button className="btn" onClick={() => setSel(null)}>Tutup</button></div></Modal>}
    </>
  );
}
