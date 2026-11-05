import { supabase } from "./supabase-client.js";

const SITE_IMAGES_BUCKET = "site-images";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_EXTENSIONS = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/avif": "avif",
  "image/gif": "gif"
};

const VIDEO_EXTENSIONS = {
  "video/mp4": "mp4",
  "video/webm": "webm"
};
const MAX_VIDEO_BYTES = 30 * 1024 * 1024;

export const IMAGE_ACCEPT = Object.keys(IMAGE_EXTENSIONS).join(",");
export const VIDEO_ACCEPT = Object.keys(VIDEO_EXTENSIONS).join(",");

export function imageFileProblem(file) {
  if (!IMAGE_EXTENSIONS[file.type]) return "Choose a JPEG, PNG, WebP, AVIF or GIF photo.";
  if (file.size > MAX_IMAGE_BYTES) return "Photos must be 5 MB or smaller.";
  return "";
}

export async function uploadSiteImage(file) {
  const problem = imageFileProblem(file);
  if (problem) throw new Error(problem);

  const path = `${crypto.randomUUID()}.${IMAGE_EXTENSIONS[file.type]}`;
  const storage = supabase.storage.from(SITE_IMAGES_BUCKET);
  const { error } = await storage.upload(path, file, { contentType: file.type, cacheControl: "3600" });

  if (error) {
    console.error("Photo upload failed:", error);
    throw new Error("The photo could not be uploaded. Please try again.");
  }

  return storage.getPublicUrl(path).data.publicUrl;
}

export async function uploadSiteVideo(file) {
  if (!VIDEO_EXTENSIONS[file.type]) throw new Error("Choose an MP4 or WebM video.");
  if (file.size > MAX_VIDEO_BYTES) throw new Error("Videos must be 30 MB or smaller.");

  const path = `members/${crypto.randomUUID()}.${VIDEO_EXTENSIONS[file.type]}`;
  const storage = supabase.storage.from("site-videos");
  const { error } = await storage.upload(path, file, { contentType: file.type, cacheControl: "3600" });

  if (error) {
    console.error("Video upload failed:", error);
    throw new Error("The video could not be uploaded. Please try again.");
  }

  return storage.getPublicUrl(path).data.publicUrl;
}
