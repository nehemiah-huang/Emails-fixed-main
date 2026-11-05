import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

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

const PLAN_LABELS: Record<string, string> = {
  monthly: "Monthly affiliate",
  annual: "Annual affiliate",
};

const PEACH = rgb(0xdd / 255, 0xb2 / 255, 0x9a / 255);
const PAPER = rgb(0xf2 / 255, 0xea / 255, 0xd9 / 255);
const INK = rgb(0x2b / 255, 0x21 / 255, 0x18 / 255);
const MUTED = rgb(0x6b / 255, 0x5e / 255, 0x50 / 255);

type ReceiptPayment = {
  reference: string;
  plan: string;
  amount_pesewas: number;
  currency: string;
  paid_at: string | null;
  membership_applications: { applicant_email: string; created_at: string } | null;
};

function formatDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("en-GB", {
    timeZone: "Africa/Accra",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

async function loadOwnedPayment(
  supabaseUrl: string,
  serviceKey: string,
  userId: string,
  reference: string,
): Promise<ReceiptPayment | null> {
  const select = "reference,plan,amount_pesewas,currency,paid_at,membership_applications(applicant_email,created_at)";
  const query = new URLSearchParams({
    reference: `eq.${reference}`,
    user_id: `eq.${userId}`,
    status: "eq.success",
    select,
  });
  const response = await fetch(`${supabaseUrl}/rest/v1/payment_transactions?${query}`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!response.ok) {
    throw new Error(`Loading the payment failed (${response.status})`);
  }
  const rows = (await response.json()) as ReceiptPayment[];
  return rows[0] ?? null;
}

async function userIdFromToken(supabaseUrl: string, serviceKey: string, accessToken: string): Promise<string | null> {
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) return null;
  const user = (await response.json()) as { id?: unknown };
  return typeof user.id === "string" ? user.id : null;
}

async function buildReceiptPdf(payment: ReceiptPayment): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([420, 595]);
  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);

  page.drawRectangle({ x: 0, y: 0, width: 420, height: 595, color: PAPER });
  page.drawRectangle({ x: 0, y: 495, width: 420, height: 100, color: PEACH });
  page.drawText("Edan", { x: 40, y: 540, size: 30, font: bold, color: INK });
  page.drawText("Membership receipt", { x: 40, y: 512, size: 12, font: regular, color: INK });

  const amount = `${payment.currency} ${(payment.amount_pesewas / 100).toFixed(2)}`;
  const rows: [string, string][] = [
    ["Membership", PLAN_LABELS[payment.plan] ?? payment.plan],
    ["Applicant", payment.membership_applications?.applicant_email ?? ""],
    ["Application submitted", formatDate(payment.membership_applications?.created_at ?? null)],
    ["Amount paid", amount],
    ["Date paid", formatDate(payment.paid_at)],
    ["Payment reference", payment.reference],
  ];

  let y = 460;
  for (const [label, value] of rows) {
    page.drawText(label, { x: 40, y, size: 10, font: regular, color: MUTED });
    page.drawText(value, { x: 180, y, size: 11, font: bold, color: INK });
    page.drawLine({ start: { x: 40, y: y - 10 }, end: { x: 380, y: y - 10 }, thickness: 0.5, color: PEACH });
    y -= 36;
  }

  page.drawText("Thank you for joining Edan.", { x: 40, y: 140, size: 12, font: bold, color: INK });
  page.drawText("Your membership is confirmed once our team has reviewed your application.", {
    x: 40,
    y: 120,
    size: 9,
    font: regular,
    color: MUTED,
  });

  return doc.save();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Receipts are not configured" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const accessToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!accessToken) {
      return json({ error: "Sign in to download your receipt" }, 401);
    }

    const body = (await req.json().catch(() => null)) as { reference?: unknown } | null;
    const reference = typeof body?.reference === "string" ? body.reference : "";
    if (!reference) {
      return json({ error: "A payment reference is required" }, 400);
    }

    const userId = await userIdFromToken(supabaseUrl, serviceKey, accessToken);
    if (!userId) {
      return json({ error: "Sign in to download your receipt" }, 401);
    }

    const payment = await loadOwnedPayment(supabaseUrl, serviceKey, userId, reference);
    if (!payment) {
      return json({ error: "Receipt not found" }, 404);
    }

    const pdf = await buildReceiptPdf(payment);
    return new Response(pdf, {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/pdf",
        "Cache-Control": "no-store",
        "Content-Disposition": `attachment; filename="edan-receipt-${reference}.pdf"`,
      },
    });
  } catch (error) {
    console.error("Receipt download failed:", error instanceof Error ? error.message : error);
    return json({ error: "Receipt download failed" }, 500);
  }
});
