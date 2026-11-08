// Dashboard STATIS (GitHub Pages): tidak ada server, tidak ada rahasia di build. Semua konfigurasi publik ada di public/config.js.
const basePath = process.env.PAGES_BASE_PATH || ""; // diisi otomatis oleh workflow GitHub Pages (mis. /nama-repo)
/** @type {import('next').NextConfig} */
export default {
  output: "export",
  trailingSlash: true,
  basePath,
  assetPrefix: basePath || undefined,
  images: { unoptimized: true },
  poweredByHeader: false,
  env: { NEXT_BASE_PATH: basePath }, // hanya path situs, BUKAN kunci
};
