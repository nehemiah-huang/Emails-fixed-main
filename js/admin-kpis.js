import { supabase } from "./supabase-client.js";
import { setMessageText } from "./admin-table.js";

const KPI_KEYS = ["active_members", "pending_review", "expired", "total_bookings", "appointments"];

const kpiError = document.getElementById("kpiError");

function setKpiValue(key, text) {
  const card = document.querySelector(`[data-kpi="${key}"]`);
  card.querySelector(".admin__kpi-value").textContent = text;
}

function isValidKpis(data) {
  return data !== null && typeof data === "object" && KPI_KEYS.every(key => Number.isInteger(data[key]));
}

export async function loadKpis() {
  const { data, error } = await supabase.rpc("admin_dashboard_kpis");

  if (error || !isValidKpis(data)) {
    setMessageText(kpiError, "Membership stats could not be loaded. Please refresh the dashboard.");
    KPI_KEYS.forEach(key => setKpiValue(key, "—"));
    return;
  }

  setMessageText(kpiError, "");
  KPI_KEYS.forEach(key => {
    setKpiValue(key, data[key].toLocaleString("en-GB"));
  });
}
