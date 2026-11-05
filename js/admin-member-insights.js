import { supabase } from "./supabase-client.js";
import { renderEmptyRow, setMessageText } from "./admin-table.js";

const body = document.getElementById("memberInsightsBody");
const errorMessage = document.getElementById("memberInsightsError");

const LABELS = {
  page: "Members page",
  gathering: "Gathering",
  research: "Research",
  process: "In Process",
  bonus_video: "Bonus video"
};

function formatDate(value) {
  return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "—";
}

export async function loadMemberInsights() {
  if (!body) return;
  setMessageText(errorMessage, "");
  const { data, error } = await supabase.rpc("admin_member_content_insights");

  if (error) {
    setMessageText(errorMessage, "Member activity could not be loaded.");
    renderEmptyRow(body, 4, "Member activity is unavailable.");
    return;
  }

  if (!data?.length) {
    renderEmptyRow(body, 4, "No member activity recorded yet.");
    return;
  }

  body.replaceChildren(...data.map(item => {
    const row = document.createElement("tr");
    [LABELS[item.content_type] || item.content_type, item.content_title || "Published item", item.view_count.toLocaleString("en-GB"), formatDate(item.last_viewed_at)]
      .forEach(value => {
        const cell = document.createElement("td");
        cell.textContent = value;
        row.append(cell);
      });
    return row;
  }));
}
