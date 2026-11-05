import { supabase } from "./supabase-client.js";

const heroVideo = document.querySelector("#heroMedia video");

if (heroVideo) {
  heroVideo.addEventListener("playing", () => {
    document.getElementById("heroMedia")?.classList.add("video-playing");
    supabase.from("video_views").insert({}).then(({ error }) => {
      if (error) console.error("Could not record video view:", error);
    });
  }, { once: true });

  heroVideo.addEventListener("error", () => {
    document.getElementById("heroMedia")?.classList.remove("video-playing");
  });
}
