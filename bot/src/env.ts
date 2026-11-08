import "dotenv/config";

function req(name: string): string {
  const v = process.env[name];
  if (!v || v.startsWith("<")) {
    console.error(`[FATAL] Variabel ${name} belum diisi di file .env`);
    process.exit(1);
  }
  return v;
}

export const env = {
  token: req("DISCORD_BOT_TOKEN"),
  appId: req("DISCORD_APPLICATION_ID"),
  guildId: req("DISCORD_GUILD_ID"),
  supabaseUrl: req("SUPABASE_URL"),
  serviceKey: req("SUPABASE_SERVICE_ROLE_KEY"),
  staffKey: req("STAFF_API_KEY"),
};
