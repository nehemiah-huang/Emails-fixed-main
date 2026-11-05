import { supabase } from "./supabase-client.js";

const ACCOUNT_PATH = "/login/";
const PLANS = {
  monthly: { label: "Monthly affiliate", amountGhs: 1000 },
  annual: { label: "Annual affiliate", amountGhs: 8000 },
};
const PRACTICE_LABELS = {
  researcher: "Researcher",
  creative: "Creative",
  spatial_practitioner: "Spatial practitioner",
  collective: "Collective",
  student: "Student",
  partner_institution: "Partner institution",
  other: "Other",
};
const BASED_LABELS = {
  accra: "Accra",
  passing_through: "Passing through",
};

const interestDialog = document.getElementById("interestDialog");
const interestForm = document.getElementById("interestForm");
const interestMessage = document.getElementById("interestMessage");
const interestSubmit = document.getElementById("interestSubmit");
const interestClose = document.getElementById("interestClose");

const reviewDialog = document.getElementById("reviewDialog");
const reviewDetails = document.getElementById("reviewDetails");
const reviewClose = document.getElementById("reviewClose");
const reviewDone = document.getElementById("reviewDone");

const statusLine = document.getElementById("payStatus");

function setMessage(element, text) {
  element.textContent = text;
  element.hidden = !text;
}

function setStatus(text, type = "success") {
  statusLine.textContent = text;
  statusLine.className = `pay-status${type === "error" ? " is-error" : ""}`;
  statusLine.hidden = false;
}

function requestedPlan() {
  const plan = new URLSearchParams(window.location.search).get("plan");
  return Object.hasOwn(PLANS, plan) ? plan : null;
}

async function currentSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    console.error("Could not check the current session:", error.message);
    return null;
  }
  return data.session;
}

function addReviewRow(label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const detail = document.createElement("dd");
  detail.textContent = value;
  reviewDetails.append(term, detail);
}

function addReviewWideRow(label, value) {
  const wrap = document.createElement("div");
  wrap.className = "pay__review-wide";
  const term = document.createElement("dt");
  term.textContent = label;
  const detail = document.createElement("dd");
  detail.textContent = value;
  wrap.append(term, detail);
  reviewDetails.append(wrap);
}

function showApplicationReview(form) {
  const fields = form.elements;
  const plan = fields.plan.value;
  reviewDetails.replaceChildren();

  addReviewRow("Full name", fields.fullName.value.trim());
  addReviewRow("Email", fields.email.value);
  addReviewRow("Phone", fields.phone.value.trim());
  addReviewRow("What best describes you", PRACTICE_LABELS[fields.practiceType.value] ?? fields.practiceType.value);
  addReviewRow("Based in", BASED_LABELS[fields.basedIn.value] ?? fields.basedIn.value);
  addReviewRow("Membership", `${PLANS[plan]?.label ?? plan} — GH₵ ${PLANS[plan]?.amountGhs ?? ""}`);
  addReviewWideRow("About your work", fields.aboutWork.value.trim());

  interestDialog.close();
  statusLine.hidden = true;
  reviewDialog.showModal();
}

function openInterestForm(session, plan) {
  interestForm.reset();
  interestDialog.dataset.plan = plan;
  if (plan) interestForm.elements.plan.value = plan;
  setMessage(interestMessage, "");
  statusLine.hidden = true;
  interestDialog.showModal();
}

// Error codes raised on purpose by the submit_membership_interest SQL function
// (RAISE EXCEPTION ...). Their messages are written for people, so we show them.
const FRIENDLY_RPC_CODES = new Set(["P0001", "42501"]);

function userMessageForRpcError(error) {
  if (FRIENDLY_RPC_CODES.has(error.code) && error.message) return error.message;
  if (error.code === "PGRST202" || error.code === "42883") {
    return "The form isn't set up correctly on our side yet. Please contact us.";
  }
  if (!error.code && /failed to fetch|network/i.test(error.message ?? "")) {
    return "We couldn't reach the server. Please check your connection and try again.";
  }
  return "We couldn't save your form. Please check your answers and try again.";
}

// Turns the error from supabase.functions.invoke() into something readable.
// A non-2xx reply arrives as error.context (a Response); our function answers with
// { ok, step, error, reason, hint, ... }. A network/CORS failure has no response at all.
async function describeFunctionError(error) {
  const info = { type: error.name, message: error.message };
  const response = error.context;
  if (response && typeof response.text === "function") {
    info.httpStatus = response.status;
    const raw = await response.text().catch(() => "");
    try {
      const body = JSON.parse(raw);
      info.version = body.version;
      info.step = body.step;
      info.message = body.error ?? info.message;
      info.reason = body.reason;
      info.upstreamStatus = body.upstream_status;
      info.hint = body.hint;
      info.completed = body.completed;
      info.claimReleased = body.claim_released;
      info.detail = body.detail;
    } catch {
      info.body = raw;
    }
  } else if (error.context) {
    info.cause = String(error.context);
    info.message =
      "The request never got a reply (network problem, blocked by CORS, or the function is not deployed). " + error.message;
  }
  return info;
}

// Runs in the background so the applicant is not kept waiting. Failures are logged
// with the step and reason, and the review dialog gets a short, non-technical note.
function requestApplicationEmails() {
  supabase.functions
    .invoke("membership-submission-email")
    .then(async ({ data, error }) => {
      if (error) {
        const info = await describeFunctionError(error);
        const where = (info.step ? `step "${info.step}"` : "request") + (info.version ? ` (function version ${info.version})` : " (no function version: old code or no reply)");
        console.error(
          `[membership] Application emails failed at ${where}: ${info.message}${info.reason ? " - " + info.reason : ""}`,
          info,
        );
        if (info.hint) console.warn("[membership] Hint:", info.hint);
        if (info.claimReleased === false) {
          console.error("[membership] The application is marked as emailed although the emails were not all sent.");
        }
        addReviewRow("Confirmation email", "We couldn't send it just now. Your application was received.");
        return;
      }
      if (data && data.sent === false) {
        console.info("[membership] No emails were sent:", data.reason);
      } else {
        console.info("[membership] Application emails sent.", data);
      }
    })
    .catch((unexpected) => {
      console.error("[membership] Unexpected error while requesting the application emails:", unexpected);
      addReviewRow("Confirmation email", "We couldn't send it just now. Your application was received.");
    });
}

async function handleInterestSubmit(event) {
  event.preventDefault();
  setMessage(interestMessage, "");

  if (!interestForm.reportValidity()) return;

  const session = await currentSession();
  if (!session) {
    window.location.assign(`${ACCOUNT_PATH}?plan=${interestDialog.dataset.plan}`);
    return;
  }

  const fields = interestForm.elements;
  interestSubmit.disabled = true;

  try {
    const { error } = await supabase.rpc("submit_membership_interest", {
      p_full_name: fields.fullName.value.trim(),
      p_email: fields.email.value.trim(),
      p_phone: fields.phone.value.trim(),
      p_practice_type: fields.practiceType.value,
      p_based_in: fields.basedIn.value,
      p_about_work: fields.aboutWork.value.trim(),
      p_commitment_agreed: fields.commitment.checked,
      p_membership_tier: fields.plan.value,
    });

    if (error) {
      console.error('[membership] Step "save form" failed:', {
        message: error.message,
        code: error.code,
        details: error.details,
        hint: error.hint,
      });
      setMessage(interestMessage, userMessageForRpcError(error));
      return;
    }
    console.info("[membership] Form saved.");

    showApplicationReview(interestForm);
    requestApplicationEmails();
  } catch (unexpected) {
    console.error("[membership] Unexpected error while submitting the form:", unexpected);
    setMessage(interestMessage, "Something went wrong. Please check your connection and try again.");
  } finally {
    interestSubmit.disabled = false;
  }
}

async function handlePlanClick(event) {
  event.preventDefault();
  const plan = event.currentTarget.dataset.plan;
  const session = await currentSession();

  if (!session) {
    window.location.assign(`${ACCOUNT_PATH}?plan=${plan}`);
    return;
  }

  openInterestForm(session, plan);
}

document.querySelectorAll("[data-plan]").forEach((button) => {
  button.addEventListener("click", handlePlanClick);
});

interestForm.addEventListener("submit", handleInterestSubmit);
interestClose.addEventListener("click", () => interestDialog.close());
reviewClose.addEventListener("click", () => reviewDialog.close());
reviewDone.addEventListener("click", () => reviewDialog.close());

async function openRequestedPlan() {
  const plan = requestedPlan();
  if (!plan) return;

  const session = await currentSession();
  if (session) {
    openInterestForm(session, plan);
  } else {
    window.location.replace(`${ACCOUNT_PATH}?plan=${plan}`);
  }
}

openRequestedPlan();