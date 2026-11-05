import { supabase } from "./supabase-client.js";

const GENERIC_ERROR = "Something went wrong. Please try again.";

export async function fetchRoomAvailability(checkIn, checkOut) {
  const { data, error } = await supabase.rpc("stay_room_availability", {
    p_check_in: checkIn,
    p_check_out: checkOut
  });

  if (error) {
    throw new Error(error.message || "The availability check failed with no details.");
  }
  if (!Array.isArray(data)) {
    throw new Error("The availability check returned an unexpected response.");
  }

  return data
    .filter((row) => row.is_available && typeof row.available_room_id === "string")
    .map((row) => ({
      id: row.available_room_id,
      name: String(row.available_room_name || "Stay at Ɛdan")
    }));
}

export async function createBookingHold(details) {
  const { data, error } = await supabase.rpc("create_stay_hold", {
    p_room_id: details.roomId,
    p_check_in: details.checkIn,
    p_check_out: details.checkOut,
    p_guests: details.guests,
    p_breakfast_included: details.breakfastIncluded,
    p_guest_name: details.guestName,
    p_guest_email: details.guestEmail,
    p_guest_phone: details.guestPhone
  });

  if (error) {
    throw new Error(error.message || "That room is no longer available for these dates.");
  }
  if (!data || typeof data.id !== "string") {
    throw new Error(GENERIC_ERROR);
  }

  return data;
}

export async function callStayPayment(payload) {
  const { data, error } = await supabase.functions.invoke("stay-payment", { body: payload });

  if (error) {
    let message = GENERIC_ERROR;
    try {
      const body = await error.context.json();
      if (typeof body?.error === "string") message = body.error;
    } catch {
      // Keep the generic message when the response has no readable body.
    }
    throw new Error(message);
  }

  return data;
}

export async function fetchStayConfirmation(bookingId) {
  const { data, error } = await supabase.rpc("get_own_stay_confirmation", { p_booking_id: bookingId });

  if (error || !Array.isArray(data)) {
    throw new Error("We couldn't load your booking. Please try again.");
  }

  const booking = data[0] ?? null;
  if (booking && typeof booking.status !== "string") {
    throw new Error("We couldn't load your booking. Please try again.");
  }

  return booking;
}

export async function getSignedInUser() {
  const { data, error } = await supabase.auth.getSession();
  if (error) return null;
  return data.session?.user ?? null;
}

export function initializeStayPayment(bookingId) {
  return callStayPayment({
    action: "initialize",
    booking_id: bookingId,
    callback_url: `${window.location.origin}/stay/confirmation.html?stay_booking=${bookingId}`
  });
}

export function verifyStayPayment(bookingId) {
  return callStayPayment({ action: "verify", booking_id: bookingId });
}
