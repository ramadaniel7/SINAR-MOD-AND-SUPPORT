// Favicon beranimasi: perisai berputar 3D di tab browser (dijeda saat tab tersembunyi / mode kurangi gerak).
export function startFaviconAnimation(accent: string): () => void {
  if (typeof document === "undefined" || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return () => {};
  const link = (document.querySelector("link[rel='icon']") as HTMLLinkElement) ?? Object.assign(document.createElement("link"), { rel: "icon" });
  if (!link.parentNode) document.head.appendChild(link);
  const original = link.href;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 64;
  const ctx = canvas.getContext("2d");
  if (!ctx) return () => {};
  let t = 0;
  const draw = () => {
    t += 0.2;
    const sx = Math.max(0.12, Math.abs(Math.cos(t)));
    ctx.clearRect(0, 0, 64, 64);
    ctx.save();
    ctx.translate(32, 32);
    ctx.scale(sx, 1);
    const g = ctx.createLinearGradient(-22, -28, 22, 28);
    g.addColorStop(0, "#9cc2ff"); g.addColorStop(1, accent);
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.moveTo(0, -28); ctx.lineTo(22, -20); ctx.lineTo(22, -2); ctx.bezierCurveTo(22, 14, 12, 24, 0, 29);
    ctx.bezierCurveTo(-12, 24, -22, 14, -22, -2); ctx.lineTo(-22, -20); ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = "#fff"; ctx.lineWidth = 5; ctx.lineCap = "round"; ctx.lineJoin = "round";
    ctx.beginPath(); ctx.moveTo(-10, 1); ctx.lineTo(-3, 9); ctx.lineTo(11, -8); ctx.stroke();
    ctx.restore();
    link.type = "image/png";
    link.href = canvas.toDataURL("image/png");
  };
  let timer: number | undefined;
  const run = () => { if (timer === undefined) timer = window.setInterval(draw, 150); };
  const stop = () => { if (timer !== undefined) { clearInterval(timer); timer = undefined; } };
  const onVis = () => (document.hidden ? stop() : run());
  document.addEventListener("visibilitychange", onVis);
  run();
  return () => { stop(); document.removeEventListener("visibilitychange", onVis); link.type = "image/svg+xml"; link.href = original; };
}
