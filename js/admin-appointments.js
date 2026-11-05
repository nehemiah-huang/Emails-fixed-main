import { supabase } from "./supabase-client.js";
import { createActionCell, createTableButton, createRow, formatDate, renderEmptyRow, setMessageText } from "./admin-table.js";
import { loadKpis } from "./admin-kpis.js";

const appointmentsBody = document.getElementById("appointmentsBody");
const slotsBody = document.getElementById("appointmentSlotsBody");
const appointmentsError = document.getElementById("appointmentsError");
const slotForm = document.getElementById("appointmentSlotForm");
const slotStart = document.getElementById("appointmentSlotStart");
const slotEnd = document.getElementById("appointmentSlotEnd");
const slotError = document.getElementById("appointmentSlotError");
const statusLabels = { requested: "Requested", confirmed: "Confirmed", declined: "Declined", cancelled: "Cancelled", completed: "Completed" };

function appointmentLabel(appointment) { return appointment.member_appointment_types?.title || "Appointment"; }
function appointmentTime(appointment) {
  const startsAt = appointment.requested_start_at || appointment.member_appointment_slots?.starts_at;
  return startsAt ? formatDate(startsAt) : "—";
}

function renderAppointmentRow(appointment) {
  const row = createRow([appointment.booking_reference, appointment.member_name, appointmentLabel(appointment), appointmentTime(appointment), statusLabels[appointment.status] || appointment.status], ["Reference", "Member", "Type", "Time", "Status"]);
  const buttons = [];
  if (appointment.status === "requested") {
    buttons.push(createTableButton("Confirm", "admin__button admin__button--small admin__button--solid", { appointmentAction: "confirmed", appointmentId: appointment.id }));
    buttons.push(createTableButton("Decline", "admin__button admin__button--small admin__button--danger", { appointmentAction: "declined", appointmentId: appointment.id }));
  }
  if (appointment.status === "confirmed") {
    buttons.push(createTableButton("Complete", "admin__button admin__button--small", { appointmentAction: "completed", appointmentId: appointment.id }));
    buttons.push(createTableButton("Cancel", "admin__button admin__button--small admin__button--danger", { appointmentAction: "cancelled", appointmentId: appointment.id }));
  }
  row.append(createActionCell(...buttons));
  return row;
}

function renderSlotRow(slot) {
  const row = createRow([`${formatDate(slot.starts_at)} – ${new Date(slot.ends_at).toLocaleTimeString("en-GB", { hour: "numeric", minute: "2-digit" })}`, slot.status === "available" ? "Available" : "Blocked", slot.notes || "—"], ["Available time", "Slot status", "Notes"]);
  const button = createTableButton(slot.status === "available" ? "Block" : "Make available", "admin__button admin__button--small", { slotId: slot.id, slotStatus: slot.status === "available" ? "blocked" : "available" });
  row.append(createActionCell(button));
  return row;
}

export async function loadAppointments() {
  const [appointmentsResult, slotsResult] = await Promise.all([
    supabase.from("member_appointments").select("id, booking_reference, member_name, member_email, whatsapp_number, member_note, requested_start_at, status, admin_note, created_at, member_appointment_types(title), member_appointment_slots(starts_at, ends_at)").order("created_at", { ascending: false }).limit(100),
    supabase.from("member_appointment_slots").select("id, starts_at, ends_at, status, notes").gte("starts_at", new Date().toISOString()).order("starts_at").limit(100)
  ]);
  if (appointmentsResult.error || slotsResult.error) {
    setMessageText(appointmentsError, "Appointments could not be loaded. Please refresh the dashboard.");
    renderEmptyRow(appointmentsBody, 6, "Appointments could not be loaded.");
    renderEmptyRow(slotsBody, 4, "Availability could not be loaded.");
    return;
  }
  setMessageText(appointmentsError, "");
  const appointments = appointmentsResult.data || [];
  const slots = slotsResult.data || [];
  appointments.length ? appointmentsBody.replaceChildren(...appointments.map(renderAppointmentRow)) : renderEmptyRow(appointmentsBody, 6, "No appointment requests yet.");
  slots.length ? slotsBody.replaceChildren(...slots.map(renderSlotRow)) : renderEmptyRow(slotsBody, 4, "No availability has been added yet.");
}

appointmentsBody?.addEventListener("click", async event => {
  const button = event.target.closest("button[data-appointment-action]");
  if (!button) return;
  button.disabled = true;
  const { error } = await supabase.rpc("admin_set_appointment_status", { p_appointment_id: button.dataset.appointmentId, p_status: button.dataset.appointmentAction, p_admin_note: "" });
  if (error) setMessageText(appointmentsError, "That appointment could not be updated.");
  await Promise.all([loadAppointments(), loadKpis()]);
});

slotsBody?.addEventListener("click", async event => {
  const button = event.target.closest("button[data-slot-id]");
  if (!button) return;
  button.disabled = true;
  const { error } = await supabase.rpc("admin_set_appointment_slot_status", { p_slot_id: button.dataset.slotId, p_status: button.dataset.slotStatus });
  if (error) setMessageText(appointmentsError, "That availability could not be updated.");
  await loadAppointments();
});

slotForm?.addEventListener("submit", async event => {
  event.preventDefault();
  setMessageText(slotError, "");
  const { error } = await supabase.rpc("admin_create_appointment_slot", { p_starts_at: new Date(slotStart.value).toISOString(), p_ends_at: new Date(slotEnd.value).toISOString(), p_notes: "" });
  if (error) { setMessageText(slotError, "The available time could not be added. Check that it is in the future and ends after it starts."); return; }
  slotForm.reset();
  await Promise.all([loadAppointments(), loadKpis()]);
});
