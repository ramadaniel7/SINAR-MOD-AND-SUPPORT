"use client";
import { useCallback, useEffect, useState } from "react";
import { readConfig, type Cfg } from "@/lib/config";
import { callApi, initSupabase, sb } from "@/lib/supabase";
import { startFaviconAnimation } from "@/lib/favicon";
import { ToastProvider, Tilt } from "./ui";
import Logo3D from "./Logo3D";
import Overview from "./views/Overview";
import Reports from "./views/Reports";
import Incidents from "./views/Incidents";
import Actions from "./views/Actions";
import Players from "./views/Players";
import Audit from "./views/Audit";

export type Me = { id: string; role: string; perms: Set<string> };
const NAV = [
  { id: "overview", label: "Ringkasan", icon: "◈", perm: null },
  { id: "reports", label: "Report", icon: "⚑", perm: "reports.read" },
  { id: "incidents", label: "Insiden Anti-Cheat", icon: "⚠", perm: "violations.read" },
  { id: "actions", label: "Moderasi", icon: "⚔", perm: "players.history.read" },
  { id: "players", label: "Pemain", icon: "☺", perm: "players.read" },
  { id: "audit", label: "Audit Log", icon: "☰", perm: "audit.read" },
];
const base = process.env.NEXT_BASE_PATH || "";

const Stage = () => <div className="stage" aria-hidden><div className="orb a" /><div className="orb b" /><div className="floor" /></div>;

export default function App() {
  const [phase, setPhase] = useState<"loading" | "setup" | "login" | "denied" | "app">("loading");
  const [problem, setProblem] = useState("");
  const [cfg, setCfg] = useState<Cfg | null>(null);
  const [me, setMe] = useState<Me | null>(null);
  const [route, setRoute] = useState("overview");

  const loadMe = useCallback(async () => {
    const r = await callApi("me");
    if (!r.ok) { setPhase("denied"); return; }
    setMe({ id: r.member_id, role: r.role, perms: new Set<string>(r.perms) });
    setPhase("app");
  }, []);

  useEffect(() => {
    const { cfg: c, problem: p } = readConfig();
    if (!c) { setProblem(p ?? "Konfigurasi tidak valid."); setPhase("setup"); return; }
    setCfg(c);
    document.documentElement.style.setProperty("--accent", c.accent);
    document.title = `${c.appName} • Staff`;
    initSupabase(c);
    const stopFav = startFaviconAnimation(c.accent);
    sb().auth.getSession().then(({ data }) => (data.session ? loadMe() : setPhase("login")));
    const { data: sub } = sb().auth.onAuthStateChange((_evt, session) => {
      if (!session) { setMe(null); setPhase("login"); }
      else setTimeout(() => void loadMe(), 0); // jangan await Supabase di dalam callback (hindari deadlock)
    });
    return () => { stopFav(); sub.subscription.unsubscribe(); };
  }, [loadMe]);

  useEffect(() => {
    const on = () => setRoute(location.hash.replace(/^#\/?/, "") || "overview");
    on(); window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);

  if (phase === "loading") return <><Stage /><div className="center"><Logo3D /></div></>;

  if (phase === "setup") return (
    <><Stage /><div className="center"><div className="glass card">
      <Logo3D /><h1>Konfigurasi diperlukan</h1>
      <div className="warnbox">{problem}</div>
      <ol className="steps">
        <li>Buka <code>dashboard/public/config.js</code>.</li>
        <li>Isi <code>supabaseUrl</code> dan <code>supabaseAnonKey</code> (kunci <b>anon/publishable</b>, aman publik).</li>
        <li><b>Jangan</b> pernah menaruh <code>service_role</code> / <code>sb_secret_</code>.</li>
        <li>Commit &amp; push; GitHub Pages akan memperbarui otomatis.</li>
      </ol></div></div></>
  );

  if (phase === "login" || phase === "denied") return <><Stage /><div className="center"><LoginCard cfg={cfg!} denied={phase === "denied"} /></div></>;

  const visible = NAV.filter((n) => !n.perm || me!.perms.has(n.perm));
  const VIEWS: Record<string, any> = { overview: Overview, reports: Reports, incidents: Incidents, actions: Actions, players: Players, audit: Audit };
  const allowed = visible.some((n) => n.id === route) ? route : "overview";
  const Active = VIEWS[allowed];

  return (
    <ToastProvider>
      <Stage />
      <div className="shell">
        <aside className="glass side">
          <div className="brand"><img src={`${base}/favicon.svg`} alt="" />{cfg!.appName}</div>
          <nav className="nav">{visible.map((n) => <a key={n.id} href={`#/${n.id}`} className={allowed === n.id ? "on" : ""}><span>{n.icon}</span>{n.label}</a>)}</nav>
          <div className="me">Role: <b>{me!.role}</b><br /><button className="btn" style={{ marginTop: 8 }} onClick={() => sb().auth.signOut()}>Keluar</button></div>
        </aside>
        <main><Active me={me!} /></main>
      </div>
    </ToastProvider>
  );
}

function LoginCard({ cfg, denied }: { cfg: Cfg; denied: boolean }) {
  const [email, setEmail] = useState(""); const [password, setPassword] = useState(""); const [err, setErr] = useState(""); const [busy, setBusy] = useState(false);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); setBusy(true); setErr("");
    const { error } = await sb().auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) setErr("Email atau password salah.");
  };
  return (
    <Tilt className="card">
      <Logo3D />
      <div><h1>{cfg.appName}</h1><p className="sub">Panel staf • Smart Anticheat</p></div>
      {denied && <div className="warnbox">Akun ini belum terdaftar sebagai staf aktif. Minta Founder menjalankan <code>staff_roster.sql</code> dan menautkan email lu.<br /><button className="btn" style={{ marginTop: 8 }} onClick={() => sb().auth.signOut()}>Ganti akun</button></div>}
      {!denied && <form onSubmit={submit}>
        <label>Email<input type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} /></label>
        <label>Password<input type="password" required autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} /></label>
        {err && <div className="warnbox" role="alert">{err}</div>}
        <button className="btn primary" disabled={busy}>{busy ? "Masuk…" : "Masuk"}</button>
      </form>}
    </Tilt>
  );
}
