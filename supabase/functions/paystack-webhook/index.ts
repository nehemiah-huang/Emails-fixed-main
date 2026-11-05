const RECEIPT_FROM = "Ɛdan <info@edan.studio>";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha512Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return toHex(signature);
}

async function sha256Hex(message: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(message));
  return toHex(digest);
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

type PaystackVerification = {
  id: number;
  reference: string;
  status: string;
  amount: number;
  currency: string;
  paid_at: string | null;
};

async function verifyWithPaystack(secret: string, reference: string): Promise<PaystackVerification> {
  const response = await fetch(
    `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
    { headers: { Authorization: `Bearer ${secret}` } },
  );
  if (!response.ok) {
    throw new Error(`Paystack verification failed (${response.status})`);
  }
  const body = await response.json();
  const data = body?.data;
  if (
    body?.status !== true ||
    typeof data?.id !== "number" ||
    typeof data?.reference !== "string" ||
    typeof data?.status !== "string" ||
    typeof data?.amount !== "number" ||
    typeof data?.currency !== "string"
  ) {
    throw new Error("Paystack verification returned an unexpected response");
  }
  return data as PaystackVerification;
}

async function recordEvent(
  supabaseUrl: string,
  serviceKey: string,
  args: Record<string, unknown>,
): Promise<string> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/record_paystack_event`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) {
    throw new Error(`Recording the payment failed (${response.status})`);
  }
  return (await response.json()) as string;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const PLAN_LABELS: Record<string, string> = {
  monthly: "Monthly affiliate",
  annual: "Annual affiliate",
};

type ReceiptPayment = {
  id: string;
  reference: string;
  plan: string;
  amount_pesewas: number;
  currency: string;
  paid_at: string | null;
  status: string;
  receipt_sent_at: string | null;
  membership_applications: { applicant_email: string; created_at: string } | null;
};

async function fetchReceiptPayment(
  supabaseUrl: string,
  serviceKey: string,
  reference: string,
): Promise<ReceiptPayment | null> {
  const select = "id,reference,plan,amount_pesewas,currency,paid_at,status,receipt_sent_at,membership_applications(applicant_email,created_at)";
  const response = await fetch(
    `${supabaseUrl}/rest/v1/payment_transactions?reference=eq.${encodeURIComponent(reference)}&select=${select}`,
    { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
  );
  if (!response.ok) {
    throw new Error(`Loading the payment failed (${response.status})`);
  }
  const rows = (await response.json()) as ReceiptPayment[];
  return rows[0] ?? null;
}

async function setReceiptSentAt(
  supabaseUrl: string,
  serviceKey: string,
  paymentId: string,
  value: string | null,
  onlyIfUnsent: boolean,
): Promise<boolean> {
  const filter = onlyIfUnsent ? "&receipt_sent_at=is.null" : "";
  const response = await fetch(
    `${supabaseUrl}/rest/v1/payment_transactions?id=eq.${paymentId}${filter}&select=id`,
    {
      method: "PATCH",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({ receipt_sent_at: value }),
    },
  );
  if (!response.ok) {
    throw new Error(`Updating the receipt status failed (${response.status})`);
  }
  const rows = (await response.json()) as unknown[];
  return rows.length > 0;
}

function formatReceiptDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("en-GB", { timeZone: "Africa/Accra", day: "numeric", month: "long", year: "numeric" });
}

function buildReceipt(payment: ReceiptPayment): { subject: string; html: string; text: string } {
  const planLabel = PLAN_LABELS[payment.plan] ?? payment.plan;
  const amount = `${payment.currency} ${(payment.amount_pesewas / 100).toFixed(2)}`;
  const paidOn = formatReceiptDate(payment.paid_at);
  const appliedOn = formatReceiptDate(payment.membership_applications?.created_at ?? null);
  const reference = payment.reference;
  const text = [
    "Ɛdan membership receipt",
    "",
    "Thank you for joining Ɛdan. Your payment has been received.",
    "",
    `Membership: ${planLabel}`,
    `Application submitted: ${appliedOn}`,
    `Amount paid: ${amount}`,
    `Date paid: ${paidOn}`,
    `Payment reference: ${reference}`,
    "",
    "Your membership is confirmed once our team has reviewed your application.",
  ].join("\n");
  const rows: [string, string][] = [
    ["Membership", planLabel],
    ["Application submitted", appliedOn],
    ["Amount paid", amount],
    ["Date paid", paidOn],
    ["Payment reference", reference],
  ];
  const rowsHtml = rows
    .map(([label, value]) => `<tr><td style="padding:10px 16px;color:#6B5E50;border-bottom:1px solid #E8DCC8">${escapeHtml(label)}</td><td style="padding:10px 16px;color:#2B2118;font-weight:600;border-bottom:1px solid #E8DCC8">${escapeHtml(value)}</td></tr>`)
    .join("");
  const html = `
<div style="background:#F2EAD9;padding:24px 12px;font-family:Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">
    <div style="background:#DDB29A;padding:24px 28px">
      <div style="font-size:28px;font-weight:700;color:#2B2118">Ɛdan</div>
      <div style="font-size:14px;color:#2B2118">Membership receipt</div>
    </div>
    <div style="padding:28px">
      <p style="margin:0 0 12px;font-size:16px;color:#2B2118">Thank you for joining Ɛdan. Your payment has been received.</p>
      <table cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;font-size:15px">${rowsHtml}</table>
      <p style="margin:24px 0 0;font-size:14px;line-height:1.5;color:#6B5E50">Your membership is confirmed once our team has reviewed your application.</p>
    </div>
  </div>
</div>`;
  return { subject: "Your Ɛdan membership payment receipt", html, text };
}

async function sendReceiptEmail(to: string, receipt: { subject: string; html: string; text: string }) {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    throw new Error("Receipt email is not configured");
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: RECEIPT_FROM,
      to: [to],
      subject: receipt.subject,
      html: receipt.html,
      text: receipt.text,
    }),
  });
  if (!response.ok) {
    throw new Error(`Sending the receipt email failed (${response.status})`);
  }
}

async function sendReceiptIfDue(supabaseUrl: string, serviceKey: string, reference: string) {
  const payment = await fetchReceiptPayment(supabaseUrl, serviceKey, reference);
  if (!payment || payment.status !== "success" || payment.receipt_sent_at) return;

  const applicantEmail = payment.membership_applications?.applicant_email;
  if (!applicantEmail) {
    throw new Error("Payment has no applicant email");
  }

  const claimed = await setReceiptSentAt(supabaseUrl, serviceKey, payment.id, new Date().toISOString(), true);
  if (!claimed) return;

  try {
    await sendReceiptEmail(applicantEmail, buildReceipt(payment));
  } catch (error) {
    await setReceiptSentAt(supabaseUrl, serviceKey, payment.id, null, false);
    throw error;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret || !supabaseUrl || !serviceKey) {
      return json({ error: "Payments are not configured" }, 500);
    }

    const rawBody = await req.text();
    const signature = req.headers.get("x-paystack-signature") ?? "";
    const expectedSignature = await hmacSha512Hex(secret, rawBody);
    if (!constantTimeEqual(signature, expectedSignature)) {
      return json({ error: "Invalid signature" }, 401);
    }

    const event = JSON.parse(rawBody);
    const eventType = typeof event?.event === "string" ? event.event : "";
    const reference = typeof event?.data?.reference === "string" ? event.data.reference : null;
    const eventKey = await sha256Hex(rawBody);

    if (eventType !== "charge.success" || !reference) {
      const outcome = await recordEvent(supabaseUrl, serviceKey, {
        p_event_key: eventKey,
        p_event_type: eventType,
        p_reference: reference,
        p_verified_transaction_id: null,
        p_verified_amount_pesewas: null,
        p_verified_currency: null,
        p_verified_paid_at: null,
      });
      return json({ received: true, outcome });
    }

    const verified = await verifyWithPaystack(secret, reference);
    const isSuccessful = verified.status === "success" && verified.reference === reference;

    const outcome = await recordEvent(supabaseUrl, serviceKey, {
      p_event_key: eventKey,
      p_event_type: eventType,
      p_reference: reference,
      p_verified_transaction_id: isSuccessful ? verified.id : null,
      p_verified_amount_pesewas: isSuccessful ? verified.amount : null,
      p_verified_currency: isSuccessful ? verified.currency : null,
      p_verified_paid_at: isSuccessful ? verified.paid_at : null,
    });

    if (outcome === "recorded" || outcome === "already_recorded") {
      await sendReceiptIfDue(supabaseUrl, serviceKey, reference);
    }

    return json({ received: true, outcome });
  } catch (error) {
    console.error("Paystack webhook failed:", error instanceof Error ? error.message : error);
    return json({ error: "Webhook processing failed" }, 500);
  }
});
