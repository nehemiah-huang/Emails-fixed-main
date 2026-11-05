// admin-notifications
//
// Emails the Ɛdan team (and, for two types, the applicant or member) when something happens on the site.
//
// POST body: { "type": "...", ...ids }
//   signup          { user_id }
//   application     { application_id }
//   booking         { booking_id }
//   appointment     { appointment_id }
//   approval        { application_id }   admin only, emails the applicant
//   daily_reminder  {}                   admin only
//
// Optional secrets (Supabase dashboard > Edge Functions > Secrets):
//   EMAIL_FROM             sender, e.g.  Ɛdan <info@edan.studio>  (domain must be verified in Resend)
//   ADMIN_TO / ADMIN_CC    team recipients, comma-separated. Write none in ADMIN_CC for "no CC".
//   SITE_URL               used for the payment link in the approval email
//   EXPOSE_ERROR_DETAILS   set to "true" only while diagnosing; it defaults to hidden.
//                          The function log always keeps the full detail.
// Required: RESEND_API_KEY. SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and SUPABASE_ANON_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

// Bump this when you change the function. It is returned in every reply and logged.
const VERSION = "2026-11-05.2";

const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "Ɛdan <info@edan.studio>";

function addressList(name: string, fallback: string): string[] {
  const value = (Deno.env.get(name) ?? fallback).trim();
  if (value.toLowerCase() === "none") return [];
  return value
    .split(",")
    .map((address) => address.trim())
    .filter(Boolean);
}
const adminTo = () => addressList("ADMIN_TO", "info@edan.studio");
const adminCc = () => addressList("ADMIN_CC", "hiba@edan.studio, huangnehemiah10@gmail.com");

function exposeDetails(): boolean {
  return (Deno.env.get("EXPOSE_ERROR_DETAILS") ?? "false").toLowerCase() === "true";
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const PRACTICE_LABELS: Record<string, string> = {
  researcher: "Researcher",
  creative: "Creative",
  spatial_practitioner: "Spatial practitioner",
  collective: "Collective",
  student: "Student",
  partner_institution: "Partner institution",
  other: "Other",
};

const BASED_LABELS: Record<string, string> = {
  accra: "Accra",
  passing_through: "Passing through",
};

const TIER_LABELS: Record<string, string> = {
  monthly: "Monthly affiliate (GH₵ 1,000 / month)",
  annual: "Annual affiliate (GH₵ 8,000 / year)",
};

type Db = ReturnType<typeof createClient>;

type Email = {
  to: string[];
  cc?: string[];
  replyTo?: string;
  subject: string;
  html: string;
  text: string;
  idempotencyKey?: string;
};

// ---------------------------------------------------------------------------
// Step-aware errors
// ---------------------------------------------------------------------------

type StepName =
  | "request"
  | "config"
  | "auth"
  | "authorise"
  | "load"
  | "claim"
  | "digest"
  | "send"
  | "unexpected";

const STEP_LABELS: Record<StepName, string> = {
  request: "The request was not valid",
  config: "The function is not configured",
  auth: "The sign-in check failed",
  authorise: "You are not allowed to do that",
  load: "Loading the record failed",
  claim: "Recording the notification failed",
  digest: "Building the daily summary failed",
  send: "Sending the email failed",
  unexpected: "Something unexpected went wrong",
};

class StepError extends Error {
  step: StepName;
  reason: string;
  httpStatus: number;
  upstreamStatus?: number;
  detail?: string;
  hint?: string;
  claimReleased?: boolean;

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

function dbError(step: StepName, error: { message: string; code?: string }): StepError {
  const missing = /does not exist|42703|42P01|PGRST20\d|schema cache/i.test(`${error.code ?? ""} ${error.message}`);
  return new StepError(step, `The database returned an error: ${error.message}`, 500, {
    detail: error.code,
    hint: missing
      ? "A table or column this function needs is missing. Check notification_log, reminder_log and the columns selected in this function."
      : undefined,
  });
}

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

function sendHint(status: number | undefined): string | undefined {
  if (status === 401 || status === 403) {
    return "Resend refused the request. Check the RESEND_API_KEY secret, and that the domain in EMAIL_FROM is verified in Resend.";
  }
  if (status === 422) return "Resend says the sender or a recipient address is not valid. Check EMAIL_FROM and the recipient addresses.";
  if (status === 429) return "Resend's rate limit was reached. Try again shortly.";
  return undefined;
}

function log(message: string, extra?: unknown) {
  if (extra === undefined) console.log(`[admin-notifications] ${message}`);
  else console.log(`[admin-notifications] ${message}`, extra);
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function safe(value: string | null | undefined): string {
  return value ?? "";
}

function oneLine(value: string): string {
  return value.replace(/[\r\n]+/g, " ").trim();
}

function validEmail(value: string | null | undefined): value is string {
  return typeof value === "string" && /^[^\s@]+@[^\s@]+$/.test(value.trim());
}

function replyAddress(value: string | null | undefined): string | undefined {
  return validEmail(value) ? value.trim() : undefined;
}

// A joined row can come back as an object or as a one-item array depending on the relationship.
function one<T>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return `${date.toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short", timeZone: "UTC" })} UTC`;
}

function formatMoney(amount: number | null | undefined): string {
  return `GH₵ ${(amount ?? 0).toLocaleString("en-GB")}`;
}

function rowsText(rows: [string, string][]): string {
  return rows.map(([label, value]) => `${label}: ${value}`).join("\n");
}

function emailShell(title: string, bodyHtml: string): string {
  return `
<div style="background:#F2EAD9;padding:24px 12px;font-family:Helvetica,Arial,sans-serif">
  <div style="max-width:580px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">
    <div style="background:#DDB29A;padding:24px 28px">
      <div style="font-size:28px;font-weight:700;color:#2B2118">Ɛdan</div>
      <div style="font-size:14px;color:#2B2118;margin-top:2px">${escapeHtml(title)}</div>
    </div>
    <div style="padding:28px">
      ${bodyHtml}
    </div>
    <div style="padding:0 28px 24px">
      <p style="margin:0;font-size:12px;line-height:1.5;color:#A89880">This is an automated email from Ɛdan.</p>
    </div>
  </div>
</div>`;
}

function detailTable(rows: [string, string][]): string {
  return `<table cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;font-size:15px;margin-top:8px">${rows
    .map(
      ([label, value]) =>
        `<tr><td style="padding:10px 16px;color:#6B5E50;border-bottom:1px solid #E8DCC8;width:40%;vertical-align:top">${escapeHtml(label)}</td><td style="padding:10px 16px;color:#2B2118;font-weight:600;border-bottom:1px solid #E8DCC8;white-space:pre-wrap">${escapeHtml(value)}</td></tr>`,
    )
    .join("")}</table>`;
}

// ---------------------------------------------------------------------------
// Config, sending, and the "already sent" log
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
      hint: "Add the missing secret(s) under Edge Functions > Secrets, then redeploy.",
    });
  }
  return { supabaseUrl: supabaseUrl!, serviceKey: serviceKey!, resendKey: resendKey! };
}

async function sendEmail(resendKey: string, email: Email) {
  if (email.to.length === 0) {
    throw new StepError("send", "No recipients are configured for this email", 500, {
      hint: "Check the ADMIN_TO secret, or the address on the record.",
    });
  }
  const headers: Record<string, string> = {
    Authorization: `Bearer ${resendKey}`,
    "Content-Type": "application/json",
  };
  if (email.idempotencyKey) headers["Idempotency-Key"] = email.idempotencyKey;

  let response: Response;
  try {
    response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers,
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: email.to,
        cc: email.cc && email.cc.length > 0 ? email.cc : undefined,
        reply_to: email.replyTo,
        subject: email.subject,
        html: email.html,
        text: email.text,
      }),
      signal: AbortSignal.timeout(10000),
    });
  } catch (error) {
    throw new StepError("send", `Could not reach Resend: ${errText(error)}`, 502);
  }
  if (!response.ok) {
    const { text, summary } = await readUpstream(response);
    throw new StepError("send", `Resend rejected the email (${response.status}): ${summary}`, 502, {
      upstreamStatus: response.status,
      detail: text,
      hint: sendHint(response.status),
    });
  }
}

async function hasNotified(client: Db, type: string, refId: string): Promise<boolean> {
  const { data, error } = await client
    .from("notification_log")
    .select("id")
    .eq("notification_type", type)
    .eq("ref_id", refId)
    .limit(1);
  if (error) throw dbError("claim", error);
  return (data?.length ?? 0) > 0;
}

// Returns false when another request already holds the claim (unique violation).
async function claimNotification(client: Db, type: string, refId: string): Promise<boolean> {
  const { error } = await client.from("notification_log").insert({ notification_type: type, ref_id: refId });
  if (!error) return true;
  if (error.code === "23505") return false;
  throw dbError("claim", error);
}

async function releaseNotification(client: Db, type: string, refId: string): Promise<boolean> {
  const { error } = await client.from("notification_log").delete().eq("notification_type", type).eq("ref_id", refId);
  if (error) {
    console.error(`[admin-notifications] COULD NOT UNDO THE NOTIFICATION MARKER for ${type} ${refId}: ${error.message}`);
    return false;
  }
  return true;
}

async function hasReminded(client: Db, type: string, date: string): Promise<boolean> {
  const { data, error } = await client
    .from("reminder_log")
    .select("id")
    .eq("reminder_type", type)
    .eq("reminder_date", date)
    .limit(1);
  if (error) throw dbError("claim", error);
  return (data?.length ?? 0) > 0;
}

async function claimReminder(client: Db, type: string, date: string): Promise<boolean> {
  const { error } = await client.from("reminder_log").insert({ reminder_type: type, reminder_date: date });
  if (!error) return true;
  if (error.code === "23505") return false;
  throw dbError("claim", error);
}

async function releaseReminder(client: Db, type: string, date: string): Promise<boolean> {
  const { error } = await client.from("reminder_log").delete().eq("reminder_type", type).eq("reminder_date", date);
  if (error) {
    console.error(`[admin-notifications] COULD NOT UNDO THE REMINDER MARKER for ${type} ${date}: ${error.message}`);
    return false;
  }
  return true;
}

function alreadySent(reason: string) {
  return json({ ok: true, version: VERSION, sent: false, reason });
}

// Claim first so two requests cannot both send. If sending fails, release the claim so a retry can work.
async function sendOnce(client: Db, type: string, refId: string, send: () => Promise<void>): Promise<Response> {
  if (await hasNotified(client, type, refId)) return alreadySent("already_sent");
  if (!(await claimNotification(client, type, refId))) return alreadySent("already_sent");
  try {
    await send();
  } catch (caught) {
    const err = caught instanceof StepError ? caught : new StepError("unexpected", errText(caught), 500);
    err.claimReleased = await releaseNotification(client, type, refId);
    throw err;
  }
  log(`${type} email sent`, { refId });
  return json({ ok: true, version: VERSION, sent: true });
}

// ---------------------------------------------------------------------------
// Email content
// ---------------------------------------------------------------------------

// ── Signup (to the team) ──
function buildSignupEmail(user: { id: string; email: string; full_name: string; created_at: string }): Email {
  const rows: [string, string][] = [
    ["Full name", safe(user.full_name)],
    ["Email", safe(user.email)],
    ["Account ID", safe(user.id)],
    ["Registered", formatDateTime(user.created_at)],
  ];
  const subject = `New account signup — ${oneLine(user.full_name || user.email)}`;
  const text = `A new account has been registered on the Ɛdan website.\n\n${rowsText(rows)}`;
  const html = emailShell(
    "New account signup",
    `<p style="margin:0 0 8px;font-size:16px;color:#2B2118">A new account has been registered.</p>${detailTable(rows)}`,
  );
  return { to: adminTo(), cc: adminCc(), replyTo: replyAddress(user.email), subject, html, text };
}

// ── Affiliate application (to the team) ──
function buildApplicationEmail(app: {
  full_name: string;
  applicant_email: string;
  phone: string;
  practice_type: string;
  based_in: string;
  membership_tier: string;
  about_work: string;
  submitted_at: string;
}): Email {
  const rows: [string, string][] = [
    ["Full name", safe(app.full_name)],
    ["Email", safe(app.applicant_email)],
    ["Phone", safe(app.phone)],
    ["Practice", PRACTICE_LABELS[app.practice_type] ?? safe(app.practice_type)],
    ["Based in", BASED_LABELS[app.based_in] ?? safe(app.based_in)],
    ["Membership", TIER_LABELS[app.membership_tier] ?? safe(app.membership_tier)],
    ["Submitted", formatDate(app.submitted_at)],
  ];
  const subject = `New affiliate application — ${oneLine(app.full_name || app.applicant_email)}`;
  const text = `A new affiliate application has been submitted.\n\n${rowsText(rows)}\n\nAbout their work:\n${safe(app.about_work)}`;
  const html = emailShell(
    "New affiliate application",
    `<p style="margin:0 0 8px;font-size:16px;color:#2B2118">A new affiliate application has been submitted.</p>${detailTable(rows)}<p style="margin:20px 0 8px;font-size:14px;font-weight:700;color:#2B2118">About their work</p><p style="margin:0;font-size:14px;line-height:1.6;color:#2B2118;white-space:pre-wrap">${escapeHtml(safe(app.about_work))}</p>`,
  );
  return { to: adminTo(), cc: adminCc(), replyTo: replyAddress(app.applicant_email), subject, html, text };
}

// ── Stay booking (to the team, full admin-view details) ──
function buildBookingEmail(booking: {
  booking_reference: string;
  guest_name: string;
  guest_email: string;
  guest_phone: string;
  room_name: string;
  check_in: string;
  check_out: string;
  guests: number;
  breakfast_included: boolean;
  nightly_rate_ghs: number;
  total_ghs: number;
  status: string;
  source: string;
  notes: string;
  checked_in_at: string | null;
}): Email {
  const nights = Math.round(
    (new Date(`${booking.check_out}T00:00:00Z`).getTime() - new Date(`${booking.check_in}T00:00:00Z`).getTime()) / 86400000,
  );
  const statusLabels: Record<string, string> = {
    pending_payment: "Pending payment",
    confirmed: "Confirmed",
    cancelled: "Cancelled",
    completed: "Completed",
    payment_failed: "Payment failed",
  };
  const rows: [string, string][] = [
    ["Reference", safe(booking.booking_reference)],
    ["Status", statusLabels[booking.status] ?? safe(booking.status)],
    ["Room", safe(booking.room_name)],
    ["Check-in", formatDate(booking.check_in)],
    ["Check-out", formatDate(booking.check_out)],
    ["Nights", String(nights)],
    ["Guests", String(booking.guests)],
    ["Rate", `${booking.breakfast_included ? "With breakfast" : "Room only"} (${formatMoney(booking.nightly_rate_ghs)} / night)`],
    ["Total", formatMoney(booking.total_ghs)],
    ["Payment source", booking.source === "manual" ? "Manual booking (not linked to Paystack)" : "Online booking (Paystack)"],
    ["Guest name", safe(booking.guest_name)],
    ["Email", safe(booking.guest_email)],
    ["Phone", safe(booking.guest_phone)],
  ];
  if (booking.checked_in_at) rows.push(["Checked in", formatDateTime(booking.checked_in_at)]);
  if (booking.notes) rows.push(["Notes", safe(booking.notes)]);
  const subject = `New stay booking — ${oneLine(safe(booking.booking_reference))} — ${oneLine(safe(booking.guest_name))}`;
  const text = `A new stay booking has been created.\n\n${rowsText(rows)}`;
  const html = emailShell(
    "New stay booking",
    `<p style="margin:0 0 8px;font-size:16px;color:#2B2118">A new stay booking has been created.</p>${detailTable(rows)}`,
  );
  return { to: adminTo(), cc: adminCc(), replyTo: replyAddress(booking.guest_email), subject, html, text };
}

type AppointmentDetails = {
  id: string;
  booking_reference: string;
  member_name: string;
  member_email: string;
  whatsapp_number: string;
  member_note: string;
  status: string;
  appointment_title: string;
  starts_at: string | null;
  ends_at: string | null;
};

// ── Appointment request (to the team) ──
function buildAppointmentEmail(appointment: AppointmentDetails): Email {
  const rows: [string, string][] = [
    ["Reference", safe(appointment.booking_reference)],
    ["Appointment", safe(appointment.appointment_title)],
    ["Member", safe(appointment.member_name)],
    ["Email", safe(appointment.member_email)],
    ["WhatsApp", safe(appointment.whatsapp_number)],
    ["Status", safe(appointment.status)],
    ["Requested start", formatDateTime(appointment.starts_at)],
    ["Requested end", formatDateTime(appointment.ends_at)],
  ];
  if (appointment.member_note) rows.push(["Note", appointment.member_note]);
  const text = `A new appointment request has been submitted.\n\n${rowsText(rows)}`;
  const html = emailShell(
    "New appointment request",
    `<p style="margin:0 0 8px;font-size:16px;color:#2B2118">A new appointment request has been submitted.</p>${detailTable(rows)}`,
  );
  return {
    to: adminTo(),
    cc: adminCc(),
    replyTo: replyAddress(appointment.member_email),
    subject: `New appointment request — ${oneLine(safe(appointment.booking_reference))}`,
    html,
    text,
    idempotencyKey: `appointment-${appointment.id}-admin`,
  };
}

// ── Appointment request (confirmation to the member) ──
function buildAppointmentConfirmationEmail(appointment: AppointmentDetails): Email {
  const rows: [string, string][] = [
    ["Reference", safe(appointment.booking_reference)],
    ["Appointment", safe(appointment.appointment_title)],
    ["Status", "Request received"],
    ["Requested start", formatDateTime(appointment.starts_at)],
    ["Requested end", formatDateTime(appointment.ends_at)],
  ];
  const text = `Hi ${safe(appointment.member_name)},\n\nWe received your appointment request with Ɛdan. We will be in touch to confirm the time.\n\n${rowsText(rows)}\n\nWith thanks,\nThe Ɛdan team`;
  const html = emailShell(
    "Appointment request received",
    `<p style="margin:0 0 12px;font-size:16px;color:#2B2118">Hi ${escapeHtml(safe(appointment.member_name))},</p><p style="margin:0 0 16px;font-size:16px;line-height:1.5;color:#2B2118">We received your appointment request. We will be in touch to confirm the time.</p>${detailTable(rows)}<p style="margin:24px 0 0;font-size:14px;color:#6B5E50">With thanks,<br>The Ɛdan team</p>`,
  );
  return {
    to: [safe(appointment.member_email)].filter(Boolean),
    subject: `Appointment request received — ${oneLine(safe(appointment.booking_reference))}`,
    html,
    text,
    idempotencyKey: `appointment-${appointment.id}-member`,
  };
}

// ── Membership approved (to the applicant, with payment link) ──
function buildApprovalEmail(app: {
  full_name: string;
  applicant_email: string;
  membership_tier: string;
  site_url: string;
}): Email {
  const tierLabel = TIER_LABELS[app.membership_tier] ?? safe(app.membership_tier);
  const paymentUrl = `${app.site_url}/members/`;
  const subject = "Your Ɛdan membership has been approved";
  const text = `Hi ${safe(app.full_name)},\n\nYour Ɛdan membership application has been approved.\n\nMembership: ${tierLabel}\n\nTo complete your membership, please pay by visiting:\n${paymentUrl}\n\nWith thanks,\nThe Ɛdan team`;
  const html = emailShell(
    "Membership approved",
    `<p style="margin:0 0 12px;font-size:16px;color:#2B2118">Hi ${escapeHtml(safe(app.full_name))},</p><p style="margin:0 0 16px;font-size:16px;line-height:1.5;color:#2B2118">Your Ɛdan membership application has been approved.</p>${detailTable([["Membership", tierLabel]])}<p style="margin:24px 0 12px;font-size:16px;line-height:1.5;color:#2B2118">To complete your membership, please pay by clicking the link below:</p><p style="margin:0 0 24px"><a href="${escapeHtml(paymentUrl)}" style="display:inline-block;padding:12px 28px;background:#DDB29A;color:#2B2118;text-decoration:none;font-weight:700;border-radius:6px;font-size:15px">Pay for your membership</a></p><p style="margin:0;font-size:14px;color:#6B5E50">With thanks,<br>The Ɛdan team</p>`,
  );
  return { to: [safe(app.applicant_email)].filter(Boolean), subject, html, text };
}

// ── Daily summary (to the team) ──
type Digest = {
  pending_applications?: unknown[] | null;
  expired_memberships?: unknown[] | null;
  upcoming_block_ends?: unknown[] | null;
} | null;

function buildReminderEmail(digest: Digest): Email {
  const sections: string[] = [];
  const textParts: string[] = [];
  const spacer = '<div style="height:16px"></div>';

  type PendingApp = {
    full_name: string;
    applicant_email: string;
    phone: string;
    membership_tier: string;
    submitted_at: string;
  };
  const apps = (digest?.pending_applications ?? []) as PendingApp[];
  if (apps.length > 0) {
    const tables = apps.map((a) =>
      detailTable([
        ["Name", safe(a.full_name)],
        ["Email", safe(a.applicant_email)],
        ["Phone", safe(a.phone)],
        ["Membership", TIER_LABELS[a.membership_tier] ?? safe(a.membership_tier)],
        ["Submitted", formatDate(a.submitted_at)],
      ])
    );
    sections.push(
      `<p style="margin:0 0 12px;font-size:15px;font-weight:700;color:#2B2118">Pending applications awaiting review (${apps.length})</p>${tables.join(spacer)}`,
    );
    textParts.push(
      `Pending applications (${apps.length}):\n${apps.map((a) => `  - ${safe(a.full_name)} (${safe(a.applicant_email)}) — ${TIER_LABELS[a.membership_tier] ?? safe(a.membership_tier)}`).join("\n")}`,
    );
  }

  type ExpiredMember = {
    member_email: string;
    membership_tier: string;
    expires_at: string;
  };
  const members = (digest?.expired_memberships ?? []) as ExpiredMember[];
  if (members.length > 0) {
    const tables = members.map((m) =>
      detailTable([
        ["Email", safe(m.member_email)],
        ["Tier", safe(m.membership_tier)],
        ["Status", "Expired"],
        ["Expires", formatDate(m.expires_at)],
      ])
    );
    sections.push(
      `<p style="margin:0 0 12px;font-size:15px;font-weight:700;color:#2B2118">Expired memberships (${members.length})</p>${tables.join(spacer)}`,
    );
    textParts.push(
      `Expired memberships (${members.length}):\n${members.map((m) => `  - ${safe(m.member_email)} — expired ${formatDate(m.expires_at)}`).join("\n")}`,
    );
  }

  type Block = {
    room_name: string;
    starts_on: string;
    ends_on: string;
    reason: string;
  };
  const blocks = (digest?.upcoming_block_ends ?? []) as Block[];
  if (blocks.length > 0) {
    const tables = blocks.map((b) =>
      detailTable([
        ["Room", safe(b.room_name)],
        ["From", formatDate(b.starts_on)],
        ["Until (first day free)", formatDate(b.ends_on)],
        ["Reason", safe(b.reason)],
      ])
    );
    sections.push(
      `<p style="margin:0 0 12px;font-size:15px;font-weight:700;color:#2B2118">Blocked dates ending soon (${blocks.length})</p>${tables.join(spacer)}`,
    );
    textParts.push(
      `Blocked dates ending soon (${blocks.length}):\n${blocks.map((b) => `  - ${safe(b.room_name)}: ${formatDate(b.starts_on)} to ${formatDate(b.ends_on)}`).join("\n")}`,
    );
  }

  const hasContent = sections.length > 0;
  const bodyHtml = hasContent
    ? sections.join('<div style="height:24px"></div>')
    : `<p style="margin:0;font-size:16px;color:#2B2118">No pending items today. Everything is up to date.</p>`;
  const subject = hasContent ? "Ɛdan daily summary — action needed" : "Ɛdan daily summary — all clear";
  const text = hasContent ? textParts.join("\n\n") : "No pending items today. Everything is up to date.";

  return { to: adminTo(), cc: adminCc(), subject, html: emailShell("Daily summary", bodyHtml), text };
}

// ---------------------------------------------------------------------------
// Request handling
// ---------------------------------------------------------------------------

type Ctx = {
  client: Db;
  supabaseUrl: string;
  resendKey: string;
  body: Record<string, unknown>;
  accessToken: string;
  callerId: string;
  callerIsAdmin: boolean;
};

function requireId(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || !value.trim()) throw new StepError("request", `${key} required`, 400);
  return value.trim();
}

function requireAdmin(ctx: Ctx) {
  if (!ctx.callerIsAdmin) throw new StepError("authorise", "Admin access required", 403);
}

async function authenticate(req: Request, client: Db) {
  const header = req.headers.get("Authorization") ?? "";
  const accessToken = header.replace(/^Bearer\s+/i, "");
  if (!accessToken) throw new StepError("auth", "Sign in required", 401);

  const { data, error } = await client.auth.getUser(accessToken);
  if (error || !data.user) throw new StepError("auth", "Sign in required", 401, { detail: error?.message });

  const { data: adminRow, error: adminError } = await client
    .from("admins")
    .select("user_id")
    .eq("user_id", data.user.id)
    .maybeSingle();
  if (adminError) throw dbError("auth", adminError);

  return { accessToken, callerId: data.user.id, callerIsAdmin: Boolean(adminRow) };
}

async function handleDailyReminder(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);

  const today = new Date().toISOString().slice(0, 10);
  const reminderType = "daily_digest";
  if (await hasReminded(ctx.client, reminderType, today)) return alreadySent("already_sent_today");

  // The digest RPC checks the caller is an admin, so call it with the caller's own token.
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!anonKey) throw new StepError("config", "Missing secret(s): SUPABASE_ANON_KEY", 500);
  const userClient = createClient(ctx.supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${ctx.accessToken}` } },
    auth: { persistSession: false },
  });
  const { data: digest, error: digestError } = await userClient.rpc("get_daily_admin_digest");
  if (digestError) throw new StepError("digest", `The digest query failed: ${digestError.message}`, 500, { detail: digestError.code });
  if (!digest) throw new StepError("digest", "The digest query returned nothing", 500);

  const email = buildReminderEmail(digest as Digest);
  if (!(await claimReminder(ctx.client, reminderType, today))) return alreadySent("already_sent_today");
  try {
    await sendEmail(ctx.resendKey, email);
  } catch (caught) {
    const err = caught instanceof StepError ? caught : new StepError("unexpected", errText(caught), 500);
    err.claimReleased = await releaseReminder(ctx.client, reminderType, today);
    throw err;
  }
  log("daily reminder sent", { today });
  return json({ ok: true, version: VERSION, sent: true, digest });
}

async function handleSignup(ctx: Ctx): Promise<Response> {
  const userId = requireId(ctx.body, "user_id");
  if (userId !== ctx.callerId && !ctx.callerIsAdmin) throw new StepError("authorise", "Not authorised", 403);

  const { data, error } = await ctx.client.auth.admin.getUserById(userId);
  if (error || !data.user) throw new StepError("load", "User not found", 404, { detail: error?.message });

  const u = data.user;
  const email = buildSignupEmail({
    id: u.id,
    email: u.email ?? "",
    full_name: (u.user_metadata?.full_name as string) ?? "",
    created_at: u.created_at,
  });
  return await sendOnce(ctx.client, "signup", userId, () => sendEmail(ctx.resendKey, email));
}

async function handleApplication(ctx: Ctx): Promise<Response> {
  const appId = requireId(ctx.body, "application_id");

  const { data: app, error } = await ctx.client
    .from("membership_applications")
    .select("user_id,full_name,applicant_email,phone,practice_type,based_in,membership_tier,about_work,submitted_at")
    .eq("id", appId)
    .maybeSingle();
  if (error) throw dbError("load", error);
  if (!app) throw new StepError("load", "Application not found", 404);
  if (!ctx.callerIsAdmin && app.user_id !== ctx.callerId) throw new StepError("authorise", "Not authorised", 403);

  const email = buildApplicationEmail(app);
  return await sendOnce(ctx.client, "application", appId, () => sendEmail(ctx.resendKey, email));
}

async function handleBooking(ctx: Ctx): Promise<Response> {
  const bookingId = requireId(ctx.body, "booking_id");

  const { data: booking, error } = await ctx.client
    .from("stay_bookings")
    .select("user_id,booking_reference,guest_name,guest_email,guest_phone,check_in,check_out,guests,breakfast_included,nightly_rate_ghs,total_ghs,status,source,notes,checked_in_at,stay_rooms(name)")
    .eq("id", bookingId)
    .maybeSingle();
  if (error) throw dbError("load", error);
  if (!booking) throw new StepError("load", "Booking not found", 404);
  if (!ctx.callerIsAdmin && booking.user_id !== ctx.callerId) throw new StepError("authorise", "Not authorised", 403);

  const room = one(booking.stay_rooms as { name?: string } | { name?: string }[] | null);
  const email = buildBookingEmail({ ...booking, room_name: room?.name ?? "—" });
  return await sendOnce(ctx.client, "booking", bookingId, () => sendEmail(ctx.resendKey, email));
}

async function handleAppointment(ctx: Ctx): Promise<Response> {
  const appointmentId = requireId(ctx.body, "appointment_id");

  const { data: appointment, error } = await ctx.client
    .from("member_appointments")
    .select("user_id,booking_reference,member_name,member_email,whatsapp_number,member_note,status,requested_start_at,member_appointment_types(title,duration_minutes),member_appointment_slots(starts_at,ends_at)")
    .eq("id", appointmentId)
    .maybeSingle();
  if (error) throw dbError("load", error);
  if (!appointment) throw new StepError("load", "Appointment not found", 404);
  if (!ctx.callerIsAdmin && appointment.user_id !== ctx.callerId) throw new StepError("authorise", "Not authorised", 403);

  const slot = one(appointment.member_appointment_slots as { starts_at?: string; ends_at?: string } | { starts_at?: string; ends_at?: string }[] | null);
  const apptType = one(appointment.member_appointment_types as { title?: string; duration_minutes?: number } | { title?: string; duration_minutes?: number }[] | null);
  const startsAt = slot?.starts_at ?? appointment.requested_start_at ?? null;
  const endsAt = slot?.ends_at ?? (startsAt && apptType?.duration_minutes
    ? new Date(new Date(startsAt).getTime() + apptType.duration_minutes * 60_000).toISOString()
    : null);

  const details: AppointmentDetails = {
    id: appointmentId,
    booking_reference: appointment.booking_reference,
    member_name: appointment.member_name,
    member_email: appointment.member_email,
    whatsapp_number: appointment.whatsapp_number,
    member_note: appointment.member_note,
    status: appointment.status,
    appointment_title: apptType?.title ?? "Appointment",
    starts_at: startsAt,
    ends_at: endsAt,
  };
  const adminEmail = buildAppointmentEmail(details);
  const memberEmail = buildAppointmentConfirmationEmail(details);

  return await sendOnce(ctx.client, "appointment", appointmentId, async () => {
    // Attempt both. If one fails, the retry cannot deliver the other twice (idempotency keys).
    const results = await Promise.allSettled([
      sendEmail(ctx.resendKey, adminEmail),
      sendEmail(ctx.resendKey, memberEmail),
    ]);
    for (const result of results) {
      if (result.status === "rejected") throw result.reason;
    }
  });
}

async function handleApproval(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const appId = requireId(ctx.body, "application_id");

  const { data: app, error } = await ctx.client
    .from("membership_applications")
    .select("full_name,applicant_email,membership_tier")
    .eq("id", appId)
    .maybeSingle();
  if (error) throw dbError("load", error);
  if (!app) throw new StepError("load", "Application not found", 404);

  // The link comes from the SITE_URL secret only, never from the request body.
  const siteUrl = (Deno.env.get("SITE_URL") ?? "https://edan.studio").replace(/\/+$/, "");
  const email = buildApprovalEmail({ ...app, site_url: siteUrl });
  return await sendOnce(ctx.client, "approval", appId, () => sendEmail(ctx.resendKey, email));
}

function failure(err: StepError) {
  const body: Record<string, unknown> = {
    ok: false,
    version: VERSION,
    step: err.step,
    // Client errors (bad request, not signed in, not allowed) are safe to explain; server errors stay generic.
    error: err.httpStatus < 500 ? err.reason : STEP_LABELS[err.step],
  };
  if (err.claimReleased !== undefined) body.claim_released = err.claimReleased;
  if (exposeDetails()) {
    body.reason = err.reason;
    if (err.upstreamStatus !== undefined) body.upstream_status = err.upstreamStatus;
    if (err.detail) body.detail = err.detail;
    if (err.hint) body.hint = err.hint;
  }
  return json(body, err.httpStatus);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, step: "request", error: "Method not allowed" }, 405);
  }

  let type = "";
  try {
    const { supabaseUrl, serviceKey, resendKey } = readConfig();
    const client = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // an empty body is fine for the daily reminder
    }
    type = typeof body.type === "string" ? body.type : "";

    const caller = await authenticate(req, client);
    const ctx: Ctx = { client, supabaseUrl, resendKey, body, ...caller };
    log(`request ok (version ${VERSION})`, { type, callerId: caller.callerId });

    switch (type) {
      case "daily_reminder":
        return await handleDailyReminder(ctx);
      case "signup":
        return await handleSignup(ctx);
      case "application":
        return await handleApplication(ctx);
      case "booking":
        return await handleBooking(ctx);
      case "appointment":
        return await handleAppointment(ctx);
      case "approval":
        return await handleApproval(ctx);
      default:
        throw new StepError(
          "request",
          "Unknown notification type. Use: signup, application, booking, appointment, approval, daily_reminder",
          400,
        );
    }
  } catch (caught) {
    const err = caught instanceof StepError ? caught : new StepError("unexpected", errText(caught), 500);
    console.error(`[admin-notifications] FAILED at step "${err.step}": ${err.reason}`, {
      version: VERSION,
      type,
      status: err.upstreamStatus,
      detail: err.detail,
      hint: err.hint,
      claimReleased: err.claimReleased,
    });
    return failure(err);
  }
});