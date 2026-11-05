/* =========================================
   ƐDAN — GUEST ACCOUNT AUTHENTICATION
   Requires Supabase JS v2 in login/index.html
   ========================================= */

(() => {
  "use strict";

  const SUPABASE_URL = "https://tqgjgnohqzmvkakqxhcm.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_R6DbjHgjZXrJSwVKLKvh0Q_Ks0BFYEV";

  // Folder URLs, from the site root (the site uses /folder/index.html pages)
  const LOGIN_PATH = "/login/";
  const AFTER_LOGIN_PATH = "/stay/?account=success";
  const GATHER_PATH = "/gather/";
  const PLAN_IDS = ["monthly", "annual"];
  const STAY_PATH_PREFIX = "/stay/";
  const NEXT_ALIASES = new Map([
    ["members", "/members/"],
    ["admin", "/dashboard/"]
  ]);

  if (
    SUPABASE_URL.startsWith("YOUR_") ||
    SUPABASE_PUBLISHABLE_KEY.startsWith("YOUR_")
  ) {
    console.error("Add your Supabase project URL and publishable key.");
    return;
  }

  const client = window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY
  );

  const loginTab = document.getElementById("loginTab");
  const signupTab = document.getElementById("signupTab");
  const loginForm = document.getElementById("loginForm");
  const signupForm = document.getElementById("signupForm");

  const title = document.getElementById("accountTitle");
  const eyebrow = document.getElementById("accountEyebrow");
  const description = document.getElementById("accountDescription");
  const message = document.getElementById("accountMessage");
  const switchText = document.getElementById("accountSwitch");

  const forgotButton = document.getElementById("forgotPassword");
  const switchToSignup = document.getElementById("switchToSignup");
  const recoveryForm = document.getElementById("recoveryForm");
  const isRecovery = new URLSearchParams(window.location.search).get("mode") === "recovery";

  function showMessage(text, type = "success") {
    message.textContent = text;
    message.className = `account__message is-${type}`;
    message.hidden = false;
  }

  function clearMessage() {
    message.textContent = "";
    message.hidden = true;
    message.className = "account__message";
  }

  function setBusy(form, busy) {
    const button = form.querySelector('[type="submit"]');

    button.disabled = busy;
    button.setAttribute("aria-busy", String(busy));

    if (busy) {
      button.dataset.originalText = button.textContent;
      button.textContent = "Please wait…";
    } else if (button.dataset.originalText) {
      button.textContent = button.dataset.originalText;
      delete button.dataset.originalText;
    }
  }

  function showLogin() {
    loginForm.hidden = false;
    signupForm.hidden = true;

    loginTab.classList.add("is-active");
    signupTab.classList.remove("is-active");

    loginTab.setAttribute("aria-selected", "true");
    signupTab.setAttribute("aria-selected", "false");

    title.textContent = "Log in";
    eyebrow.textContent = "WELCOME BACK";
    description.textContent = "Sign in to continue planning your stay.";

    switchText.replaceChildren(
      document.createTextNode("New to Ɛdan? ")
    );

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Create an account";
    button.addEventListener("click", showSignup);

    switchText.append(button);
    clearMessage();
  }

  function showSignup() {
    loginForm.hidden = true;
    signupForm.hidden = false;

    loginTab.classList.remove("is-active");
    signupTab.classList.add("is-active");

    loginTab.setAttribute("aria-selected", "false");
    signupTab.setAttribute("aria-selected", "true");

    title.textContent = "Create an account";
    eyebrow.textContent = "YOUR STAY STARTS HERE";
    description.textContent = "Create your guest account to continue.";

    switchText.replaceChildren(
      document.createTextNode("Already have an account? ")
    );

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Log in";
    button.addEventListener("click", showLogin);

    switchText.append(button);
    clearMessage();
  }

  function requestedPlan() {
    const plan = new URLSearchParams(window.location.search).get("plan");
    return PLAN_IDS.includes(plan) ? plan : null;
  }

  function requestedNext() {
    const next = new URLSearchParams(window.location.search).get("next");
    if (NEXT_ALIASES.has(next)) return NEXT_ALIASES.get(next);
    return next && next.startsWith(STAY_PATH_PREFIX) ? next : null;
  }

  function continueAfterLogin() {
    const next = requestedNext();
    if (next) {
      window.location.assign(next);
      return;
    }

    const plan = requestedPlan();
    window.location.assign(plan ? `${GATHER_PATH}?plan=${plan}` : AFTER_LOGIN_PATH);
  }

  function showRecoveryForm() {
    loginForm.hidden = true;
    signupForm.hidden = true;
    recoveryForm.hidden = false;

    loginTab.closest(".account__tabs").hidden = true;
    switchText.hidden = true;

    title.textContent = "Choose a new password";
    eyebrow.textContent = "ALMOST THERE";
    description.textContent = "Enter a new password for your account.";
    clearMessage();
  }

  loginTab.addEventListener("click", showLogin);
  signupTab.addEventListener("click", showSignup);
  switchToSignup.addEventListener("click", showSignup);

  signupForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearMessage();

    const formData = new FormData(signupForm);
    const fullName = String(formData.get("fullName") || "").trim();
    const email = String(formData.get("email") || "").trim();
    const password = String(formData.get("password") || "");
    const confirmPassword = String(
      formData.get("confirmPassword") || ""
    );

    if (password !== confirmPassword) {
      showMessage("Your passwords do not match.", "error");
      return;
    }

    if (password.length < 8) {
      showMessage("Your password must contain at least 8 characters.", "error");
      return;
    }

    setBusy(signupForm, true);

    try {
      const { data, error } = await client.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: fullName
          },
          emailRedirectTo: `${window.location.origin}${LOGIN_PATH}`
        }
      });

      if (error) throw error;

      if (data.session) {
        await client.from("membership_applications").insert({
          user_id: data.user.id,
          applicant_email: email,
          status: "pending"
        });

        const { error: notificationError } = await client.functions.invoke("admin-notifications", {
          body: { type: "signup", user_id: data.user.id }
        });
        if (notificationError) console.error("Signup notification failed:", notificationError.message);

        showMessage("Your account is ready. Taking you back to your stay…");
        window.setTimeout(continueAfterLogin, 1000);
      } else {
        showMessage(
          "Your account request has been received. Check your email for the confirmation link before logging in."
        );
        signupForm.reset();
      }
    } catch (error) {
      showMessage(
        error.message || "We couldn't create your account. Please try again.",
        "error"
      );
    } finally {
      setBusy(signupForm, false);
    }
  });

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearMessage();

    const formData = new FormData(loginForm);
    const email = String(formData.get("email") || "").trim();
    const password = String(formData.get("password") || "");

    setBusy(loginForm, true);

    try {
      const { error } = await client.auth.signInWithPassword({
        email,
        password
      });

      if (error) throw error;

      showMessage("You're signed in. Taking you back to your stay…");
      window.setTimeout(continueAfterLogin, 700);
    } catch (error) {
      showMessage(
        error.message || "We couldn't log you in. Check your details and try again.",
        "error"
      );
    } finally {
      setBusy(loginForm, false);
    }
  });

  forgotButton.addEventListener("click", async () => {
    clearMessage();

    const email = loginForm.elements.email.value.trim();

    if (!email) {
      showMessage("Enter your email address first, then choose forgot password.", "error");
      loginForm.elements.email.focus();
      return;
    }

    forgotButton.disabled = true;

    try {
      const { error } = await client.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}${LOGIN_PATH}?mode=recovery`
      });

      if (error) throw error;

      showMessage(
        "If password recovery is available for that address, you'll receive an email with the next steps."
      );
    } catch (error) {
      showMessage(
        error.message || "We couldn't send the reset email. Please try again.",
        "error"
      );
    } finally {
      forgotButton.disabled = false;
    }
  });

  client.auth.onAuthStateChange((event) => {
    if (event === "PASSWORD_RECOVERY") showRecoveryForm();
  });

  recoveryForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearMessage();

    const formData = new FormData(recoveryForm);
    const password = String(formData.get("password") || "");
    const confirmPassword = String(formData.get("confirmPassword") || "");

    if (password !== confirmPassword) {
      showMessage("Your passwords do not match.", "error");
      return;
    }

    if (password.length < 8) {
      showMessage("Your password must contain at least 8 characters.", "error");
      return;
    }

    setBusy(recoveryForm, true);

    try {
      const { error } = await client.auth.updateUser({ password });

      if (error) throw error;

      showMessage("Your password has been updated. Taking you back to your stay…");
      window.setTimeout(continueAfterLogin, 1000);
    } catch (error) {
      showMessage(
        error.message || "We couldn't update your password. Please try again.",
        "error"
      );
    } finally {
      setBusy(recoveryForm, false);
    }
  });

  // If a guest already has a valid session, don't show the login form.
  client.auth.getSession().then(({ data, error }) => {
    if (error) {
      console.error("Could not check the current session:", error.message);
      return;
    }

    if (isRecovery) return;

    if (data.session && (requestedPlan() || requestedNext())) {
      continueAfterLogin();
      return;
    }

    if (data.session) {
      title.textContent = "You're signed in";
      description.textContent =
        "Your guest account is ready. You can return to your stay.";
      loginForm.hidden = true;
      signupForm.hidden = true;
      loginTab.closest(".account__tabs").hidden = true;
      switchText.hidden = true;

      const button = document.createElement("button");
      button.type = "button";
      button.className = "account__submit";
      button.textContent = "Return to your stay";

      button.addEventListener("click", continueAfterLogin);

      document.querySelector(".account__panel").append(button);
    }
  });

  // Support the confirmation link returning to this page.
  const params = new URLSearchParams(window.location.search);

  if (params.get("error_description")) {
    showMessage(
      params.get("error_description").replace(/\+/g, " "),
      "error"
    );
  } else if (window.location.hash.includes("access_token")) {
    showMessage(
      "Your email confirmation link has been opened. You can now try logging in.",
      "success"
    );
  }

  if (params.get("mode") === "signup") {
    showSignup();
  }
})();