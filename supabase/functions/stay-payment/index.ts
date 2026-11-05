import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const PAYSTACK_BASE_URL = "https://api.paystack.co";

type BookingRow = {
  id: string;
  booking_reference: string;
  status: string;
  total_ghs: number;
  hold_expires_at: string | null;
  paystack_reference: string | null;
  paystack_authorization_url: string | null;
  paystack_access_code: string | null;
  guest_email: string;
};

type PaystackTransaction = {
  id: number;
  status: string;
  reference: string;
  amount: number;
  currency: string;
  paid_at: string | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

async function paystackRequest(
  secret: string,
  path: string,
  init: { method?: string; body?: unknown } = {},
): Promise<{ ok: boolean; data: any }> {
  const response = await fetch(`${PAYSTACK_BASE_URL}${path}`, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/json",
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const payload = await response.json().catch(() => null);
  return { ok: response.ok && payload?.status === true, data: payload?.data ?? null };
}

function isTransaction(value: unknown): value is PaystackTransaction {
  const t = value as PaystackTransaction;
  return !!t && typeof t.status === "string" && typeof t.reference === "string" &&
    typeof t.amount === "number" && typeof t.currency === "string";
}

function holdHasExpired(booking: BookingRow) {
  return !booking.hold_expires_at || new Date(booking.hold_expires_at).getTime() <= Date.now();
}

async function currentStatus(admin: ReturnType<typeof createClient>, bookingId: string) {
  const { data, error } = await admin
    .from("stay_bookings")
    .select("status")
    .eq("id", bookingId)
    .maybeSingle();
  if (error) throw error;
  return data?.status ?? null;
}

async function initializePayment(
  admin: ReturnType<typeof createClient>,
  secret: string,
  booking: BookingRow,
  callbackUrl: string,
) {
  if (booking.status !== "pending_payment" || holdHasExpired(booking)) {
    return json({ error: "This booking is no longer waiting for payment. Please start again." }, 409);
  }

  if (booking.paystack_authorization_url && booking.paystack_access_code) {
    return json({
      access_code: booking.paystack_access_code,
      authorization_url: booking.paystack_authorization_url,
    });
  }

  const { error: prepareError } = await admin.rpc("prepare_stay_payment", { p_booking_id: booking.id });
  if (prepareError) {
    console.error("Stay payment preparation failed:", prepareError.message);
    return json({ error: "This booking could not be prepared for payment." }, 409);
  }

  const initialized = await paystackRequest(secret, "/transaction/initialize", {
    method: "POST",
    body: {
      email: booking.guest_email,
      amount: booking.total_ghs * 100,
      currency: "GHS",
      reference: booking.paystack_reference,
      callback_url: callbackUrl,
      metadata: { source: "stay", booking_id: booking.id, booking_reference: booking.booking_reference },
    },
  });

  const authorizationUrl = initialized.data?.authorization_url;
  const accessCode = initialized.data?.access_code;
  if (!initialized.ok || typeof authorizationUrl !== "string" || typeof accessCode !== "string") {
    return json({ error: "Payment could not be started. Please try again." }, 502);
  }

  const { error: saveError } = await admin
    .from("stay_bookings")
    .update({ paystack_authorization_url: authorizationUrl, paystack_access_code: accessCode })
    .eq("id", booking.id);
  if (saveError) throw saveError;

  return json({ access_code: accessCode, authorization_url: authorizationUrl });
}

async function verifyPayment(
  admin: ReturnType<typeof createClient>,
  secret: string,
  booking: BookingRow,
) {
  if (booking.status === "confirmed" || !booking.paystack_reference) {
    return json({ status: booking.status });
  }

  const verified = await paystackRequest(
    secret,
    `/transaction/verify/${encodeURIComponent(booking.paystack_reference)}`,
  );

  if (isTransaction(verified.data) && verified.data.reference === booking.paystack_reference) {
    if (verified.data.status === "success") {
      const { error } = await admin.rpc("confirm_stay_payment", {
        p_reference: booking.paystack_reference,
        p_transaction_id: verified.data.id,
        p_amount_pesewas: verified.data.amount,
        p_currency: verified.data.currency,
        p_paid_at: verified.data.paid_at,
      });
      if (error) throw error;
    } else if (verified.data.status === "failed") {
      const { error } = await admin.rpc("mark_stay_payment_failed", {
        p_reference: booking.paystack_reference,
      });
      if (error) throw error;
    }
  }

  return json({ status: await currentStatus(admin, booking.id) });
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
    const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!supabaseUrl || !serviceKey || !secret) {
      return json({ error: "Payments are not configured yet." }, 500);
    }

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return json({ error: "Please log in to continue." }, 401);
    }

    const body = await req.json().catch(() => null);
    const action = body?.action;
    const bookingId = typeof body?.booking_id === "string" ? body.booking_id : "";
    if (!bookingId || (action !== "initialize" && action !== "verify")) {
      return json({ error: "Invalid request." }, 400);
    }

    const { data: booking, error: bookingError } = await admin
      .from("stay_bookings")
      .select("id, booking_reference, status, total_ghs, hold_expires_at, paystack_reference, paystack_authorization_url, paystack_access_code, guest_email")
      .eq("id", bookingId)
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (bookingError) throw bookingError;
    if (!booking) {
      return json({ error: "That booking could not be found." }, 404);
    }

    if (action === "verify") {
      return await verifyPayment(admin, secret, booking);
    }

    const callbackUrl = typeof body?.callback_url === "string" ? body.callback_url : "";
    if (!/^https?:\/\//.test(callbackUrl)) {
      return json({ error: "Invalid return address." }, 400);
    }

    return await initializePayment(admin, secret, booking, callbackUrl);
  } catch (error) {
    console.error("Stay payment failed:", error instanceof Error ? error.message : error);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
