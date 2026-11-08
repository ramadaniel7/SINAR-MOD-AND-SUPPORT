import "./globals.css";
import type { Metadata } from "next";

const base = process.env.NEXT_BASE_PATH || "";
export const metadata: Metadata = { title: "Smart Anticheat • Staff", robots: { index: false, follow: false } };

const CSP = [
  "default-src 'self'", "script-src 'self' 'unsafe-inline'", "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https://*.supabase.co https://tr.rbxcdn.com", "connect-src 'self' https://*.supabase.co",
  "font-src 'self'", "object-src 'none'", "base-uri 'self'", "form-action 'self'",
].join("; ");

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <head>
        <meta httpEquiv="Content-Security-Policy" content={CSP} />
        <meta name="referrer" content="no-referrer" />
        <meta name="theme-color" content="#0b0e17" />
        <link rel="icon" type="image/svg+xml" href={`${base}/favicon.svg`} />
        {/* konfigurasi publik (runtime) — dimuat sebelum aplikasi */}
        <script src={`${base}/config.js`} />
      </head>
      <body>{children}</body>
    </html>
  );
}
