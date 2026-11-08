// Gaya embed seragam. Merah = ban/penindakan, hijau = kasus selesai, biru = informasi, oranye/kuning = peringatan.
export const COLOR = { red: 0xed4245, green: 0x57f287, blue: 0x5865f2, orange: 0xe67e22, yellow: 0xfee75c, gray: 0x95a5a6 } as const;
export const ts = (iso: string | number | Date, style: "R" | "f" | "F" | "D" = "f") =>
  `<t:${Math.floor(new Date(iso).getTime() / 1000)}:${style}>`;
export const clip = (s: unknown, n: number) => String(s ?? "").slice(0, n);
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
