import { supabase } from "./supabase-client.js";
import { createActionCell, createRow, createTableButton, renderEmptyRow, setMessageText } from "./admin-table.js";
import { IMAGE_ACCEPT, VIDEO_ACCEPT, uploadSiteImage, uploadSiteVideo } from "./admin-upload.js";

const ITEM_LIMIT = 100;
const IMAGE_REFERENCE_PATTERN = /^(\/images\/[^/\\]+|https:\/\/\S+)$/;
const HTTPS_PATTERN = /^https:\/\/\S+$/;
const MEDIA_REFERENCE_PATTERN = /^(\/(images|videos)\/[^/\\]+|https:\/\/\S+)$/;

const CONTENT_TYPES = {
  gatherings: {
    table: "member_gatherings",
    singular: "gathering",
    fields: [
      { name: "title", label: "Title", type: "text", required: true, maxLength: 160 },
      { name: "gathering_type", label: "Gather page area", type: "select", options: [["upcoming", "Upcoming gathering"], ["past", "Past gathering"], ["moment", "Community moment"]] },
      { name: "category", label: "Category", type: "text", maxLength: 80 },
      { name: "starts_at", label: "Date and time", type: "datetime-local" },
      { name: "location", label: "Location", type: "text", maxLength: 160 },
      { name: "description", label: "Description", type: "textarea", maxLength: 2000 },
      { name: "caption", label: "Archive or moment caption", type: "text", maxLength: 240 },
      { name: "image_path", label: "Photo", type: "image" },
      { name: "registration_url", label: "Event details link (https://)", type: "url" },
      { name: "is_featured", label: "Use as featured gathering", type: "checkbox" },
      { name: "sort_order", label: "Display order (lower first)", type: "number" }
    ]
  },
  research: {
    table: "member_research_items",
    singular: "research item",
    fields: [
      { name: "title", label: "Title", type: "text", required: true, maxLength: 160 },
      { name: "category", label: "Category", type: "text", maxLength: 80 },
      { name: "summary", label: "Summary", type: "textarea", maxLength: 500 },
      { name: "body", label: "Full text (blank lines start new paragraphs)", type: "textarea", maxLength: 20000 },
      { name: "image_path", label: "Photo", type: "image" },
      { name: "read_more_url", label: "Read more link (https://)", type: "url" },
      { name: "sort_order", label: "Display order (lower first)", type: "number" }
    ]
  },
  process: {
    table: "member_process_items",
    singular: "in-process item",
    fields: [
      { name: "title", label: "Title", type: "text", required: true, maxLength: 160 },
      { name: "content_type", label: "In Process format", type: "select", options: [["project", "Project"], ["update", "Project update"], ["video", "Featured video"]] },
      { name: "category", label: "Category", type: "text", maxLength: 80 },
      { name: "summary", label: "Short description", type: "textarea", maxLength: 500 },
      { name: "body", label: "Full text (blank lines start new paragraphs)", type: "textarea", maxLength: 20000 },
      { name: "image_path", label: "Main photo", type: "image" },
      { name: "poster_path", label: "Video thumbnail", type: "image" },
      { name: "updated_label", label: "Date or update label", type: "text", maxLength: 80 },
      { name: "progress_label", label: "Progress label", type: "text", maxLength: 80 },
      { name: "duration_label", label: "Video duration", type: "text", maxLength: 40 },
      { name: "video_path", label: "Video file or URL", type: "video", maxLength: 300 },
      { name: "link_url", label: "Project link (https:// or #anchor)", type: "text", maxLength: 300 },
      { name: "link_label", label: "Project link label", type: "text", maxLength: 80 },
      { name: "is_featured", label: "Use as featured project", type: "checkbox" },
      { name: "sort_order", label: "Display order (lower first)", type: "number" }
    ]
  },
  videos: {
    table: "member_bonus_videos",
    singular: "bonus video",
    fields: [
      { name: "title", label: "Title", type: "text", required: true, maxLength: 160 },
      { name: "description", label: "Description", type: "textarea", maxLength: 2000 },
      { name: "video_path", label: "Video file or URL", type: "video", maxLength: 300 },
      { name: "poster_path", label: "Poster photo", type: "image" },
      { name: "sort_order", label: "Display order (lower first)", type: "number" }
    ]
  }
};

const contentSection = document.getElementById("content");
const contentTypeButtons = document.querySelectorAll("[data-content-type]");
const contentAddButton = document.getElementById("contentAddButton");
const contentBody = document.getElementById("contentBody");
const contentError = document.getElementById("contentError");
const contentDialog = document.getElementById("contentDialog");
const contentDialogHeading = document.getElementById("contentDialogHeading");
const contentForm = document.getElementById("contentForm");
const contentFields = document.getElementById("contentFields");
const contentFormError = document.getElementById("contentFormError");
const contentSave = document.getElementById("contentSave");
const contentCancel = document.getElementById("contentCancel");

function selectedType() {
  return document.querySelector("[data-content-type][aria-pressed='true']")?.dataset.contentType ?? "gatherings";
}

function renderItemRow(item) {
  const row = createRow([
    item.title,
    item.content_type || item.gathering_type || "—",
    item.is_published ? "Published" : "Draft",
    String(item.sort_order)
  ], ["Title", "Format", "Status", "Order"]);

  const editButton = createTableButton("Edit", "admin__button admin__button--small", { editId: item.id });
  const toggleButton = createTableButton(
    item.is_published ? "Unpublish" : "Publish",
    "admin__button admin__button--small",
    { toggleId: item.id, nextPublished: String(!item.is_published) }
  );
  const deleteButton = createTableButton(
    "Delete",
    "admin__button admin__button--small admin__button--danger",
    { deleteId: item.id, itemTitle: item.title }
  );

  row.append(createActionCell(editButton, toggleButton, deleteButton));
  return row;
}

export async function loadMemberContent() {
  const config = CONTENT_TYPES[selectedType()];
  setMessageText(contentError, "");

  const { data, error } = await supabase
    .from(config.table)
    .select(config.table === "member_process_items" ? "id, title, content_type, is_published, sort_order" : config.table === "member_gatherings" ? "id, title, gathering_type, is_published, sort_order" : "id, title, is_published, sort_order")
    .order("sort_order")
    .order("created_at", { ascending: false })
    .limit(ITEM_LIMIT);

  if (error) {
    setMessageText(contentError, "Entries could not be loaded. Please refresh the dashboard.");
    renderEmptyRow(contentBody, 5, "Entries could not be loaded.");
    return;
  }

  if (!data.length) {
    renderEmptyRow(contentBody, 5, "No entries yet.");
    return;
  }

  contentBody.replaceChildren(...data.map(renderItemRow));
}

function toDateTimeLocal(isoValue) {
  const date = new Date(isoValue);
  const localTime = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
}

function fieldValue(field, item) {
  const value = item?.[field.name];
  if (field.type === "datetime-local") return value ? toDateTimeLocal(value) : "";
  if (field.type === "checkbox") return Boolean(value);
  if (value == null) return field.type === "number" ? "0" : "";
  return String(value);
}

function renderVideoField(field, value) {
  const wrapper = document.createElement("div");
  wrapper.className = "admin__image-field";
  const current = document.createElement("input");
  current.type = "text";
  current.name = field.name;
  current.className = "admin__file";
  current.value = value;
  current.placeholder = "Upload a video or enter an https:// URL";
  const file = document.createElement("input");
  file.type = "file";
  file.className = "admin__file";
  file.accept = VIDEO_ACCEPT;
  file.dataset.videoField = field.name;
  const preview = document.createElement("video");
  preview.className = "admin__image-preview";
  preview.controls = true;
  preview.preload = "metadata";
  preview.hidden = !value;
  if (value) preview.src = value;
  file.addEventListener("change", () => {
    const selected = file.files?.[0];
    if (!selected) return;
    preview.src = URL.createObjectURL(selected);
    preview.hidden = false;
  });
  wrapper.append(current, file, preview);
  return wrapper;
}

function renderImageField(field, value) {
  const wrapper = document.createElement("div");
  wrapper.className = "admin__image-field";

  const current = document.createElement("input");
  current.type = "hidden";
  current.name = field.name;
  current.value = value;

  const preview = document.createElement("img");
  preview.className = "admin__image-preview";
  preview.alt = "";
  preview.hidden = !value;
  if (value) preview.src = value;

  const file = document.createElement("input");
  file.type = "file";
  file.id = `content-${field.name}-file`;
  file.className = "admin__file";
  file.accept = IMAGE_ACCEPT;
  file.dataset.imageField = field.name;

  const removeButton = createTableButton("Remove photo", "admin__button admin__button--small", {});
  removeButton.addEventListener("click", () => {
    current.value = "";
    file.value = "";
    preview.hidden = true;
    preview.removeAttribute("src");
  });

  wrapper.append(current, preview, file, removeButton);
  return wrapper;
}

function renderFields(config, item) {
  contentFields.replaceChildren(...config.fields.flatMap(field => {
    const value = fieldValue(field, item);
    const label = document.createElement("label");
    label.className = "admin__label";
    label.textContent = field.label;

    if (field.type === "image") {
      label.htmlFor = `content-${field.name}-file`;
      return [label, renderImageField(field, value)];
    }
    if (field.type === "video") {
      label.htmlFor = `content-${field.name}`;
      return [label, renderVideoField(field, value)];
    }

    label.htmlFor = `content-${field.name}`;
    const input = field.type === "textarea" ? document.createElement("textarea") : field.type === "select" ? document.createElement("select") : document.createElement("input");
    input.id = `content-${field.name}`;
    input.name = field.name;
    input.className = "admin__file";

    if (field.type === "textarea") {
      input.rows = 4;
    } else if (field.type === "select") {
      field.options.forEach(([optionValue, optionLabel]) => {
        const option = document.createElement("option");
        option.value = optionValue;
        option.textContent = optionLabel;
        input.append(option);
      });
    } else {
      input.type = field.type;
    }

    input.required = Boolean(field.required);
    if (field.maxLength) input.maxLength = field.maxLength;
    if (field.type === "checkbox") {
      input.checked = Boolean(value);
    } else {
      input.value = value;
    }

    return [label, input];
  }));
}

function openEditor(type, item = null) {
  const config = CONTENT_TYPES[type];
  contentForm.reset();
  setMessageText(contentFormError, "");
  contentDialog.dataset.contentType = type;
  contentDialog.dataset.itemId = item?.id ?? "";
  contentDialogHeading.textContent = `${item ? "Edit" : "Add"} ${config.singular}`;
  renderFields(config, item);
  contentDialog.showModal();
}

async function readFieldValue(field) {
  if (field.type === "image") {
    const file = contentFields.querySelector(`input[type="file"][data-image-field="${field.name}"]`).files[0];
    if (file) return uploadSiteImage(file);
    return contentFields.querySelector(`input[type="hidden"][name="${field.name}"]`).value;
  }
  if (field.type === "video") {
    const file = contentFields.querySelector(`input[type="file"][data-video-field="${field.name}"]`).files[0];
    if (file) return uploadSiteVideo(file);
    return contentFields.querySelector(`[name="${field.name}"]`).value.trim();
  }

  const input = contentFields.querySelector(`[name="${field.name}"]`);

  if (field.type === "datetime-local") return input.value ? new Date(input.value).toISOString() : null;
  if (field.type === "number") return Math.trunc(Number(input.value)) || 0;
  if (field.type === "checkbox") return input.checked;
  return input.value.trim();
}

async function readPayload(config) {
  const payload = {};
  for (const field of config.fields) {
    payload[field.name] = await readFieldValue(field);
  }
  return payload;
}

function validatePayload(config, payload) {
  for (const field of config.fields) {
    const value = payload[field.name];
    if (field.type === "image" && value && !IMAGE_REFERENCE_PATTERN.test(value)) {
      return "That photo could not be used. Please upload it again.";
    }
    if (field.type === "video" && value && !MEDIA_REFERENCE_PATTERN.test(value)) {
      return "Videos must be uploaded or use an https:// URL.";
    }
    if (field.type === "url" && value && !HTTPS_PATTERN.test(value)) {
      return "Links must start with https://.";
    }
  }
  return "";
}

async function saveEntry(event) {
  event.preventDefault();
  setMessageText(contentFormError, "");

  if (!contentForm.reportValidity()) return;

  const type = contentDialog.dataset.contentType;
  const config = CONTENT_TYPES[type];
  const itemId = contentDialog.dataset.itemId;

  contentSave.disabled = true;

  let payload;
  try {
    payload = await readPayload(config);
  } catch (error) {
    console.error("Content media upload failed:", error);
    setMessageText(contentFormError, "The media could not be uploaded. Please try again.");
    contentSave.disabled = false;
    return;
  }

  const problem = validatePayload(config, payload);
  if (problem) {
    setMessageText(contentFormError, problem);
    contentSave.disabled = false;
    return;
  }

  const request = itemId
    ? supabase.from(config.table).update(payload).eq("id", itemId).select("id")
    : supabase.from(config.table).insert({ ...payload, is_published: false }).select("id");
  const { data, error } = await request;

  contentSave.disabled = false;

  if (error || !data?.length) {
    setMessageText(contentFormError, "That entry could not be saved. Please try again.");
    return;
  }

  contentDialog.close();
  await loadMemberContent();
}

async function togglePublished(button) {
  button.disabled = true;
  setMessageText(contentError, "");

  const { data, error } = await supabase
    .from(CONTENT_TYPES[selectedType()].table)
    .update({ is_published: button.dataset.nextPublished === "true" })
    .eq("id", button.dataset.toggleId)
    .select("id");

  if (error || !data?.length) {
    setMessageText(contentError, error?.message ?? "That entry could not be updated.");
    button.disabled = false;
    return;
  }

  await loadMemberContent();
}

async function deleteEntry(button) {
  if (!window.confirm(`Delete "${button.dataset.itemTitle}"? This cannot be undone.`)) return;

  button.disabled = true;
  setMessageText(contentError, "");

  const { data, error } = await supabase
    .from(CONTENT_TYPES[selectedType()].table)
    .delete()
    .eq("id", button.dataset.deleteId)
    .select("id");

  if (error || !data?.length) {
    setMessageText(contentError, error?.message ?? "That entry could not be deleted.");
    button.disabled = false;
    return;
  }

  await loadMemberContent();
}

async function openExistingEntry(itemId) {
  setMessageText(contentError, "");

  const { data, error } = await supabase
    .from(CONTENT_TYPES[selectedType()].table)
    .select("*")
    .eq("id", itemId)
    .maybeSingle();

  if (error || !data) {
    setMessageText(contentError, error?.message ?? "That entry could not be found.");
    return;
  }

  openEditor(selectedType(), data);
}

contentSection.addEventListener("click", (event) => {
  const typeButton = event.target.closest("[data-content-type]");
  if (typeButton) {
    contentTypeButtons.forEach(other => other.setAttribute("aria-pressed", String(other === typeButton)));
    loadMemberContent();
  }
});

contentAddButton.addEventListener("click", () => openEditor(selectedType()));

contentBody.addEventListener("click", (event) => {
  const editButton = event.target.closest("button[data-edit-id]");
  if (editButton) return openExistingEntry(editButton.dataset.editId);

  const toggleButton = event.target.closest("button[data-toggle-id]");
  if (toggleButton) return togglePublished(toggleButton);

  const deleteButton = event.target.closest("button[data-delete-id]");
  if (deleteButton) deleteEntry(deleteButton);
});

contentForm.addEventListener("submit", saveEntry);
contentCancel.addEventListener("click", () => contentDialog.close());
