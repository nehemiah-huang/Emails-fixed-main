  const SUPABASE_URL = "https://afkegyueanjmktgrsnpn.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_AY-KPS5F2lxajImeHv83kw_UmMczbGS";

export const supabase = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

export const SITE_VIDEO_BUCKET = "site-videos";
export const SITE_VIDEO_FOLDER = "hero";
export const SITE_VIDEO_NAME = "edan-hero.mp4";
export const SITE_VIDEO_PATH = `${SITE_VIDEO_FOLDER}/${SITE_VIDEO_NAME}`;
