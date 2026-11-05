import { fetchStayConfirmation, getSignedInUser, verifyStayPayment } from "./stay-api.js";
import { formatGhsPrecise, formatStayDate, formatGhs } from "./stay-format.js";

const BOOKING_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PAGE_PATH = "/stay/confirmation.html";
const STAY_PATH = "./";

const dateTimeFormat = new Intl.DateTimeFormat("en-GB", { dateStyle: "medium", timeStyle: "short" });

const messageBox = document.getElementById("confirmMessage");
const messageTitle = document.getElementById("confirmMessageTitle");
const messageText = document.getElementById("confirmMessageText");
const messageAction = document.getElementById("confirmMessageAction");
const receipt = document.getElementById("confirmReceipt");
const receiptTitle = document.getElementById("receiptTitle");
const receiptLede = document.getElementById("receiptLede");
const bookingList = document.getElementById("bookingDetails");
const paymentList = document.getElementById("paymentDetails");
const printButton = document.getElementById("printReceipt");

const bookingId = new URLSearchParams(window.location.search).get("stay_booking");

function showMessage(title, text, action) {
  receipt.hidden = true;
  messageBox.hidden = false;
  messageTitle.textContent = title;
  messageText.textContent = text;
  messageAction.hidden = !action;
  messageAction.textContent = action?.label ?? "";
  messageAction.onclick = action ? action.onClick : null;
}

function addRow(list, label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const detail = document.createElement("dd");
  detail.textContent = value;
  list.append(term, detail);
}

function nightsBetween(checkIn, checkOut) {
  return Math.round((Date.parse(`${checkOut}T00:00:00Z`) - Date.parse(`${checkIn}T00:00:00Z`)) / 86400000);
}

function renderReceipt(booking) {
  const nights = nightsBetween(booking.check_in, booking.check_out);
  const rateLabel = booking.breakfast_included ? "With breakfast" : "Room only";

  bookingList.replaceChildren();
  paymentList.replaceChildren();

  addRow(bookingList, "Booking reference", booking.booking_reference);
  addRow(bookingList, "Room", booking.room_name);
  addRow(bookingList, "Guest", booking.guest_name);
  addRow(bookingList, "Email", booking.guest_email);
  addRow(bookingList, "Check-in", `${formatStayDate(booking.check_in)}, from 3:00 PM`);
  addRow(bookingList, "Check-out", `${formatStayDate(booking.check_out)}, by 11:00 AM`);
  addRow(bookingList, "Length of stay", `${nights} ${nights === 1 ? "night" : "nights"}`);
  addRow(bookingList, "Guests", String(booking.guests));
  addRow(bookingList, "Rate", `${rateLabel} (${formatGhs(booking.nightly_rate_ghs)} / night)`);

  const paidAmount = typeof booking.paid_amount_pesewas === "number"
    ? formatGhsPrecise(booking.paid_amount_pesewas / 100)
    : "Not recorded";
  const paidAt = booking.paid_at ? dateTimeFormat.format(new Date(booking.paid_at)) : "Not recorded";

  addRow(paymentList, "Status", "Paid");
  addRow(paymentList, "Amount paid", paidAmount);
  addRow(paymentList, "Paid on", paidAt);
  addRow(paymentList, "Paystack reference", booking.paystack_reference ?? "Not recorded");
  addRow(paymentList, "Total for stay", formatGhs(booking.total_ghs));

  receiptTitle.textContent = booking.status === "completed" ? "Thank you for staying with us" : "Your stay is confirmed";
  receiptLede.textContent = `Thank you, ${booking.guest_name}. Keep this page or print it for your records.`;
  messageBox.hidden = true;
  receipt.hidden = false;
}

function showUnfinishedBooking(booking) {
  const retry = { label: "Check again", onClick: loadConfirmation };

  if (booking.status === "pending_payment") {
    showMessage(
      "Payment not confirmed yet",
      "We haven't received confirmation from Paystack yet. Wait a moment, then check again.",
      retry
    );
    return;
  }

  if (booking.status === "cancelled") {
    showMessage(
      "This booking was cancelled",
      "The room has been released. Contact Ɛdan if you have questions about this booking.",
      { label: "Back to Stay", onClick: () => window.location.assign(STAY_PATH) }
    );
    return;
  }

  showMessage(
    "This booking didn't go through",
    "The payment wasn't completed, so the room has been released. Choose your dates again to book.",
    { label: "Back to Stay", onClick: () => window.location.assign(STAY_PATH) }
  );
}

async function loadConfirmation() {
  showMessage("Checking your payment", "This only takes a moment.", null);

  let verifyError = null;
  try {
    await verifyStayPayment(bookingId);
  } catch (error) {
    verifyError = error;
  }

  try {
    const booking = await fetchStayConfirmation(bookingId);

    if (!booking) {
      showMessage(
        "We couldn't find this booking",
        "It may belong to a different account. Sign in with the account you booked with.",
        null
      );
      return;
    }

    if (booking.status === "confirmed" || booking.status === "completed") {
      renderReceipt(booking);
      return;
    }

    if (verifyError) {
      showMessage("We couldn't check your payment", verifyError.message, { label: "Try again", onClick: loadConfirmation });
      return;
    }

    showUnfinishedBooking(booking);
  } catch (error) {
    showMessage("We couldn't load your booking", error.message, { label: "Try again", onClick: loadConfirmation });
  }
}

async function start() {
  if (!bookingId || !BOOKING_ID_PATTERN.test(bookingId)) {
    showMessage(
      "We couldn't find that booking",
      "Check the link from your payment, or go back to Stay to make a new booking.",
      { label: "Back to Stay", onClick: () => window.location.assign(STAY_PATH) }
    );
    return;
  }

  const user = await getSignedInUser();
  if (!user) {
    const returnPath = `${PAGE_PATH}?stay_booking=${bookingId}`;
    showMessage(
      "Sign in to see your booking",
      "Sign in with the account you booked with to view your confirmation and receipt.",
      { label: "Sign in", onClick: () => window.location.assign(`/login/?next=${encodeURIComponent(returnPath)}`) }
    );
    return;
  }

  await loadConfirmation();
}

printButton.addEventListener("click", () => window.print());

start();
