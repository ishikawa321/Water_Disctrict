export function supabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key || key === "YOUR_PUBLIC_PUBLISHABLE_KEY")
    throw new Error("Configure the public Supabase URL and publishable key.");
  return { url, key };
}
