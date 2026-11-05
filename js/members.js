
/* =========================================
   ƐDAN — MEMBER ACCESS
   Requires Supabase JS v2
   ========================================= */

(() => {
  "use strict";

  // Use the same public credentials as account.js.
  const SUPABASE_URL = "https://tqgjgnohqzmvkakqxhcm.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_R6DbjHgjZXrJSwVKLKvh0Q_Ks0BFYEV";

  const message = document.getElementById("membersMessage");
  const greeting = document.getElementById("memberGreeting");
  const heroHeading = document.getElementById("heroHeading");
  const heroTier = document.getElementById("heroTier");
  const intro = document.getElementById("memberIntro");
  const tierLabel = document.getElementById("memberTier");
  const statusLabel = document.getElementById("memberStatus");
  const expiryLabel = document.getElementById("memberExpiry");
  const benefitList = document.getElementById("benefitList");
  const gatedBlocks = document.querySelectorAll(".members__gated");
  const annualBlocks = document.querySelectorAll(".members__block--annual");
  const annualLockNotes = document.querySelectorAll("[data-annual-lock]");
  const annualContent = document.querySelectorAll("[data-annual-content]");
  const annualBenefits = () => benefitList.querySelectorAll(".members__benefit--annual");
  const logoutButton = document.getElementById("memberLogout");
  const receiptPanel = document.getElementById("receiptPanel");
  const downloadButton = document.getElementById("downloadReceipt");
  const receiptMessage = document.getElementById("receiptMessage");

  const expiryFormat = new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "long",
    year: "numeric"
  });

  function showMessage(text) {
    message.textContent = text;
  }

  function setMembershipView(membership) {
    const tier = membership?.membership_tier;
    const status = membership?.membership_status;

    tierLabel.textContent = tier || "Not assigned";
    statusLabel.textContent = status || "Pending approval";
    expiryLabel.textContent = membership?.expires_at
      ? expiryFormat.format(new Date(membership.expires_at))
      : "—";

    if (tier) {
      heroTier.textContent = `${tier} member`;
      heroTier.hidden = false;
    }

    const active =
      status === "active" &&
      (tier === "monthly" || tier === "annual") &&
      (!membership.expires_at ||
        new Date(membership.expires_at).getTime() > Date.now());

    if (!active) {
      intro.textContent =
        "Your account is ready. Your membership is awaiting activation or renewal by the Ɛdan team.";

      gatedBlocks.forEach(block => {
        block.hidden = true;
      });
      benefitList.hidden = true;
      return;
    }

    intro.textContent =
      `Your ${tier} membership is active. Welcome to your Ɛdan member space.`;

    gatedBlocks.forEach(block => {
      block.hidden = false;
    });
    benefitList.hidden = false;

    const isAnnual = tier === "annual";

    annualBlocks.forEach(block => {
      block.classList.toggle("is-locked", !isAnnual);
    });
    annualLockNotes.forEach(note => {
      note.hidden = isAnnual;
    });
    annualContent.forEach(content => {
      content.hidden = !isAnnual;
    });
    annualBenefits().forEach(item => {
      item.hidden = !isAnnual;
    });
  }

  function setPageImage(selector, path) {
    if (!path) return;
    const image = document.querySelector(selector);
    if (image) image.src = path;
  }

  function setPageCopy(selector, value) {
    if (!value) return;
    const element = document.querySelector(selector);
    if (element) element.textContent = value;
  }

  function applyPageSettings(settings) {
    setPageCopy(".members__hero .members__eyebrow", settings.hero_eyebrow);
    setPageCopy(".members__intro .members__eyebrow", settings.membership_eyebrow);
    setPageCopy("#memberIntro", settings.membership_intro);
    setPageImage(".members__hero-image", settings.hero_image_path);

    const sections = [
      ["community", "community"],
      ["process", "process"],
      ["gather", "gather"],
      ["research", "research"],
      ["bonus", "bonus"],
      ["appointments", "appointment"]
    ];
    sections.forEach(([key, className]) => {
      const section = document.querySelector(`.members__${className}-hero`);
      if (!section) return;
      setPageImage(`.members__${className}-hero img`, settings[`${key}_image_path`]);
      setPageCopy(`.members__${className}-hero-copy .members__eyebrow`, settings[`${key}_eyebrow`]);
      setPageCopy(`.members__${className}-hero-copy h2`, settings[`${key}_title`]);
      setPageCopy(`.members__${className}-hero-copy p`, settings[`${key}_description`]);
    });

    if (Array.isArray(settings.benefits)) {
      const list = benefitList.querySelector("ol");
      list.replaceChildren(...settings.benefits.map((benefit, index) => {
        const item = document.createElement("li");
        item.textContent = String(benefit);
        if (index >= settings.benefits.length - 2) item.className = "members__benefit--annual";
        return item;
      }));
    }
  }

  async function loadPageSettings(client) {
    const { data, error } = await client
      .from("member_page_settings")
      .select("*")
      .eq("id", "default")
      .maybeSingle();

    if (error) {
      console.error("Members page settings lookup failed:", error);
      return;
    }

    if (data) applyPageSettings(data);
  }

  async function setupReceipt(client, accessToken, userId) {
    const { data: payment, error } = await client
      .from("payment_transactions")
      .select("reference")
      .eq("user_id", userId)
      .eq("status", "success")
      .order("paid_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error("Receipt lookup failed:", error);
      return;
    }
    if (!payment?.reference) return;

    receiptPanel.hidden = false;
    downloadButton.addEventListener("click", () =>
      downloadReceipt(accessToken, payment.reference)
    );
  }

  async function downloadReceipt(accessToken, reference) {
    downloadButton.disabled = true;
    receiptMessage.textContent = "Preparing your receipt…";

    try {
      const response = await fetch(`${SUPABASE_URL}/functions/v1/payment-receipt`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          apikey: SUPABASE_PUBLISHABLE_KEY,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ reference })
      });
      if (!response.ok) {
        throw new Error(`Receipt download failed (${response.status})`);
      }

      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `edan-receipt-${reference}.pdf`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      receiptMessage.textContent = "";
    } catch (error) {
      console.error("Receipt download error:", error);
      receiptMessage.textContent = "We couldn't download your receipt. Please try again.";
    } finally {
      downloadButton.disabled = false;
    }
  }

  async function init() {
    if (
      SUPABASE_URL.startsWith("YOUR_") ||
      SUPABASE_PUBLISHABLE_KEY.startsWith("YOUR_")
    ) {
      showMessage("Add your Supabase Project URL and publishable key to js/members.js.");
      return;
    }

    if (!window.supabase) {
      showMessage("Supabase did not load. Refresh the page and try again.");
      return;
    }

    const client = window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY
    );

    const { data: sessionData, error: sessionError } =
      await client.auth.getSession();

    if (sessionError || !sessionData.session) {
      window.location.replace("/login/?next=members");
      return;
    }

    const user = sessionData.session.user;
    const fullName = user.user_metadata?.full_name?.trim();

    heroHeading.textContent = fullName
      ? `Welcome back, ${fullName.split(" ")[0]}.`
      : "Welcome back.";
    greeting.textContent = fullName
      ? `Welcome, ${fullName}.`
      : "Welcome to Ɛdan.";

    setupReceipt(client, sessionData.session.access_token, user.id);

    const { data: membership, error: membershipError } = await client
      .from("memberships")
      .select("membership_tier, membership_status, started_at, expires_at")
      .eq("user_id", user.id)
      .maybeSingle();

    if (membershipError) {
      console.error("Membership lookup failed:", membershipError);
      showMessage("We couldn't load your membership. Please try again later.");
      return;
    }

    if (!membership) {
      setMembershipView(null);
      return;
    }

    if (
      membership.membership_status === "active" &&
      membership.expires_at &&
      new Date(membership.expires_at).getTime() <= Date.now()
    ) {
      setMembershipView({
        ...membership,
        membership_status: "expired"
      });
      return;
    }

    if (
      membership.membership_status === "active" &&
      ["monthly", "annual"].includes(membership.membership_tier)
    ) {
      await loadPageSettings(client);
    }

    setMembershipView(membership);
  }

  logoutButton.addEventListener("click", async () => {
    logoutButton.disabled = true;

    const client = window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY
    );

    const { error } = await client.auth.signOut();

    if (error) {
      showMessage("We couldn't log you out. Please try again.");
      logoutButton.disabled = false;
      return;
    }

    window.location.replace("/");
  });

  init().catch(error => {
    console.error("Member page error:", error);
    showMessage("Something went wrong while loading your membership.");
  });
})();
