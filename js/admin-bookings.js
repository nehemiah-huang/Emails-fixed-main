import { supabase } from "./supabase-client.js";
import {
  createActionCell,
  createTableButton,
  createRow,
  formatDay,
  formatMoney,
  localIsoDate,
  renderEmptyRow,
  setMessageText
} from "./admin-table.js";
import { fetchRooms } from "./admin-availability.js";

const BOOKING_LIMIT = 100;
const BOOKING_COLUMNS = "id, booking_reference, guest_name, guest_email, guest_phone, check_in, check_out, guests, breakfast_included, nightly_rate_ghs, total_ghs, status, source, notes, checked_in_at, stay_rooms(name)";
const RATES = { room: 650, breakfast: 700 };
const DELETABLE_BOOKING_STATUSES = new Set(["pending_payment", "payment_failed", "cancelled"]);

const STATUS_LABELS = {
  pending_payment: "Pending payment",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
  completed: "Completed",
  payment_failed: "Payment failed"
};

const bookingsBody = document.getElementById("bookingsBody");
const bookingsError = document.getElementById("bookingsError");
const bookingSearch = document.getElementById("bookingSearch");
const addBookingButton = document.getElementById("addBookingButton");
const bookingDialog = document.getElementById("bookingDialog");
const bookingDetails = document.getElementById("bookingDetails");
const bookingDetailError = document.getElementById("bookingDetailError");
const bookingActions = document.getElementById("bookingActions");
const bookingDialogClose = document.getElementById("bookingDialogClose");
const manualBookingDialog = document.getElementById("manualBookingDialog");
const manualBookingForm = document.getElementById("manualBookingForm");
const manualRoom = document.getElementById("manualRoom");
const manualRate = document.getElementById("manualRate");
const manualCheckIn = document.getElementById("manualCheckIn");
const manualCheckOut = document.getElementById("manualCheckOut");
const manualGuests = document.getElementById("manualGuests");
const manualName = document.getElementById("manualName");
const manualEmail = document.getElementById("manualEmail");
const manualPhone = document.getElementById("manualPhone");
const manualNotes = document.getElementById("manualNotes");
const manualTotal = document.getElementById("manualTotal");
const manualError = document.getElementById("manualError");
const manualSubmit = document.getElementById("manualSubmit");
const manualCancel = document.getElementById("manualCancel");

let searchTimer = 0;

function nightsBetween(checkIn, checkOut) {
  const start = Date.parse(`${checkIn}T00:00:00Z`);
  const end = Date.parse(`${checkOut}T00:00:00Z`);
  return Math.round((end - start) / 86400000);
}

function sourceLabel(booking) {
  return booking.source === "manual" ? "Manual" : "Online";
}

function statusLabel(booking) {
  if (booking.status === "confirmed" && booking.checked_in_at) return "Checked in";
  return STATUS_LABELS[booking.status] ?? booking.status;
}

function selectedView() {
  return document.querySelector("[data-booking-view][aria-pressed='true']")?.dataset.bookingView ?? "upcoming";
}

function cleanSearchTerm(value) {
  return value.replace(/[^\p{L}\p{N}\s@._-]/gu, "").trim().slice(0, 80);
}

function renderBookingRow(booking) {
  const row = createRow([
    booking.booking_reference,
    booking.guest_name,
    booking.stay_rooms?.name ?? "—",
    `${formatDay(booking.check_in)} to ${formatDay(booking.check_out)}`,
    String(booking.guests),
    formatMoney(booking.total_ghs),
    statusLabel(booking),
    sourceLabel(booking)
  ], ["Reference", "Guest", "Room", "Dates", "Guests", "Total", "Status", "Source"]);

  const viewButton = createTableButton("View", "admin__button admin__button--small", { bookingId: booking.id });
  const deleteButton = DELETABLE_BOOKING_STATUSES.has(booking.status)
    ? createTableButton("Delete", "admin__button admin__button--small admin__button--danger", { deleteBookingId: booking.id })
    : null;
  row.append(createActionCell(viewButton, deleteButton));

  return row;
}

export async function loadStayBookings() {
  const view = selectedView();
  const today = localIsoDate();

  let query = supabase
    .from("stay_bookings")
    .select(BOOKING_COLUMNS)
    .order("check_in", { ascending: view !== "past" })
    .limit(BOOKING_LIMIT);

  if (view === "upcoming") query = query.gte("check_out", today);
  if (view === "past") query = query.lt("check_out", today);

  const term = cleanSearchTerm(bookingSearch.value);
  if (term) {
    query = query.or(
      `guest_name.ilike.*${term}*,guest_email.ilike.*${term}*,booking_reference.ilike.*${term}*`
    );
  }

  const { data, error } = await query;

  if (error) {
    setMessageText(bookingsError, "Bookings could not be loaded. Please refresh the dashboard.");
    renderEmptyRow(bookingsBody, 9, "Bookings could not be loaded.");
    return;
  }

  setMessageText(bookingsError, "");

  if (!data.length) {
    renderEmptyRow(bookingsBody, 9, term ? "No bookings match that search." : "No bookings in this view.");
    return;
  }

  bookingsBody.replaceChildren(...data.map(renderBookingRow));
}

function addDetail(list, label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const detail = document.createElement("dd");
  detail.textContent = value;
  list.append(term, detail);
}

function renderBookingDetails(booking) {
  const list = document.createElement("dl");
  list.className = "admin__details";

  addDetail(list, "Reference", booking.booking_reference);
  addDetail(list, "Status", statusLabel(booking));
  if (booking.checked_in_at) {
    addDetail(
      list,
      "Checked in",
      new Date(booking.checked_in_at).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short" })
    );
  }
  addDetail(list, "Room", booking.stay_rooms?.name ?? "—");
  addDetail(list, "Check-in", formatDay(booking.check_in));
  addDetail(list, "Check-out", formatDay(booking.check_out));
  addDetail(list, "Nights", String(nightsBetween(booking.check_in, booking.check_out)));
  addDetail(list, "Guests", String(booking.guests));
  addDetail(
    list,
    "Rate",
    `${booking.breakfast_included ? "With breakfast" : "Room only"} (${formatMoney(booking.nightly_rate_ghs)} / night)`
  );
  addDetail(list, "Total", formatMoney(booking.total_ghs));
  addDetail(
    list,
    "Payment source",
    booking.source === "manual"
      ? "Manual booking, not linked to a Paystack payment"
      : "Online booking (Paystack)"
  );
  addDetail(list, "Guest name", booking.guest_name);
  addDetail(list, "Email", booking.guest_email);
  addDetail(list, "Phone", booking.guest_phone);
  addDetail(list, "Notes", booking.notes || "—");

  bookingDetails.replaceChildren(list);
}

function actionButton(label, action, className) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.textContent = label;
  button.dataset.bookingAction = action;
  return button;
}

function renderBookingActions(booking) {
  bookingActions.dataset.bookingId = booking.id;

  if (booking.status !== "confirmed") {
    bookingActions.replaceChildren();
    return;
  }

  const buttons = [];
  if (!booking.checked_in_at) {
    buttons.push(actionButton("Check in guest", "check-in", "admin__button admin__button--solid"));
  }
  buttons.push(
    actionButton("Mark as completed", "completed", "admin__button"),
    actionButton("Cancel booking", "cancelled", "admin__button admin__button--danger")
  );

  bookingActions.replaceChildren(...buttons);
}

async function openBookingDetails(bookingId) {
  setMessageText(bookingDetailError, "");
  bookingDetails.replaceChildren(document.createTextNode("Loading booking…"));
  bookingActions.replaceChildren();
  bookingDialog.showModal();

  const { data, error } = await supabase
    .from("stay_bookings")
    .select(BOOKING_COLUMNS)
    .eq("id", bookingId)
    .maybeSingle();

  if (error || !data) {
    bookingDetails.replaceChildren();
    setMessageText(bookingDetailError, "That booking could not be found. Please refresh and try again.");
    return;
  }

  renderBookingDetails(data);
  renderBookingActions(data);
}

async function deleteBooking(button) {
  if (!window.confirm("Delete this booking permanently? Its dates will be free for other guests.")) return;

  button.disabled = true;
  setMessageText(bookingsError, "");

  const { data, error } = await supabase
    .from("stay_bookings")
    .delete()
    .eq("id", button.dataset.deleteBookingId)
    .select("id");

  if (error || !data.length) {
    setMessageText(bookingsError, "That booking could not be deleted. Please try again.");
    button.disabled = false;
    return;
  }

  await loadStayBookings();
}

async function runBookingAction(bookingId, rpcName, params) {
  bookingActions.querySelectorAll("button").forEach(button => { button.disabled = true; });
  setMessageText(bookingDetailError, "");

  const { error } = await supabase.rpc(rpcName, { p_booking_id: bookingId, ...params });

  if (error) {
    setMessageText(bookingDetailError, "That booking could not be updated. Please try again.");
    bookingActions.querySelectorAll("button").forEach(button => { button.disabled = false; });
    return;
  }

  bookingDialog.close();
  await loadStayBookings();
}

function changeBookingStatus(bookingId, status) {
  if (status === "cancelled" && !window.confirm("Cancel this booking? The room's dates will become available.")) {
    return;
  }

  return runBookingAction(bookingId, "admin_set_booking_status", { p_status: status });
}

function checkInBooking(bookingId) {
  return runBookingAction(bookingId, "admin_check_in_booking", {});
}

function updateManualTotal() {
  const nights = nightsBetween(manualCheckIn.value, manualCheckOut.value);

  if (!manualCheckIn.value || !manualCheckOut.value || nights < 1) {
    manualTotal.textContent = "Choose check-in and check-out dates to see the total.";
    return;
  }

  const rate = RATES[manualRate.value];
  const nightLabel = nights === 1 ? "night" : "nights";
  manualTotal.textContent =
    `${nights} ${nightLabel} × ${formatMoney(rate)} = ${formatMoney(nights * rate)} total`;
}

async function openManualBooking() {
  manualBookingForm.reset();
  setMessageText(manualError, "");
  manualCheckIn.min = localIsoDate();
  manualTotal.textContent = "Choose check-in and check-out dates to see the total.";
  manualSubmit.disabled = true;
  manualRoom.replaceChildren(new Option("Loading rooms…"));
  manualBookingDialog.showModal();

  try {
    const rooms = (await fetchRooms()).filter(room => room.is_active);

    if (!rooms.length) {
      manualRoom.replaceChildren();
      setMessageText(manualError, "Add a room in the Rooms section before creating a booking.");
      return;
    }

    manualRoom.replaceChildren(...rooms.map(room => {
      const option = document.createElement("option");
      option.value = room.id;
      option.textContent = room.name;
      return option;
    }));
    manualSubmit.disabled = false;
  } catch (error) {
    setMessageText(manualError, "Rooms could not be loaded. Please refresh and try again.");
  }
}

async function saveManualBooking(event) {
  event.preventDefault();
  setMessageText(manualError, "");

  if (!manualBookingForm.reportValidity()) return;

  if (nightsBetween(manualCheckIn.value, manualCheckOut.value) < 1) {
    setMessageText(manualError, "Check-out must be at least one night after check-in.");
    return;
  }

  manualSubmit.disabled = true;

  const { error } = await supabase.rpc("admin_create_manual_booking", {
    p_room_id: manualRoom.value,
    p_check_in: manualCheckIn.value,
    p_check_out: manualCheckOut.value,
    p_guests: Number(manualGuests.value),
    p_breakfast_included: manualRate.value === "breakfast",
    p_guest_name: manualName.value,
    p_guest_email: manualEmail.value,
    p_guest_phone: manualPhone.value,
    p_notes: manualNotes.value
  });

  manualSubmit.disabled = false;

  if (error) {
    setMessageText(manualError, "The booking could not be saved. Please check the dates and try again.");
    return;
  }

  manualBookingDialog.close();
  await loadStayBookings();
}

document.querySelectorAll("[data-booking-view]").forEach(button => {
  button.addEventListener("click", async () => {
    document.querySelectorAll("[data-booking-view]").forEach(other => {
      other.setAttribute("aria-pressed", String(other === button));
    });
    await loadStayBookings();
  });
});

bookingSearch.addEventListener("input", () => {
  window.clearTimeout(searchTimer);
  searchTimer = window.setTimeout(loadStayBookings, 300);
});

bookingsBody.addEventListener("click", (event) => {
  const deleteButton = event.target.closest("button[data-delete-booking-id]");
  if (deleteButton) {
    deleteBooking(deleteButton);
    return;
  }

  const button = event.target.closest("button[data-booking-id]");
  if (!button) return;
  openBookingDetails(button.dataset.bookingId);
});

bookingActions.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-booking-action]");
  if (!button) return;

  const bookingId = bookingActions.dataset.bookingId;
  const action = button.dataset.bookingAction;
  if (action === "check-in") {
    checkInBooking(bookingId);
  } else {
    changeBookingStatus(bookingId, action);
  }
});

bookingDialogClose.addEventListener("click", () => bookingDialog.close());

addBookingButton.addEventListener("click", openManualBooking);
manualCancel.addEventListener("click", () => manualBookingDialog.close());
manualCheckIn.addEventListener("change", () => {
  if (manualCheckOut.value && manualCheckOut.value <= manualCheckIn.value) manualCheckOut.value = "";
  manualCheckOut.min = manualCheckIn.value;
  updateManualTotal();
});
manualCheckOut.addEventListener("change", updateManualTotal);
manualRate.addEventListener("change", updateManualTotal);
manualBookingForm.addEventListener("submit", saveManualBooking);
