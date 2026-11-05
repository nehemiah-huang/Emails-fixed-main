import { supabase } from "./supabase-client.js";
import { loadMemberships } from "./admin-memberships.js";
import { loadStayBookings } from "./admin-bookings.js";
import { loadAppointments } from "./admin-appointments.js";
import { loadAvailability } from "./admin-availability.js";
import { loadMemberContent } from "./admin-members-content.js";
import { loadMemberPageSettings } from "./admin-member-settings.js";
import { loadMemberInsights } from "./admin-member-insights.js";
import { loadKpis } from "./admin-kpis.js";
import "./admin-nav.js";

const message = document.getElementById("adminMessage");
const dashboard = document.getElementById("adminDashboard");
const restricted = document.getElementById("adminRestricted");
const logoutButton = document.getElementById("adminLogout");

function setMessage(text, isError = false) {
  message.textContent = text;
  message.classList.toggle("admin__message--error", isError);
}

async function refreshDashboard() {
  await Promise.all([
    loadKpis(),
    loadMemberships(),
    loadStayBookings(),
    loadAppointments(),
    loadAvailability(),
    loadMemberContent(),
    loadMemberPageSettings(),
    loadMemberInsights()
  ]);

  const { error: reminderError } = await supabase.functions.invoke("admin-notifications", {
    body: { type: "daily_reminder" }
  });
  if (reminderError) console.error("Daily notification failed:", reminderError.message);
}

logoutButton.addEventListener("click", async () => {
  logoutButton.disabled = true;
  const { error } = await supabase.auth.signOut();

  if (error) {
    setMessage("Couldn't log out. Please try again.", true);
    logoutButton.disabled = false;
    return;
  }

  window.location.replace("/login/");
});

async function init() {
  const { data, error } = await supabase.auth.getSession();

  if (error || !data.session) {
    window.location.replace("/login/?next=admin");
    return;
  }

  const { data: allowed, error: permissionError } = await supabase.rpc("is_edan_admin");

  if (permissionError || allowed !== true) {
    restricted.hidden = false;
    setMessage("");
    return;
  }

  dashboard.hidden = false;
  setMessage("");
  await refreshDashboard();
}

init().catch(error => {
  console.error("Dashboard error:", error);
  setMessage("Something went wrong loading the dashboard. Refresh and try again.", true);
});