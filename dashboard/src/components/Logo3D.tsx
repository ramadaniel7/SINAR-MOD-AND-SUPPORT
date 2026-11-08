"use client";
import { useRef } from "react";

const Shield = ({ o = 1 }: { o?: number }) => (
  <svg viewBox="0 0 64 64" style={{ opacity: o }}><defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#9cc2ff" /><stop offset="1" stopColor="var(--accent)" /></linearGradient></defs>
    <path d="M32 4 54 12v18c0 14-9 25-22 30C19 55 10 44 10 30V12z" fill="url(#lg)" /><path d="M22 32l7 7 14-15" fill="none" stroke="#fff" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" /></svg>
);

// Logo perisai 3D: beberapa lapisan pada kedalaman berbeda + miring mengikuti mouse (memakai gambar favicon yang sama).
export default function Logo3D() {
  const ref = useRef<HTMLDivElement>(null);
  const move = (e: React.MouseEvent) => {
    const r = e.currentTarget.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
    ref.current?.style.setProperty("--rx", `${-y * 25 - 8}deg`);
    ref.current?.style.setProperty("--ry", `${x * 35}deg`);
  };
  return (
    <div className="scene" onMouseMove={move} aria-hidden>
      <div className="logo3d" ref={ref}>
        {[-24, -16, -8, 0, 8, 16, 24].map((z, i) => <div className="layer" key={z} style={{ transform: `translateZ(${z}px)` }}><Shield o={i === 6 ? 1 : 0.55} /></div>)}
      </div>
    </div>
  );
}
