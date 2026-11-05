// membership-submission-email
//
// Sends two emails after someone submits the membership interest form:
//   1. a confirmation to the applicant
//   2. a notification to the Ɛdan team
//
// Every step reports its own error. On failure the response (and the function
// log) says WHICH step failed and WHY, for example:
//   { ok: false, step: "send_applicant_email",
//     error: "Sending the applicant confirmation email failed",
//     reason: "Resend rejected the email (403): validation_error: You can only send testing emails to your own email address ...",
//     hint: "...", completed: ["config", "auth", "load_application", "claim_application"] }
//
// Optional secrets (Supabase dashboard > Edge Functions > Secrets):
//   EMAIL_FROM             sender, e.g.  Ɛdan <hello@edan.studio>  (domain must be verified in Resend)
//   ADMIN_TO / ADMIN_CC    who gets the team notification (comma-separated; ADMIN_CC may be empty).
//                          While Resend is in testing mode set ADMIN_TO to the Resend account owner's email.
//                          Secrets cannot be empty, so write none in ADMIN_CC for "no CC".
//   EXPOSE_ERROR_DETAILS   set to "true" only while diagnosing failures; it defaults to hidden.
//                          The function log always keeps the full detail.

// Bump this when you change the function. It is returned in every reply and logged, so you can tell which deploy is live.
const VERSION = "2026-11-05.2";

const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "Ɛdan <info@edan.studio>";

// Who receives the team notification. Comma-separated lists. The word "none" means nobody (use it for ADMIN_CC).
function addressList(name: string, fallback: string): string[] {
  const value = (Deno.env.get(name) ?? fallback).trim();
  if (value.toLowerCase() === "none") return [];
  return value
    .split(",")
    .map((address) => address.trim())
    .filter(Boolean);
}
function exposeDetails(): boolean {
  return (Deno.env.get("EXPOSE_ERROR_DETAILS") ?? "false").toLowerCase() === "true";
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// "2026-11-05T15:35:09.626Z" -> "5 November 2026, 15:35 UTC"
function formatSubmitted(iso: string | null): string {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  const day = date.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
  const time = date.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "UTC" });
  return `${day}, ${time} UTC`;
}

function tierLabel(tier: string | null): string {
  return tier === "annual" ? "Annual affiliate" : tier === "monthly" ? "Monthly affiliate" : tier ?? "Not specified";
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const PRACTICE_LABELS: Record<string, string> = {
  researcher: "Researcher",
  creative: "Creative",
  spatial_practitioner: "Spatial practitioner",
  collective: "Collective",
  student: "Student",
  partner_institution: "Partner institution",
  other: "Other",
};

const BASED_IN_LABELS: Record<string, string> = {
  accra: "Based in Accra",
  passing_through: "Passing through Accra",
};

type Application = {
  id: string;
  applicant_email: string;
  full_name: string | null;
  phone: string | null;
  practice_type: string | null;
  based_in: string | null;
  about_work: string | null;
  submitted_at: string | null;
  submission_emailed_at: string | null;
  membership_tier: string | null;
};

type Email = { to: string[]; cc?: string[]; replyTo?: string; subject: string; html: string; text: string; idempotencyKey: string };

// ---------------------------------------------------------------------------
// Step-aware errors
// ---------------------------------------------------------------------------

type StepName =
  | "request"
  | "config"
  | "auth"
  | "load_application"
  | "claim_application"
  | "send_applicant_email"
  | "send_admin_email"
  | "release_claim"
  | "unexpected";

const STEP_LABELS: Record<StepName, string> = {
  request: "The request was not valid",
  config: "The function is not configured",
  auth: "The sign-in check failed",
  load_application: "Loading the application failed",
  claim_application: "Marking the application as emailed failed",
  send_applicant_email: "Sending the applicant confirmation email failed",
  send_admin_email: "Sending the team notification email failed",
  release_claim: "Undoing the emailed marker failed",
  unexpected: "Something unexpected went wrong",
};

class StepError extends Error {
  step: StepName;
  reason: string;
  httpStatus: number;
  upstreamStatus?: number;
  detail?: string;
  hint?: string;

  constructor(
    step: StepName,
    reason: string,
    httpStatus: number,
    extra: { upstreamStatus?: number; detail?: string; hint?: string } = {},
  ) {
    super(`${STEP_LABELS[step]}: ${reason}`);
    this.step = step;
    this.reason = reason;
    this.httpStatus = httpStatus;
    this.upstreamStatus = extra.upstreamStatus;
    this.detail = extra.detail;
    this.hint = extra.hint;
  }
}

function errText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

// Reads an error body from Resend, PostgREST or the auth service and pulls out a readable line.
async function readUpstream(response: Response): Promise<{ text: string; summary: string }> {
  const text = (await response.text().catch(() => "")).slice(0, 1000);
  let summary = text;
  try {
    const parsed = JSON.parse(text) as Record<string, unknown>;
    const message = parsed.message ?? parsed.msg ?? parsed.error_description ?? parsed.error;
    const code = parsed.code ?? parsed.name;
    if (typeof message === "string") summary = code ? `${code}: ${message}` : message;
  } catch {
    // not JSON, keep the raw text
  }
  return { text, summary: summary || "empty response" };
}

function hintFor(step: StepName, status: number | undefined, summary: string): string | undefined {
  if (step === "send_applicant_email" || step === "send_admin_email") {
    if (status === 401 || status === 403) {
      return "Resend refused the request. If the message mentions testing emails or a domain, verify your domain in Resend and set the EMAIL_FROM secret to an address on it. If it says the API key is invalid, check the RESEND_API_KEY secret.";
    }
    if (status === 422) return "Resend says the sender or a recipient address is not valid. Check EMAIL_FROM and the recipient addresses.";
    if (status === 429) return "Resend's rate limit was reached. Try again shortly.";
    return undefined;
  }
  if (step === "load_application" || step === "claim_application" || step === "release_claim") {
    if (/does not exist|42703|42P01|PGRST20\d|schema cache/i.test(summary)) {
      return "A column or table this function needs is missing in the database. Make sure the SQL that adds membership_applications.submission_emailed_at has been run.";
    }
    if (status === 401 || status === 403) return "The database rejected the service role key. Check the SUPABASE_SERVICE_ROLE_KEY secret.";
    return undefined;
  }
  if (step === "auth" && status === 401) {
    return "The user's access token was rejected. Ask the user to sign in again.";
  }
  return undefined;
}

function log(message: string, extra?: unknown) {
  if (extra === undefined) console.log(`[membership-email] ${message}`);
  else console.log(`[membership-email] ${message}`, extra);
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

function readConfig(): { supabaseUrl: string; serviceKey: string; resendKey: string } {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const missing = [
    !supabaseUrl && "SUPABASE_URL",
    !serviceKey && "SUPABASE_SERVICE_ROLE_KEY",
    !resendKey && "RESEND_API_KEY",
  ].filter(Boolean) as string[];
  if (missing.length > 0) {
    throw new StepError("config", `Missing secret(s): ${missing.join(", ")}`, 500, {
      hint:
        "Add the missing secret(s) under Edge Functions > Secrets, then redeploy. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are normally provided automatically; RESEND_API_KEY you add yourself.",
    });
  }
  return { supabaseUrl: supabaseUrl!, serviceKey: serviceKey!, resendKey: resendKey! };
}

async function userFromToken(
  supabaseUrl: string,
  serviceKey: string,
  accessToken: string,
): Promise<{ id: string; email: string }> {
  let response: Response;
  try {
    response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(10000),
    });
  } catch (error) {
    throw new StepError("auth", `Could not reach the auth service: ${errText(error)}`, 502);
  }
  if (!response.ok) {
    const { text, summary } = await readUpstream(response);
    throw new StepError("auth", `The sign-in token was not accepted (${response.status}): ${summary}`, 401, {
      upstreamStatus: response.status,
      detail: text,
      hint: hintFor("auth", response.status, summary),
    });
  }
  const user = (await response.json().catch(() => null)) as { id?: unknown; email?: unknown } | null;
  if (!user || typeof user.id !== "string") {
    throw new StepError("auth", "The auth service did not return a user id", 401);
  }
  if (typeof user.email !== "string" || !user.email.includes("@")) {
    throw new StepError("auth", "The signed-in account has no email address", 401, {
      hint: "Confirmations are sent to the email on the signed-in account. Sign in with an email-based account.",
    });
  }
  return { id: user.id, email: user.email };
}

async function loadLatestPendingApplication(
  supabaseUrl: string,
  serviceKey: string,
  userId: string,
): Promise<Application | null> {
  const select = "id,applicant_email,full_name,phone,practice_type,based_in,about_work,submitted_at,submission_emailed_at,membership_tier";
  const query = new URLSearchParams({
    user_id: `eq.${userId}`,
    status: "eq.pending",
    order: "created_at.desc",
    limit: "1",
    select,
  });
  let response: Response;
  try {
    response = await fetch(`${supabaseUrl}/rest/v1/membership_applications?${query}`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      signal: AbortSignal.timeout(10000),
    });
  } catch (error) {
    throw new StepError("load_application", `Could not reach the database: ${errText(error)}`, 502);
  }
  if (!response.ok) {
    const { text, summary } = await readUpstream(response);
    throw new StepError("load_application", `The database returned ${response.status}: ${summary}`, 500, {
      upstreamStatus: response.status,
      detail: text,
      hint: hintFor("load_application", response.status, summary),
    });
  }
  const rows = (await response.json().catch(() => null)) as Application[] | null;
  return rows?.[0] ?? null;
}

async function setEmailedAt(
  step: "claim_application" | "release_claim",
  supabaseUrl: string,
  serviceKey: string,
  applicationId: string,
  value: string | null,
  onlyIfUnsent: boolean,
): Promise<boolean> {
  const filter = onlyIfUnsent ? "&submission_emailed_at=is.null" : "";
  let response: Response;
  try {
    response = await fetch(
      `${supabaseUrl}/rest/v1/membership_applications?id=eq.${encodeURIComponent(applicationId)}${filter}&select=id`,
      {
        method: "PATCH",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify({ submission_emailed_at: value }),
        signal: AbortSignal.timeout(10000),
      },
    );
  } catch (error) {
    throw new StepError(step, `Could not reach the database: ${errText(error)}`, 502);
  }
  if (!response.ok) {
    const { text, summary } = await readUpstream(response);
    throw new StepError(step, `The database returned ${response.status}: ${summary}`, 500, {
      upstreamStatus: response.status,
      detail: text,
      hint: hintFor(step, response.status, summary),
    });
  }
  const rows = (await response.json().catch(() => [])) as unknown[];
  return rows.length > 0;
}

async function sendEmail(step: "send_applicant_email" | "send_admin_email", resendKey: string, email: Email) {
  let response: Response;
  try {
    response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": email.idempotencyKey,
      },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: email.to,
        subject: email.subject,
        html: email.html,
        text: email.text,
        cc: email.cc,
        reply_to: email.replyTo,
      }),
      signal: AbortSignal.timeout(10000),
    });
  } catch (error) {
    throw new StepError(step, `Could not reach Resend: ${errText(error)}`, 502);
  }
  if (!response.ok) {
    const { text, summary } = await readUpstream(response);
    throw new StepError(step, `Resend rejected the email (${response.status}): ${summary}`, 502, {
      upstreamStatus: response.status,
      detail: text,
      hint: hintFor(step, response.status, summary),
    });
  }
}

// ---------------------------------------------------------------------------
// Email content
// ---------------------------------------------------------------------------

function buildApplicantEmail(application: Application, accountEmail: string): Email {
  const name = application.full_name ?? "there";
  const tier = tierLabel(application.membership_tier);
  const submitted = formatSubmitted(application.submitted_at);
  const subject = "Your Ɛdan affiliate application receipt";
  const text = [
    `Hi ${name},`,
    "",
    "Thank you for applying to become an Ɛdan affiliate. This email confirms that we received your application.",
    "",
    `Membership option: ${tier}`,
    `Submitted: ${submitted}`,
    "Status: Under review",
    "",
    "We will be in touch as your application moves forward.",
    "",
    "With thanks,",
    "The Ɛdan team",
  ].join("\n");
  const rows = [
    ["Membership option", tier],
    ["Submitted", submitted],
    ["Status", "Under review"],
  ] as const;
  const rowsHtml = rows
    .map(([label, value]) => `<tr><td style="padding:10px 16px;color:#6B5E50;border-bottom:1px solid #E8DCC8">${escapeHtml(label)}</td><td style="padding:10px 16px;color:#2B2118;font-weight:600;border-bottom:1px solid #E8DCC8">${escapeHtml(value)}</td></tr>`)
    .join("");
  const html = `
<div style="background:#F2EAD9;padding:24px 12px;font-family:Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">
    <div style="background:#DDB29A;padding:24px 28px">
      <div style="font-size:28px;font-weight:700;color:#2B2118">Ɛdan</div>
      <div style="font-size:14px;color:#2B2118">Affiliate application receipt</div>
    </div>
    <div style="padding:28px">
      <p style="margin:0 0 12px;font-size:16px;line-height:1.5;color:#2B2118">Hi ${escapeHtml(name)},</p>
      <p style="margin:0 0 16px;font-size:16px;line-height:1.5;color:#2B2118">Thank you for applying to become an Ɛdan affiliate. This email confirms that we received your application.</p>
      <table cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;font-size:15px">${rowsHtml}</table>
      <p style="margin:24px 0 0;font-size:14px;line-height:1.5;color:#6B5E50">We will be in touch as your application moves forward.</p>
    </div>
  </div>
</div>`;
  return { to: [accountEmail], subject, html, text, idempotencyKey: `${application.id}-applicant` };
}

function buildAdminEmail(application: Application, accountEmail: string): Email {
  const practice = PRACTICE_LABELS[application.practice_type ?? ""] ?? application.practice_type ?? "";
  const basedIn = BASED_IN_LABELS[application.based_in ?? ""] ?? application.based_in ?? "";
  const rows: [string, string][] = [
    ["Name", application.full_name ?? ""],
    ["Email", accountEmail],
    ...(application.applicant_email && application.applicant_email.toLowerCase() !== accountEmail.toLowerCase()
      ? ([["Email on form", application.applicant_email]] as [string, string][])
      : []),
    ["Phone", application.phone ?? ""],
    ["Membership option", tierLabel(application.membership_tier)],
    ["Practice", practice],
    ["Location", basedIn],
    ["Submitted", formatSubmitted(application.submitted_at)],
  ];
  const subject = `New membership application from ${(application.full_name ?? accountEmail).replace(/[\r\n]+/g, " ")}`;
  const aboutWork = application.about_work ?? "";
  const text = [
    "A new membership application has been submitted.",
    "",
    ...rows.map(([label, value]) => `${label}: ${value}`),
    "",
    "About their work:",
    aboutWork,
  ].join("\n");
  const rowsHtml = rows
    .map(([label, value]) => `<tr><td style="padding:10px 16px;color:#6B5E50;border-bottom:1px solid #E8DCC8">${escapeHtml(label)}</td><td style="padding:10px 16px;color:#2B2118;font-weight:600;border-bottom:1px solid #E8DCC8">${escapeHtml(value)}</td></tr>`)
    .join("");
  const html = `
<div style="background:#F2EAD9;padding:24px 12px;font-family:Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">
    <div style="background:#DDB29A;padding:24px 28px">
      <div style="font-size:24px;font-weight:700;color:#2B2118">New membership application</div>
    </div>
    <div style="padding:28px">
      <table cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;font-size:15px">${rowsHtml}</table>
      <p style="margin:24px 0 8px;font-size:14px;font-weight:700;color:#2B2118">About their work</p>
      <p style="margin:0;font-size:14px;line-height:1.5;color:#2B2118;white-space:pre-wrap">${escapeHtml(aboutWork)}</p>
    </div>
  </div>
</div>`;
  const to = addressList("ADMIN_TO", "info@edan.studio");
  const cc = addressList("ADMIN_CC", "hiba@edan.studio, huangnehemiah10@gmail.com");
  return {
    to,
    cc: cc.length > 0 ? cc : undefined,
    replyTo: accountEmail,
    subject,
    html,
    text,
    idempotencyKey: `${application.id}-admin`,
  };
}

// ---------------------------------------------------------------------------
// Responses
// ---------------------------------------------------------------------------

function failure(err: StepError, completed: string[], claimReleased?: boolean) {
  const body: Record<string, unknown> = {
    ok: false,
    version: VERSION,
    step: err.step,
    error: STEP_LABELS[err.step],
    completed,
  };
  if (claimReleased !== undefined) body.claim_released = claimReleased;
  if (exposeDetails()) {
    body.reason = err.reason;
    if (err.upstreamStatus !== undefined) body.upstream_status = err.upstreamStatus;
    if (err.detail) body.detail = err.detail;
    if (err.hint) body.hint = err.hint;
  }
  return json(body, err.httpStatus);
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ ok: false, step: "request", error: "Method not allowed" }, 405);
  }

  const completed: string[] = [];
  let claim: { supabaseUrl: string; serviceKey: string; applicationId: string } | null = null;

  try {
    // 1. Configuration
    const { supabaseUrl, serviceKey, resendKey } = readConfig();
    completed.push("config");
    log(`config ok (version ${VERSION})`);

    // 2. Who is calling
    const authHeader = req.headers.get("Authorization") ?? "";
    const accessToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!accessToken) {
      throw new StepError("auth", "No sign-in token was sent with the request", 401, {
        hint: "The user must be signed in when the form is submitted.",
      });
    }
    const { id: userId, email: accountEmail } = await userFromToken(supabaseUrl, serviceKey, accessToken);
    completed.push("auth");
    log("auth ok", { userId });

    // 3. Find the submitted application
    const application = await loadLatestPendingApplication(supabaseUrl, serviceKey, userId);
    if (!application) {
      throw new StepError("load_application", "No pending application was found for this user", 404, {
        hint: "The form may not have been saved. Check that the submit_membership_interest call succeeded first.",
      });
    }
    if (!application.submitted_at) {
      throw new StepError("load_application", "The user's pending application was never submitted (submitted_at is empty)", 404);
    }
    completed.push("load_application");
    log("application loaded", { applicationId: application.id });

    if (application.submission_emailed_at) {
      log("already emailed, nothing to do");
      return json({ ok: true, version: VERSION, sent: false, reason: "already_sent", completed });
    }

    // 4. Claim it so two requests cannot both send
    const claimed = await setEmailedAt(
      "claim_application",
      supabaseUrl,
      serviceKey,
      application.id,
      new Date().toISOString(),
      true,
    );
    if (!claimed) {
      log("another request already claimed this application");
      return json({ ok: true, version: VERSION, sent: false, reason: "already_sent", completed });
    }
    claim = { supabaseUrl, serviceKey, applicationId: application.id };
    completed.push("claim_application");
    log("claimed");

    // 5. Send both emails. Each is attempted even if the other fails, and each carries an idempotency
    //    key, so a retry after a partial failure cannot deliver the same email twice (Resend remembers keys for 24h).
    const adminEmail = buildAdminEmail(application, accountEmail);
    log("sending emails", { applicant: accountEmail, to: adminEmail.to, cc: adminEmail.cc ?? [], from: EMAIL_FROM });
    const [applicantResult, adminResult] = await Promise.allSettled([
      sendEmail("send_applicant_email", resendKey, buildApplicantEmail(application, accountEmail)),
      sendEmail("send_admin_email", resendKey, adminEmail),
    ]);
    if (applicantResult.status === "fulfilled") {
      completed.push("send_applicant_email");
      log("applicant email sent");
    }
    if (adminResult.status === "fulfilled") {
      completed.push("send_admin_email");
      log("admin email sent");
    }
    if (applicantResult.status === "rejected") throw applicantResult.reason;
    if (adminResult.status === "rejected") throw adminResult.reason;

    return json({ ok: true, version: VERSION, sent: true, completed });
  } catch (caught) {
    const err = caught instanceof StepError ? caught : new StepError("unexpected", errText(caught), 500);

    // If we claimed the application but could not finish, undo the claim so a retry can work.
    let claimReleased: boolean | undefined;
    if (claim) {
      try {
        await setEmailedAt("release_claim", claim.supabaseUrl, claim.serviceKey, claim.applicationId, null, false);
        claimReleased = true;
      } catch (releaseError) {
        claimReleased = false;
        console.error(
          "[membership-email] COULD NOT UNDO THE EMAILED MARKER. The application is marked as emailed but the emails were not all sent:",
          errText(releaseError),
        );
      }
    }

    console.error(`[membership-email] FAILED at step "${err.step}": ${err.reason}`, {
      version: VERSION,
      status: err.upstreamStatus,
      detail: err.detail,
      hint: err.hint,
      completed,
      claimReleased,
    });
    return failure(err, completed, claimReleased);
  }
});