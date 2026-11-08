"use client";
import { useCallback, useEffect, useState } from "react";
import { callApi, sb } from "@/lib/supabase";
import { CATEGORY, errText, fmt } from "@/lib/format";
import { Badge, Modal, PAGE, Pager, Table, useToast } from "../ui";

export default function Reports({ me }: any) {
  const [rows, setRows] = useState<any[]>([]); const [page, setPage] = useState(1); const [status, setStatus] = useState(""); const [sel, setSel] = useState<any>(null);
  const load = useCallback(async () => {
    let q = sb().from("reports").select("id,report_code,reported_user_id,category,description,status,created_at,source,context,job_id,place_id,resolution")
      .order("created_at", { ascending: false }).range((page - 1) * PAGE, page * PAGE);
    if (status) q = q.eq("status", status);
    const { data } = await q; setRows(data ?? []);
  }, [page, status]);
  useEffect(() => { void load(); }, [load]);
  return (
    <>
      <div><h1>Report Pemain</h1><p className="sub">Report bukan bukti. Identitas pelapor hanya untuk role yang berhak.</p></div>
      <div className="row">{["", "open", "in_review", "resolved", "dismissed"].map((s) => <button key={s} className={`btn ${status === s ? "primary" : ""}`} onClick={() => { setStatus(s); setPage(1); }}>{s || "semua"}</button>)}</div>
      <div className="glass panel"><Table head={["Kode", "Terlapor", "Kategori", "Sumber", "Status", "Waktu"]} empty="Tidak ada report."
        rows={rows.slice(0, PAGE).map((r) => <tr key={r.id} className="click" onClick={() => setSel(r)}>
          <td className="mono">{r.report_code}</td><td>{r.context?.reported_name ?? r.reported_user_id}</td><td>{CATEGORY[r.category] ?? r.category}</td>
          <td>{r.source === "ingame" ? "Dalam game" : "Tiket Discord"}</td><td><Badge v={r.status} /></td><td>{fmt(r.created_at)}</td></tr>)} /></div>
      <Pager page={page} hasMore={rows.length > PAGE} onPage={setPage} />
      {sel && <ReportModal me={me} r={sel} onClose={() => setSel(null)} onChanged={() => { setSel(null); void load(); }} />}
    </>
  );
}

function ReportModal({ me, r, onClose, onChanged }: any) {
  const toast = useToast(); const [ver, setVer] = useState<any>(null); const [reporter, setReporter] = useState<any>(null); const [note, setNote] = useState(""); const [busy, setBusy] = useState(false);
  useEffect(() => {
    void callApi("verify_report", { report_id: r.id }).then(setVer);
    if (me.perms.has("reports.read_reporter")) void sb().from("report_private").select("reporter_user_id,reporter_discord_id").eq("report_id", r.id).maybeSingle().then(({ data }) => setReporter(data));
  }, [r.id, me]);
  const act = async (status: string) => {
    if (status !== "in_review" && note.trim().length < 3) { toast("Isi catatan penyelesaian (min 3 karakter).", "bad"); return; }
    setBusy(true);
    const res = await callApi("resolve_report", { report_id: r.id, status, resolution: note.trim() });
    setBusy(false);
    if (res.ok) { toast("Report diperbarui.", "good"); onChanged(); } else toast(errText(res.error), "bad");
  };
  const c = r.context ?? {};
  return (
    <Modal onClose={onClose}>
      <h1>{r.report_code} <Badge v={r.status} /></h1>
      <dl className="kv">
        <dt>Terlapor</dt><dd>{c.reported_name ?? "-"} ({r.reported_user_id}) · <a href={`https://www.roblox.com/users/${r.reported_user_id}/profile`} target="_blank" rel="noreferrer">profil Roblox</a></dd>
        <dt>Kategori</dt><dd>{CATEGORY[r.category] ?? r.category}</dd><dt>Dibuat</dt><dd>{fmt(r.created_at)}</dd>
        <dt>Deskripsi</dt><dd>{r.description}</dd>
        {reporter && <><dt>Pelapor</dt><dd>{reporter.reporter_user_id ? `Roblox ${reporter.reporter_user_id}` : `Discord ${reporter.reporter_discord_id}`}</dd></>}
        {r.job_id && <><dt>Server (JobId)</dt><dd className="mono">{r.job_id}<br />Di game: <code>;goserver {r.job_id}</code></dd></>}
        {c.reported_pos && <><dt>Posisi terlapor</dt><dd className="mono">{c.reported_pos.join(", ")}</dd></>}
        {r.resolution && <><dt>Catatan penutupan</dt><dd>{r.resolution}</dd></>}
      </dl>
      <h3>Pemeriksaan otomatis</h3>
      {!ver ? <p className="sub">Memeriksa…</p> : !ver.ok ? <p className="sub">Tidak tersedia ({errText(ver.error)}).</p> : (
        <div><p><Badge v={`kecocokan ${ver.level}`} kind={ver.level === "tinggi" ? "good" : ver.level === "sedang" ? "warn" : "bad"} /> <span className="sub">skor {ver.score} — petunjuk, bukan vonis</span></p>
          <pre>{ver.text}</pre></div>)}
      {me.perms.has("reports.review") && ["open", "in_review"].includes(r.status) && <>
        <label style={{ marginTop: 14 }}>Catatan penyelesaian<textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></label>
        <div className="row" style={{ marginTop: 10 }}>
          <button className="btn" disabled={busy} onClick={() => act("in_review")}>Tinjau</button>
          <button className="btn good" disabled={busy} onClick={() => act("resolved")}>Selesai</button>
          <button className="btn danger" disabled={busy} onClick={() => act("dismissed")}>Tolak</button>
          <button className="btn" onClick={onClose}>Tutup</button></div></>}
      {!(me.perms.has("reports.review") && ["open", "in_review"].includes(r.status)) && <div className="row" style={{ marginTop: 12 }}><button className="btn" onClick={onClose}>Tutup</button></div>}
    </Modal>
  );
}
