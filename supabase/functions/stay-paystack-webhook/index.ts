import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const PAYSTACK_BASE_URL = "https://api.paystack.co";
const STAY_REFERENCE_PREFIX = "EDNSTAY-";

type PaystackTransaction = {
  id: number;
  status: string;
  reference: string;
  amount: number;
  currency: string;
  paid_at: string | null;
};

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function toHex(buffer: ArrayBuffer) {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha512Hex(secret: string, payload: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)));
}

async function sha256Hex(payload: string) {
  return toHex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(payload)));
}

function constantTimeEquals(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function fetchVerifiedTransaction(secret: string, reference: string) {
  const response = await fetch(
    `${PAYSTACK_BASE_URL}/transaction/verify/${encodeURIComponent(reference)}`,
    { headers: { Authorization: `Bearer ${secret}` } },
  );
  const payload = await response.json().catch(() => null);
  if (!response.ok || payload?.status !== true) {
    throw new Error(`Paystack verification failed with status ${response.status}`);
  }
  const data = payload.data as PaystackTransaction | null;
  if (!data || typeof data.status !== "string" || data.reference !== reference) {
    throw new Error("Paystack verification returned an unexpected response");
  }
  return data;
}

const EMAIL_FROM = "Ɛdan <info@edan.studio>";

type BookingEmailRow = {
  id: string;
  booking_reference: string;
  check_in: string;
  check_out: string;
  guests: number;
  breakfast_included: boolean;
  total_ghs: number;
  nightly_rate_ghs: number;
  status: string;
  source: string;
  notes: string;
  checked_in_at: string | null;
  guest_name: string;
  guest_email: string;
  guest_phone: string;
  stay_rooms: { name: string } | null;
};

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatStayDate(isoDate: string) {
  return new Date(`${isoDate}T00:00:00Z`).toLocaleDateString("en-GB", {
    timeZone: "UTC",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function buildStayEmails(booking: BookingEmailRow): { guest: EmailMessage; admin: EmailMessage } {
  const roomName = booking.stay_rooms?.name ?? "";
  const amount = `GHS ${booking.total_ghs.toLocaleString("en-GB")}`;
  const checkIn = new Date(`${booking.check_in}T00:00:00Z`);
  const checkOut = new Date(`${booking.check_out}T00:00:00Z`);
  const nights = Math.round((checkOut.getTime() - checkIn.getTime()) / 86400000);
  const rows: [string, string][] = [
    ["Booking reference", booking.booking_reference],
    ["Status", booking.status === "confirmed" ? "Confirmed" : booking.status],
    ["Room", roomName],
    ["Check-in", formatStayDate(booking.check_in)],
    ["Check-out", formatStayDate(booking.check_out)],
    ["Nights", String(nights)],
    ["Guests", String(booking.guests)],
    ["Rate", `${booking.breakfast_included ? "With breakfast" : "Room only"} (GHS ${booking.nightly_rate_ghs.toLocaleString("en-GB")} / night)`],
    ["Total", amount],
    ["Payment source", booking.source === "manual" ? "Manual booking" : "Online booking (Paystack)"],
    ["Guest name", booking.guest_name],
    ["Email", booking.guest_email],
    ["Phone", booking.guest_phone],
  ];
  if (booking.checked_in_at) rows.push(["Checked in", booking.checked_in_at]);
  if (booking.notes) rows.push(["Notes", booking.notes]);
  const rowsHtml = rows
    .map(([label, value]) => `<tr><td style="padding:10px 16px;color:#6B5E50;border-bottom:1px solid #E8DCC8">${escapeHtml(label)}</td><td style="padding:10px 16px;color:#2B2118;font-weight:600;border-bottom:1px solid #E8DCC8">${escapeHtml(value)}</td></tr>`)
    .join("");
  const rowsText = rows.map(([label, value]) => `${label}: ${value}`);

  const guestText = [
    `Hi ${booking.guest_name},`,
    "",
    "Your stay at Ɛdan is confirmed. We look forward to hosting you.",
    "",
    ...rowsText,
    "",
    "With thanks,",
    "The Ɛdan team",
  ].join("\n");
  const guestHtml = `
<div style="background:#F2EAD9;padding:24px 12px;font-family:Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">
    <div style="background:#DDB29A;padding:24px 28px">
      <div style="font-size:28px;font-weight:700;color:#2B2118">Ɛdan</div>
      <div style="font-size:14px;color:#2B2118">Stay confirmed</div>
    </div>
    <div style="padding:28px">
      <p style="margin:0 0 12px;font-size:16px;line-height:1.5;color:#2B2118">Hi ${escapeHtml(booking.guest_name)},</p>
      <p style="margin:0 0 12px;font-size:16px;line-height:1.5;color:#2B2118">Your stay at Ɛdan is confirmed. We look forward to hosting you.</p>
      <table cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;font-size:15px">${rowsHtml}</table>
      <p style="margin:24px 0 0;font-size:14px;line-height:1.5;color:#6B5E50">With thanks,<br>The Ɛdan team</p>
    </div>
  </div>
</div>`;

  const adminText = ["A new stay booking has been confirmed.", "", `Guest: ${booking.guest_name} (${booking.guest_email})`, ...rowsText].join("\n");
  const adminHtml = `
<div style="background:#F2EAD9;padding:24px 12px;font-family:Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">
    <div style="background:#DDB29A;padding:24px 28px">
      <div style="font-size:24px;font-weight:700;color:#2B2118">New stay booking</div>
    </div>
    <div style="padding:28px">
      <p style="margin:0 0 12px;font-size:15px;color:#2B2118">Guest: ${escapeHtml(booking.guest_name)} (${escapeHtml(booking.guest_email)})</p>
      <table cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;font-size:15px">${rowsHtml}</table>
    </div>
  </div>
</div>`;

  return {
    guest: {
      to: [booking.guest_email],
      subject: `Your Ɛdan stay is confirmed (${booking.booking_reference})`,
      html: guestHtml,
      text: guestText,
    },
    admin: {
      to: ["info@edan.studio"],
      cc: ["hiba@edan.studio", "huangnehemiah10@gmail.com"],
      subject: `New stay booking ${booking.booking_reference}`,
      html: adminHtml,
      text: adminText,
    },
  };
}

type EmailMessage = { to: string[]; cc?: string[]; subject: string; html: string; text: string };

async function sendEmail(resendKey: string, email: EmailMessage) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: EMAIL_FROM,
      to: email.to,
      subject: email.subject,
      html: email.html,
      text: email.text,
      cc: email.cc,
    }),
  });
  if (!response.ok) {
    throw new Error(`Sending the email failed (${response.status})`);
  }
}

async function sendConfirmationEmailsIfDue(admin: SupabaseClient, reference: string) {
  const { data: booking, error } = await admin
    .from("stay_bookings")
    .select("id,booking_reference,check_in,check_out,guests,breakfast_included,total_ghs,nightly_rate_ghs,status,source,notes,checked_in_at,guest_name,guest_email,guest_phone,stay_rooms(name)")
    .eq("paystack_reference", reference)
    .eq("status", "confirmed")
    .is("confirmation_emailed_at", null)
    .maybeSingle();
  if (error) throw error;
  if (!booking) return;

  const { data: claimed, error: claimError } = await admin
    .from("stay_bookings")
    .update({ confirmation_emailed_at: new Date().toISOString() })
    .eq("id", booking.id)
    .is("confirmation_emailed_at", null)
    .select("id")
    .maybeSingle();
  if (claimError) throw claimError;
  if (!claimed) return;

  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) throw new Error("Email is not configured");

  const emails = buildStayEmails(booking as unknown as BookingEmailRow);
  try {
    await sendEmail(resendKey, emails.guest);
    await sendEmail(resendKey, emails.admin);
  } catch (sendError) {
    await admin.from("stay_bookings").update({ confirmation_emailed_at: null }).eq("id", booking.id);
    throw sendError;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return respond({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!supabaseUrl || !serviceKey || !secret) {
      return respond({ error: "Payments are not configured yet." }, 500);
    }

    const rawBody = await req.text();
    const signature = req.headers.get("x-paystack-signature") ?? "";
    const expectedSignature = await hmacSha512Hex(secret, rawBody);
    if (!constantTimeEquals(signature, expectedSignature)) {
      return respond({ error: "Invalid signature" }, 401);
    }

    let event: { event?: unknown; data?: { reference?: unknown } };
    try {
      event = JSON.parse(rawBody);
    } catch {
      return respond({ error: "Invalid payload" }, 400);
    }

    const eventType = typeof event.event === "string" ? event.event : "";
    const reference = typeof event.data?.reference === "string" ? event.data.reference : "";
    if (!reference.startsWith(STAY_REFERENCE_PREFIX)) {
      return respond({ received: true, ignored: true });
    }

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const { error: logError } = await admin
      .from("stay_payment_events")
      .upsert(
        { event_key: await sha256Hex(rawBody), event_type: eventType, reference },
        { onConflict: "event_key", ignoreDuplicates: true },
      );
    if (logError) throw logError;

    if (eventType === "charge.success") {
      const transaction = await fetchVerifiedTransaction(secret, reference);
      if (transaction.status === "success") {
        const { data: confirmation, error } = await admin.rpc("confirm_stay_payment", {
          p_reference: reference,
          p_transaction_id: transaction.id,
          p_amount_pesewas: transaction.amount,
          p_currency: transaction.currency,
          p_paid_at: transaction.paid_at,
        });
        if (error) throw error;
        if (confirmation === "confirmed" || confirmation === "already_confirmed") {
          await sendConfirmationEmailsIfDue(admin, reference);
        }
      }
    } else if (eventType === "charge.failed") {
      const { error } = await admin.rpc("mark_stay_payment_failed", { p_reference: reference });
      if (error) throw error;
    }

    return respond({ received: true });
  } catch (error) {
    console.error("Stay Paystack webhook failed:", error instanceof Error ? error.message : error);
    return respond({ error: "Webhook processing failed" }, 500);
  }
});
