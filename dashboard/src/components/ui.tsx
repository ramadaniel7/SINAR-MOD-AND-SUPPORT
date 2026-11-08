"use client";
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from "react";

// ---------- toast ----------
type Toast = { id: number; msg: string; kind: "good" | "bad" | "" };
const ToastCtx = createContext<(msg: string, kind?: "good" | "bad") => void>(() => {});
export const useToast = () => useContext(ToastCtx);
export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Toast[]>([]);
  const push = useCallback((msg: string, kind: "good" | "bad" | "" = "") => {
    const id = Date.now() + Math.random();
    setItems((x) => [...x.slice(-3), { id, msg, kind }]);
    setTimeout(() => setItems((x) => x.filter((t) => t.id !== id)), 4500);
  }, []);
  return <ToastCtx.Provider value={push}>{children}<div className="toasts" role="status" aria-live="polite">{items.map((t) => <div key={t.id} className={`toast ${t.kind}`}>{t.msg}</div>)}</div></ToastCtx.Provider>;
}

// ---------- kartu miring 3D mengikuti kursor ----------
export function Tilt({ children, className = "" }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const move = (e: React.MouseEvent) => {
    const el = ref.current; if (!el) return;
    const r = el.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
    el.style.transform = `perspective(700px) rotateY(${x * 9}deg) rotateX(${-y * 9}deg) translateZ(6px)`;
  };
  return <div ref={ref} className={`glass tilt ${className}`} onMouseMove={move} onMouseLeave={() => { if (ref.current) ref.current.style.transform = ""; }}>{children}</div>;
}

export function Badge({ v, kind }: { v: string; kind?: "good" | "bad" | "warn" | "info" }) {
  const map: Record<string, string> = { resolved: "good", executed: "good", reviewed: "good", approved: "info", queued: "info", in_review: "info", open: "warn", pending_approval: "warn", failed: "bad", rejected: "bad", confirmed: "bad", dismissed: "", expired: "" };
  return <span className={`badge ${kind ?? map[v] ?? ""}`}>{v}</span>;
}

export function Modal({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  return <div className="overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}><div className="glass modal" role="dialog" aria-modal="true">{children}</div></div>;
}

export function Table({ head, rows, empty = "Belum ada data." }: { head: string[]; rows: ReactNode[]; empty?: string }) {
  return (
    <div className="tablewrap"><table><thead><tr>{head.map((h) => <th key={h}>{h}</th>)}</tr></thead>
      <tbody>{rows.length ? rows : <tr><td colSpan={head.length} className="empty">{empty}</td></tr>}</tbody></table></div>
  );
}

export function Pager({ page, hasMore, onPage }: { page: number; hasMore: boolean; onPage: (p: number) => void }) {
  return <div className="pager"><button className="btn" disabled={page <= 1} onClick={() => onPage(page - 1)}>← Sebelumnya</button><span>Halaman {page}</span><button className="btn" disabled={!hasMore} onClick={() => onPage(page + 1)}>Berikutnya →</button></div>;
}

export const PAGE = 20;
