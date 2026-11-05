/* =========================================
   ƐDAN — MEMBER CONTENT
   Gatherings and annual bonus videos.
   Access is enforced by row level security.
   ========================================= */

(() => {
  "use strict";

  const SUPABASE_URL = "https://tqgjgnohqzmvkakqxhcm.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_R6DbjHgjZXrJSwVKLKvh0Q_Ks0BFYEV";

  const gatheringList = document.getElementById("gatheringList");
  const gatheringEmpty = document.getElementById("gatheringEmpty");
  const gatherFeatured = document.getElementById("gatherFeatured");
  const featuredGatherMedia = document.getElementById("featuredGatherMedia");
  const featuredGatherCategory = document.getElementById("featuredGatherCategory");
  const featuredGatherTitle = document.getElementById("featuredGatherTitle");
  const featuredGatherDescription = document.getElementById("featuredGatherDescription");
  const featuredGatherDate = document.getElementById("featuredGatherDate");
  const featuredGatherLocation = document.getElementById("featuredGatherLocation");
  const featuredGatherLink = document.getElementById("featuredGatherLink");
  const gatherArchive = document.getElementById("gatherArchive");
  const gatherMoments = document.getElementById("gatherMoments");
  const videoList = document.getElementById("bonusVideoList");
  const videoEmpty = document.getElementById("bonusVideoEmpty");
  const researchList = document.getElementById("researchList");
  const researchEmpty = document.getElementById("researchEmpty");
  const processFeatured = document.getElementById("processFeatured");
  const featuredProcessMedia = document.getElementById("featuredProcessMedia");
  const featuredProcessCategory = document.getElementById("featuredProcessCategory");
  const featuredProcessTitle = document.getElementById("featuredProcessTitle");
  const featuredProcessSummary = document.getElementById("featuredProcessSummary");
  const featuredProcessUpdated = document.getElementById("featuredProcessUpdated");
  const featuredProcessProgress = document.getElementById("featuredProcessProgress");
  const featuredProcessLink = document.getElementById("featuredProcessLink");
  const processProjectList = document.getElementById("processProjectList");
  const processUpdateList = document.getElementById("processUpdateList");
  const processVideoList = document.getElementById("processVideoList");
  const processEmpty = document.getElementById("processEmpty");
  const readerDialog = document.getElementById("researchReader");
  const readerCategory = document.getElementById("readerCategory");
  const readerTitle = document.getElementById("readerTitle");
  const readerBody = document.getElementById("readerBody");
  const readerClose = document.getElementById("readerClose");

  readerClose.addEventListener("click", () => readerDialog.close());

  const dateFormat = new Intl.DateTimeFormat(undefined, {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
  const gatherDateFormat = new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric"
  });

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function isWebUrl(value) {
    try {
      return ["http:", "https:"].includes(new URL(value).protocol);
    } catch {
      return false;
    }
  }

  function gatherImage(item, className = "") {
    if (!item.image_path) return null;
    const image = element("img", className, item.title);
    image.src = item.image_path;
    image.alt = item.title;
    image.loading = "lazy";
    return image;
  }

  function gatherDate(item) {
    if (!item.starts_at) return "Coming soon";
    return gatherDateFormat.format(new Date(item.starts_at));
  }

  function gatherMeta(item) {
    const meta = element("div", "members__gather-meta");
    meta.append(element("span", "", `▦ ${gatherDate(item)}`));
    if (item.location) meta.append(element("span", "", `⌖ ${item.location}`));
    return meta;
  }

  function gatherLink(item) {
    const link = element("a", "members__gather-link", "Event details");
    const external = Boolean(item.registration_url && isWebUrl(item.registration_url));
    link.href = external ? item.registration_url : "#gather";
    link.append(element("span", "", "→"));
    if (external) {
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    }
    return link;
  }

  function renderGathering(item) {
    const card = element("article", "members__gather-card");
    markContent(card, "gathering", item.id);
    const image = gatherImage(item);
    if (image) card.append(image);
    const copy = element("div", "members__gather-card-copy");
    copy.append(element("span", "members__gather-category", item.category || "Gathering"));
    copy.append(element("h4", "", item.title));
    if (item.description) copy.append(element("p", "", item.description));
    copy.append(gatherMeta(item), gatherLink(item));
    card.append(copy);
    return card;
  }

  function renderArchiveItem(item) {
    const article = element("article", "members__gather-archive-item");
    markContent(article, "gathering", item.id);
    const image = gatherImage(item);
    if (image) article.append(image);
    const copy = element("div", "members__gather-archive-copy");
    copy.append(element("h4", "", item.title));
    copy.append(element("span", "", item.caption || gatherDate(item)));
    article.append(copy);
    return article;
  }

  function renderMoment(item) {
    const figure = element("figure", "members__gather-moment");
    markContent(figure, "gathering", item.id);
    const image = gatherImage(item);
    if (image) figure.append(image);
    if (item.caption) figure.append(element("figcaption", "", item.caption));
    return figure;
  }

  function renderFeaturedGathering(item) {
    gatherFeatured.hidden = false;
    markContent(gatherFeatured, "gathering", item.id);
    featuredGatherMedia.replaceChildren();
    const image = gatherImage(item);
    if (image) featuredGatherMedia.append(image);
    featuredGatherCategory.textContent = item.category || "Featured gathering";
    featuredGatherTitle.textContent = item.title;
    featuredGatherDescription.textContent = item.description || "";
    featuredGatherDate.textContent = `▦ ${gatherDate(item)}`;
    featuredGatherLocation.textContent = item.location ? `⌖ ${item.location}` : "";
    const link = gatherLink(item);
    featuredGatherLink.href = link.href;
    featuredGatherLink.target = link.target;
    featuredGatherLink.rel = link.rel;
    featuredGatherLink.textContent = "Event details →";
  }

  function renderVideo(item) {
    const figure = element("figure", "members__video");
    markContent(figure, "bonus_video", item.id);

    if (item.video_path) {
      const video = element("video");
      video.controls = true;
      video.preload = "metadata";
      video.playsInline = true;
      video.src = item.video_path;
      if (item.poster_path) video.poster = item.poster_path;
      video.addEventListener("error", () => {
        video.replaceWith(element("div", "members__video-placeholder", "This video is unavailable right now."));
      });
      figure.append(video);
    } else {
      const placeholder = element("div", "members__video-placeholder", "Video coming soon");
      placeholder.dataset.videoPath = "/videos/replace-with-bonus-content-video.mp4";
      figure.append(placeholder);
    }

    figure.append(element("h3", "", item.title));

    if (item.description) {
      figure.append(element("p", "", item.description));
    }

    return figure;
  }

  function markContent(node, contentType, contentId) {
    node.dataset.contentType = contentType;
    node.dataset.contentId = contentId;
  }

  async function recordView(client, contentType, contentId) {
    const key = `member-content-view:${contentType}:${contentId}`;
    if (sessionStorage.getItem(key)) return;
    const { error } = await client.from("member_content_views").insert({
      content_type: contentType,
      content_id: contentId
    });
    if (error) {
      console.error("Member activity could not be recorded:", error);
      return;
    }
    sessionStorage.setItem(key, "1");
  }

  function trackVisibleContent(client) {
    const nodes = document.querySelectorAll("[data-content-type][data-content-id]");
    const observer = new IntersectionObserver(entries => {
      entries.filter(entry => entry.isIntersecting).forEach(entry => {
        const node = entry.target;
        observer.unobserve(node);
        recordView(client, node.dataset.contentType, node.dataset.contentId);
      });
    }, { threshold: 0.5 });
    nodes.forEach(node => observer.observe(node));
  }

  function showList(listEl, emptyEl, items, render) {
    listEl.replaceChildren(emptyEl);
    emptyEl.hidden = items.length > 0;
    items.forEach(item => listEl.append(render(item)));
  }

  async function loadGatherings(client) {
    const { data, error } = await client
      .from("member_gatherings")
      .select("id, title, description, starts_at, location, image_path, registration_url, category, gathering_type, is_featured, caption")
      .order("sort_order", { ascending: true })
      .order("starts_at", { ascending: true, nullsFirst: false });

    if (error) throw error;

    const items = data || [];
    const featured = items.find(item => item.is_featured) || items.find(item => item.gathering_type === "upcoming") || items[0];
    const upcoming = items.filter(item => item.gathering_type === "upcoming" && item.id !== featured?.id);
    const archive = items.filter(item => item.gathering_type === "past");
    const moments = items.filter(item => item.gathering_type === "moment");

    gatheringEmpty.hidden = items.length > 0;
    gatherFeatured.hidden = !featured;
    gatheringList.replaceChildren(...upcoming.map(renderGathering));
    gatherArchive.replaceChildren(...archive.map(renderArchiveItem));
    gatherMoments.replaceChildren(...moments.map(renderMoment));
    if (featured) renderFeaturedGathering(featured);
  }

  async function loadBonusVideos(client) {
    const { data, error } = await client
      .from("member_bonus_videos")
      .select("id, title, description, video_path, poster_path")
      .order("sort_order", { ascending: true });

    if (error) throw error;
    const items = data || [];
    showList(videoList, videoEmpty, items, renderVideo);
  }

  function openReader(item) {
    readerCategory.textContent = item.category || "";
    readerCategory.hidden = !item.category;
    readerTitle.textContent = item.title;
    readerBody.replaceChildren(
      ...item.body
        .split(/\n\s*\n/)
        .map(paragraph => paragraph.trim())
        .filter(Boolean)
        .map(paragraph => element("p", "", paragraph))
    );
    readerDialog.showModal();
  }

  function isSafeLink(value) {
    return value.startsWith("#") || value.startsWith("/") || isWebUrl(value);
  }

  function processImage(path, alt = "") {
    if (!path) return null;
    const image = element("img");
    image.src = path;
    image.alt = alt;
    image.loading = "lazy";
    return image;
  }

  function processMeta(item) {
    const meta = element("div", "members__process-meta");
    if (item.updated_label) meta.append(element("span", "", item.updated_label));
    if (item.progress_label) meta.append(element("span", "", item.progress_label));
    return meta;
  }

  function processLink(item) {
    if (!item.link_url || !isSafeLink(item.link_url)) return null;
    const link = element("a", "members__process-link", item.link_label || "View project");
    link.href = item.link_url;
    if (isWebUrl(item.link_url)) {
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    }
    link.append(element("span", "", "→"));
    return link;
  }

  function renderProject(item) {
    const article = element("article", "members__process-project");
    markContent(article, "process", item.id);
    const image = processImage(item.image_path, item.title);
    if (image) article.append(image);

    const copy = element("div", "members__process-project-copy");
    if (item.category) copy.append(element("span", "members__process-category", item.category));
    copy.append(element("h4", "", item.title));
    if (item.summary) copy.append(element("p", "", item.summary));
    copy.append(processMeta(item));
    const link = processLink(item);
    if (link) copy.append(link);
    article.append(copy);
    return article;
  }

  function renderUpdate(item) {
    const article = element("article", "members__process-update");
    markContent(article, "process", item.id);
    const image = processImage(item.image_path, item.title);
    if (image) article.append(image);

    const copy = element("div", "members__process-update-copy");
    if (item.category) copy.append(element("span", "members__process-category", item.category));
    copy.append(element("h4", "", item.title));
    if (item.summary) copy.append(element("p", "", item.summary));
    copy.append(processMeta(item));
    article.append(copy);
    return article;
  }

  function renderProcessVideo(item) {
    const figure = element("article", "members__process-video");
    markContent(figure, "process", item.id);
    const media = element("div", "members__process-video-media");
    if (item.video_path) {
      const video = element("video");
      video.controls = true;
      video.preload = "metadata";
      video.playsInline = true;
      video.src = item.video_path;
      if (item.poster_path || item.image_path) video.poster = item.poster_path || item.image_path;
      media.append(video);
    } else {
      const image = processImage(item.poster_path || item.image_path, item.title);
      if (image) media.append(image);
      media.append(element("span", "members__process-video-unavailable", "Video coming soon"));
    }
    if (item.duration_label) media.append(element("span", "members__process-duration", item.duration_label));
    figure.append(media);
    const copy = element("div", "members__process-video-copy");
    copy.append(element("h4", "", item.title));
    if (item.summary) copy.append(element("p", "", item.summary));
    figure.append(copy);
    return figure;
  }

  function renderFeatured(item) {
    processFeatured.hidden = false;
    markContent(processFeatured, "process", item.id);
    featuredProcessMedia.replaceChildren();
    const image = processImage(item.image_path, item.title);
    if (image) featuredProcessMedia.append(image);
    featuredProcessCategory.textContent = item.category || "Featured project";
    featuredProcessTitle.textContent = item.title;
    featuredProcessSummary.textContent = item.summary || "";
    featuredProcessUpdated.textContent = item.updated_label || "";
    featuredProcessProgress.textContent = item.progress_label || "";
    const link = processLink(item);
    featuredProcessLink.hidden = !link;
    if (link) {
      featuredProcessLink.href = link.href;
      featuredProcessLink.textContent = `${item.link_label || "View project"} →`;
      if (link.target) {
        featuredProcessLink.target = link.target;
        featuredProcessLink.rel = link.rel;
      }
    }
  }

  function renderResearch(item) {
    const article = element("article", "members__research-item");
    markContent(article, "research", item.id);

    if (item.image_path) {
      const image = element("img");
      image.src = item.image_path;
      image.alt = "";
      image.loading = "lazy";
      article.append(image);
    }

    const copy = element("div", "members__research-item-copy");

    if (item.category) {
      copy.append(element("span", "members__research-category", item.category));
    }

    copy.append(element("h3", "", item.title));

    if (item.summary) {
      copy.append(element("p", "", item.summary));
    }

    if (item.body) {
      const button = element("button", "members__research-link", "Read");
      button.type = "button";
      button.addEventListener("click", () => openReader(item));
      copy.append(button);
    }

    if (item.read_more_url && isWebUrl(item.read_more_url)) {
      const link = element("a", "members__research-link", "Read more ↗");
      link.href = item.read_more_url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      copy.append(link);
    }

    article.append(copy);
    return article;
  }

  async function loadProcess(client) {
    const { data, error } = await client
      .from("member_process_items")
      .select("id, title, summary, body, category, image_path, content_type, is_featured, progress_label, updated_label, video_path, poster_path, duration_label, link_url, link_label")
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: false });

    if (error) throw error;

    const items = data || [];
    const projects = items.filter(item => item.content_type === "project");
    const updates = items.filter(item => item.content_type === "update");
    const videos = items.filter(item => item.content_type === "video");
    const featured = projects.find(item => item.is_featured) || projects[0];

    processEmpty.hidden = items.length > 0;
    processFeatured.hidden = !featured;
    processProjectList.replaceChildren(...projects.filter(item => item.id !== featured?.id).map(renderProject));
    processUpdateList.replaceChildren(...updates.map(renderUpdate));
    processVideoList.replaceChildren(...videos.map(renderProcessVideo));
    if (featured) renderFeatured(featured);
  }

  async function loadResearch(client) {
    const { data, error } = await client
      .from("member_research_items")
      .select("id, title, summary, category, body, image_path, read_more_url")
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: false });

    if (error) throw error;
    const items = data || [];
    if (!items.length) return;
    researchEmpty.hidden = true;
    showList(researchList, researchEmpty, items, renderResearch);
  }

  async function init() {
    if (!window.supabase) return;

    const client = window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY
    );

    const { data: sessionData, error: sessionError } =
      await client.auth.getSession();

    if (sessionError || !sessionData.session) return;

    const results = await Promise.allSettled([
      loadGatherings(client),
      loadBonusVideos(client),
      loadResearch(client),
      loadProcess(client)
    ]);

    if (results[0].status === "rejected") {
      console.error("Gatherings failed to load:", results[0].reason);
      gatheringEmpty.textContent = "We couldn't load gatherings. Please refresh the page.";
    }
    if (results[1].status === "rejected") {
      console.error("Bonus videos failed to load:", results[1].reason);
      videoEmpty.hidden = false;
      videoEmpty.textContent = "We couldn't load bonus videos. Please refresh the page.";
    }
    if (results[2].status === "rejected") {
      console.error("Research failed to load:", results[2].reason);
      researchEmpty.textContent = "We couldn't load research. Please refresh the page.";
    }
    if (results[3].status === "rejected") {
      console.error("In process failed to load:", results[3].reason);
      processEmpty.textContent = "We couldn't load this section. Please refresh the page.";
    }
    trackVisibleContent(client);
  }

  init().catch(error => {
    console.error("Member content error:", error);
  });
})();
