  const SUPABASE_URL = "https://tqgjgnohqzmvkakqxhcm.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_R6DbjHgjZXrJSwVKLKvh0Q_Ks0BFYEV";

export const supabase = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

export const SITE_VIDEO_BUCKET = "site-videos";
export const SITE_VIDEO_FOLDER = "hero";
export const SITE_VIDEO_NAME = "edan-hero.mp4";
export const SITE_VIDEO_PATH = `${SITE_VIDEO_FOLDER}/${SITE_VIDEO_NAME}`;
