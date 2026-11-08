"use client";
import { useCallback, useEffect, useState } from "react";
import { callApi, sb } from "@/lib/supabase";
import { dur, errText, fmt } from "@/lib/format";
import { Badge, Modal, PAGE, Pager, Table, useToast } from "../ui";

const DURATIONS: [string, number | null][] = [["1 hari", 86400], ["1 minggu", 604800], ["30 hari", 2592000], ["365 hari", 31536000], ["Permanen (butuh persetujuan)", null]];

export default function Actions({ me }: any) {
  const toast = useToast();
  const [rows, setRows] = useState<any[]>([]); const [page, setPage] = useState(1); const [form, setForm] = useState(false); const [edit, setEdit] = useState<any>(null);
  const load = useCallback(async () => {
    const { data } = await sb().from("moderation_actions").select("id,target_user_id,action_type,duration_seconds,is_permanent,public_reason,status,execution_status,actor_type,actor_id,created_at")
      .order("created_at", { ascending: false }).range((page - 1) * PAGE, page * PAGE);
    setRows(data ?? []);
  }, [page]);
  useEffect(() => { void load(); }, [load]);
  const decide = async (id: string, decision: "approve" | "reject") => {
    if (decision === "approve" && !confirm("Setujui BAN PERMANEN ini?")) return;
    const r = await callApi("decide_action", { action_id: id, decision });
    if (r.ok) { toast(decision === "approve" ? "Disetujui & masuk antrean." : "Ditolak.", "good"); void load(); } else toast(errText(r.error), "bad");
  };
  const canCreate = ["moderation.warn", "moderation.kick", "moderation.ban.temp", "moderation.unban"].some((p) => me.perms.has(p));
  return (
    <>
      <div className="row" style={{ justifyContent: "space-between" }}><div><h1>Moderasi</h1><p className="sub">“Status” = permintaan, “Eksekusi” = hasil nyata di server game. Ban permanen harus disetujui orang lain.</p></div>
        {canCreate && <button className="btn primary" onClick={() => setForm(true)}>+ Buat tindakan</button>}</div>
      <div className="glass panel"><Table head={["Pemain", "Aksi", "Durasi", "Alasan publik", "Status", "Eksekusi", "Waktu", ""]} empty="Belum ada tindakan."
        rows={rows.slice(0, PAGE).map((a) => <tr key={a.id}>
          <td>{a.target_user_id}</td><td>{a.action_type}</td><td>{dur(a)}</td><td style={{ maxWidth: 260 }}>{a.public_reason}</td><td><Badge v={a.status} /></td><td>{a.execution_status}</td><td>{fmt(a.created_at)}</td>
          <td><div className="row">{a.status === "pending_approval" && <>
            {me.perms.has("moderation.ban.perm.approve") && a.actor_id !== me.id && <><button className="btn danger" onClick={() => decide(a.id, "approve")}>Setujui</button><button className="btn" onClick={() => decide(a.id, "reject")}>Tolak</button></>}
            {(a.actor_id === me.id || me.perms.has("moderation.ban.perm.approve")) && <button className="btn" onClick={() => setEdit(a)}>Edit alasan</button>}</>}</div></td></tr>)} /></div>
      <Pager page={page} hasMore={rows.length > PAGE} onPage={setPage} />
      {form && <CreateForm me={me} onClose={() => setForm(false)} onDone={() => { setForm(false); void load(); }} />}
      {edit && <EditReason a={edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); void load(); }} />}
    </>
  );
}

function CreateForm({ me, onClose, onDone }: any) {
  const toast = useToast();
  const [type, setType] = useState("ban"); const [target, setTarget] = useState(""); const [d, setD] = useState("0"); const [pub, setPub] = useState(""); const [priv, setPriv] = useState(""); const [busy, setBusy] = useState(false);
  const allowed = [["warn", "moderation.warn"], ["kick", "moderation.kick"], ["ban", "moderation.ban.temp"], ["unban", "moderation.unban"]].filter(([, p]) => me.perms.has(p));
  const submit = async () => {
    if (pub.trim().length < 3) { toast("Alasan publik minimal 3 karakter.", "bad"); return; }
    const [, secs] = DURATIONS[Number(d)];
    setBusy(true);
    const r = await callApi("create_action", { target: target.trim(), action_type: type, duration_seconds: type === "ban" ? secs : null, permanent: type === "ban" && secs === null,
      public_reason: pub.trim(), private_reason: priv.trim(), idempotency_key: crypto.randomUUID() });
    setBusy(false);
    if (r.ok) { toast(r.status === "pending_approval" ? `Ban permanen ${r.target} dicatat, menunggu persetujuan orang lain.` : `Permintaan untuk ${r.target} diterima.`, "good"); onDone(); } else toast(errText(r.error), "bad");
  };
  return (
    <Modal onClose={onClose}><h1>Buat tindakan</h1>
      <div className="formgrid">
        <label>Jenis<select value={type} onChange={(e) => setType(e.target.value)}>{allowed.map(([t]) => <option key={t}>{t}</option>)}</select></label>
        <label>Username / UserId Roblox<input value={target} onChange={(e) => setTarget(e.target.value)} placeholder="mis. Builderman" /></label>
        {type === "ban" && <label>Durasi<select value={d} onChange={(e) => setD(e.target.value)}>{DURATIONS.map(([l], i) => <option key={l} value={i}>{l}</option>)}</select></label>}
      </div>
      <label style={{ marginTop: 12 }}>Alasan publik (tampil ke pemain &amp; di pengumuman ban)<textarea rows={3} maxLength={400} value={pub} onChange={(e) => setPub(e.target.value)} /></label>
      <label style={{ marginTop: 12 }}>Catatan privat staf (opsional)<textarea rows={2} maxLength={1500} value={priv} onChange={(e) => setPriv(e.target.value)} /></label>
      <div className="row" style={{ marginTop: 14 }}><button className="btn primary" disabled={busy} onClick={submit}>{busy ? "Mengirim…" : "Kirim"}</button><button className="btn" onClick={onClose}>Batal</button></div>
    </Modal>
  );
}

function EditReason({ a, onClose, onDone }: any) {
  const toast = useToast(); const [v, setV] = useState(a.public_reason);
  const save = async () => { const r = await callApi("update_reason", { action_id: a.id, public_reason: v.trim() }); if (r.ok) { toast("Alasan diperbarui.", "good"); onDone(); } else toast(errText(r.error), "bad"); };
  return <Modal onClose={onClose}><h1>Edit alasan publik</h1><p className="sub">Tampil di embed “Player Banned”. Hanya bisa diubah selagi menunggu persetujuan.</p>
    <textarea rows={4} maxLength={400} value={v} onChange={(e) => setV(e.target.value)} /><div className="row" style={{ marginTop: 12 }}><button className="btn primary" onClick={save}>Simpan</button><button className="btn" onClick={onClose}>Batal</button></div></Modal>;
}
