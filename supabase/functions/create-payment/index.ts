
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!url || !anonKey || !serviceKey) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Please sign in first" }, 401);
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: "Invalid session" }, 401);

  let input: { plan?: string; email?: string };
  try {
    input = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }

  const plans = {
    monthly: { amount: 100000, label: "Monthly affiliate" },
    annual: { amount: 800000, label: "Annual affiliate" },
  } as const;

  if (input.plan !== "monthly" && input.plan !== "annual") {
    return json({ error: "Invalid plan" }, 400);
  }

  const plan = input.plan;
  const email = user.email;
  if (!email) return json({ error: "Your account has no email address" }, 400);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  const application = await admin
    .from("membership_applications")
    .select("id")
    .eq("user_id", user.id)
    .eq("status", "pending")
    .not("submitted_at", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (application.error) {
    console.error("Application lookup failed:", application.error.message);
    return json({ error: "Could not load your application" }, 500);
  }

  if (!application.data) {
    return json({ error: "Please complete the membership form first" }, 400);
  }

  const applicationId = application.data.id;

  const tierUpdate = await admin
    .from("membership_applications")
    .update({ membership_tier: plan })
    .eq("id", applicationId);

  if (tierUpdate.error) {
    console.error("Tier update failed:", tierUpdate.error.message);
    return json({ error: "Could not save your membership choice" }, 500);
  }

  const reference = `edan-${crypto.randomUUID()}`;
  const payment = await admin
    .from("payment_transactions")
    .insert({
      reference,
      membership_application_id: applicationId,
      user_id: user.id,
      plan,
      amount_pesewas: plans[plan].amount,
      currency: "GHS",
      status: "pending",
    })
    .select("reference, amount_pesewas, currency")
    .single();

  if (payment.error || !payment.data) {
    console.error("Payment insert failed:", payment.error?.message);
    return json({ error: "Could not initialize your payment" }, 500);
  }

  return json({
    reference: payment.data.reference,
    amount: payment.data.amount_pesewas,
    currency: payment.data.currency,
    email,
  });
});
