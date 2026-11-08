"use client";
import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { fmt } from "@/lib/format";
import { PAGE, Pager, Table } from "../ui";

export default function Audit() {
  const [rows, setRows] = useState<any[]>([]); const [page, setPage] = useState(1);
  useEffect(() => { void sb().from("audit_logs").select("id,occurred_at,actor_type,actor_id,actor_role_key,action,target_type,target_id").order("id", { ascending: false }).range((page - 1) * PAGE, page * PAGE).then(({ data }) => setRows(data ?? [])); }, [page]);
  return (
    <>
      <div><h1>Audit Log</h1><p className="sub">Append-only: tidak bisa diubah atau dihapus lewat aplikasi.</p></div>
      <div className="glass panel"><Table head={["Waktu", "Pelaku", "Role", "Aksi", "Target"]} empty="Belum ada log."
        rows={rows.slice(0, PAGE).map((l) => <tr key={l.id}><td>{fmt(l.occurred_at)}</td><td className="mono">{l.actor_type}<br />{l.actor_id}</td><td>{l.actor_role_key ?? "-"}</td><td className="mono">{l.action}</td><td className="mono">{l.target_type ?? ""} {l.target_id ?? ""}</td></tr>)} /></div>
      <Pager page={page} hasMore={rows.length > PAGE} onPage={setPage} />
    </>
  );
}
