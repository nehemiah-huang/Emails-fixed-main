import { supabase } from "./supabase-client.js";
import {
  createActionCell,
  createTableButton,
  createRow,
  formatDate,
  localIsoDate,
  renderEmptyRow,
  setMessageText
} from "./admin-table.js";

const APPLICATION_LIMIT = 100;
const MEMBER_LIMIT = 100;

const applicationsBody = document.getElementById("applicationsBody");
const applicationsError = document.getElementById("applicationsError");
const membersBody = document.getElementById("membersBody");
const membersExportButton = document.getElementById("membersExportButton");
const membersError = document.getElementById("membersError");
const reviewDialog = document.getElementById("reviewDialog");
const reviewForm = document.getElementById("reviewForm");
const reviewDetails = document.getElementById("reviewDetails");
const reviewTier = document.getElementById("reviewTier");
const reviewStart = document.getElementById("reviewStart");
const reviewEnd = document.getElementById("reviewEnd");
const reviewError = document.getElementById("reviewError");
const approveButton = document.getElementById("approveButton");
const rejectButton = document.getElementById("rejectButton");
const reviewCancel = document.getElementById("reviewCancel");

const TIER_LABELS = { monthly: "Monthly", annual: "Annual" };
const PRACTICE_LABELS = {
  researcher: "Researcher",
  creative: "Creative",
  spatial_practitioner: "Spatial practitioner",
  collective: "Collective",
  student: "Student",
  partner_institution: "Partner institution",
  other: "Other"
};
const BASED_LABELS = { accra: "Accra", passing_through: "Passing through" };
const MEMBER_EXPORT_HEADER = ["Email", "Tier", "Status", "Started", "Expires"];
const APPLICATION_CACHE = new Map();

function csvCell(value) {
  const text = value == null ? "" : String(value);
  const safeText = /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
  return `"${safeText.replaceAll("\"", "\"\"")}"`;
}

function buildMembersCsv(members) {
  const rows = [
    MEMBER_EXPORT_HEADER,
    ...members.map(member => [
      member.member_email,
      TIER_LABELS[member.membership_tier] ?? "",
      member.membership_status,
      member.started_at,
      member.expires_at
    ])
  ];
  return `\uFEFF${rows.map(row => row.map(csvCell).join(",")).join("\r\n")}\r\n`;
}

function setReviewBusy(isBusy) {
  approveButton.disabled = isBusy;
  rejectButton.disabled = isBusy;
  reviewCancel.disabled = isBusy;
}

function setReviewError(text) {
  reviewError.textContent = text;
  reviewError.hidden = !text;
}

function renderApplicationRow(application) {
  APPLICATION_CACHE.set(application.id, application);

  const row = createRow([
    application.full_name || "—",
    application.applicant_email,
    TIER_LABELS[application.membership_tier] || "—",
    PRACTICE_LABELS[application.practice_type] || application.practice_type || "—",
    BASED_LABELS[application.based_in] || application.based_in || "—",
    formatDate(application.created_at),
    application.status
  ], ["Name", "Email", "Tier", "Practice", "Based in", "Applied", "Status"]);

  const reviewButton = application.status === "pending"
    ? createTableButton("Review", "admin__button admin__button--small", { applicationId: application.id })
    : null;
  const deleteButton = application.status === "pending" || application.status === "rejected"
    ? createTableButton("Delete", "admin__button admin__button--small admin__button--danger", { deleteApplicationId: application.id, applicantEmail: application.applicant_email })
    : null;

  row.append(createActionCell(reviewButton, deleteButton));
  return row;
}

async function loadApplications() {
  const { data, error } = await supabase
    .from("membership_applications")
    .select("id, applicant_email, status, created_at, full_name, phone, practice_type, based_in, about_work, membership_tier")
    .order("created_at", { ascending: false })
    .limit(APPLICATION_LIMIT);

  if (error) throw error;

  if (!data.length) {
    renderEmptyRow(applicationsBody, 8, "No applications yet.");
    return;
  }

  applicationsBody.replaceChildren(...data.map(renderApplicationRow));
}

async function loadMembers() {
  const { data, error } = await supabase
    .from("memberships")
    .select("member_email, membership_tier, membership_status, expires_at")
    .order("created_at", { ascending: false })
    .limit(MEMBER_LIMIT);

  if (error) throw error;

  if (!data.length) {
    renderEmptyRow(membersBody, 4, "No members yet.");
    return;
  }

  membersBody.replaceChildren(...data.map(member => createRow([
    member.member_email,
    TIER_LABELS[member.membership_tier] ?? "—",
    member.membership_status,
    formatDate(member.expires_at)
  ], ["Email", "Tier", "Status", "Ends"])));
}

export async function loadMemberships() {
  await Promise.all([loadApplications(), loadMembers()]);
}

async function exportMembers() {
  membersExportButton.disabled = true;
  setMessageText(membersError, "");

  const { data, error } = await supabase
    .from("memberships")
    .select("member_email, membership_tier, membership_status, started_at, expires_at")
    .order("created_at", { ascending: false });

  membersExportButton.disabled = false;

  if (error) {
    setMessageText(membersError, "Members could not be exported. Please try again.");
    return;
  }

  if (!data.length) {
    setMessageText(membersError, "There are no members to export yet.");
    return;
  }

  const blob = new Blob([buildMembersCsv(data)], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `edan-members-${localIsoDate()}.csv`;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

membersExportButton.addEventListener("click", exportMembers);

async function deleteApplication(button) {
  if (!window.confirm(`Delete the application from ${button.dataset.applicantEmail}? This cannot be undone.`)) return;

  button.disabled = true;
  setMessageText(applicationsError, "");

  const { data, error } = await supabase
    .from("membership_applications")
    .delete()
    .eq("id", button.dataset.deleteApplicationId)
    .select("id");

  if (error || !data.length) {
    setMessageText(applicationsError, error?.message ?? "That application could not be deleted.");
    button.disabled = false;
    return;
  }

  await loadMemberships();
}

function addReviewDetail(label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const detail = document.createElement("dd");
  detail.textContent = value || "—";
  reviewDetails.append(term, detail);
}

function openReview(applicationId) {
  const app = APPLICATION_CACHE.get(applicationId);
  reviewForm.reset();
  setReviewError("");
  reviewDetails.replaceChildren();
  reviewDialog.dataset.applicationId = applicationId;

  if (app) {
    addReviewDetail("Full name", app.full_name);
    addReviewDetail("Email", app.applicant_email);
    addReviewDetail("Phone", app.phone);
    addReviewDetail("What best describes you", PRACTICE_LABELS[app.practice_type] || app.practice_type);
    addReviewDetail("Based in", BASED_LABELS[app.based_in] || app.based_in);
    addReviewDetail("Chosen tier", TIER_LABELS[app.membership_tier] || app.membership_tier);
    addReviewDetail("About their work", app.about_work);
    addReviewDetail("Status", app.status);
    if (app.membership_tier) reviewTier.value = app.membership_tier;
  }

  reviewDialog.showModal();
}

function toStartOfDayIso(dateValue) {
  return new Date(`${dateValue}T00:00:00Z`).toISOString();
}

function toEndOfDayIso(dateValue) {
  return new Date(`${dateValue}T23:59:59Z`).toISOString();
}

applicationsBody.addEventListener("click", (event) => {
  const deleteButton = event.target.closest("button[data-delete-application-id]");
  if (deleteButton) {
    deleteApplication(deleteButton);
    return;
  }

  const button = event.target.closest("button[data-application-id]");
  if (!button) return;
  openReview(button.dataset.applicationId);
});

reviewCancel.addEventListener("click", () => reviewDialog.close());

approveButton.addEventListener("click", async () => {
  if (!reviewForm.reportValidity()) return;

  setReviewError("");
  setReviewBusy(true);

  const { error } = await supabase.rpc("approve_membership_application", {
    p_application_id: reviewDialog.dataset.applicationId,
    p_tier: reviewTier.value,
    p_started_at: toStartOfDayIso(reviewStart.value),
    p_expires_at: toEndOfDayIso(reviewEnd.value)
  });

  setReviewBusy(false);

  if (error) {
    setReviewError("The application could not be approved. Please check the dates and try again.");
    return;
  }

  const applicationId = reviewDialog.dataset.applicationId;
  reviewDialog.close();
  const { error: notificationError } = await supabase.functions.invoke("admin-notifications", {
    body: { type: "approval", application_id: applicationId, site_url: window.location.origin }
  });
  if (notificationError) console.error("Approval notification failed:", notificationError.message);
  await loadMemberships();
});

rejectButton.addEventListener("click", async () => {
  const app = APPLICATION_CACHE.get(reviewDialog.dataset.applicationId);
  const name = app?.full_name || app?.applicant_email || "this applicant";
  if (!window.confirm(`Reject the application from ${name}?`)) return;

  setReviewError("");
  setReviewBusy(true);

  const { error } = await supabase.rpc("reject_membership_application", {
    p_application_id: reviewDialog.dataset.applicationId
  });

  setReviewBusy(false);

  if (error) {
    setReviewError("The application could not be rejected. Please try again.");
    return;
  }

  reviewDialog.close();
  await loadMemberships();
});
