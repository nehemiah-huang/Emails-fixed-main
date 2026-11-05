import { createBookingHold, initializeStayPayment } from "./stay-api.js";
import { formatStayDate } from "./stay-format.js";

export function createStayCheckout(elements) {
  const {
    modal,
    form,
    nameInput,
    emailInput,
    phoneInput,
    errorOutput,
    roomOutput,
    datesOutput,
    totalOutput,
    payButton,
    statusTitle,
    statusText,
    statusAction,
    showStep,
    formatMoney
  } = elements;

  let selection = null;

  function reopenModal() {
    if (modal && typeof modal.showModal === "function" && !modal.open) {
      modal.showModal();
    }
  }

  function setError(message) {
    errorOutput.textContent = message;
    errorOutput.hidden = false;
  }

  function clearError() {
    errorOutput.textContent = "";
    errorOutput.hidden = true;
  }

  function setPaying(isPaying) {
    payButton.disabled = isPaying;
    payButton.textContent = isPaying ? "Please wait…" : "Continue to payment";
  }

  function setStatus(title, text, action) {
    statusTitle.textContent = title;
    statusText.textContent = text;
    statusAction.hidden = !action;
    statusAction.textContent = action?.label ?? "";
    statusAction.onclick = action ? action.onClick : null;
  }

  function showConfirmation(bookingId) {
    setStatus("Payment received", "Opening your booking confirmation…", null);
    window.location.assign(`/stay/confirmation.html?stay_booking=${bookingId}`);
  }

  function openCheckoutWindow(accessCode, bookingId) {
    if (!window.PaystackPop) {
      reopenModal();
      setStatus(
        "Payment window unavailable",
        "The secure payment window could not load. Check your connection and try again.",
        { label: "Try again", onClick: () => startPayment(bookingId) }
      );
      return;
    }

    modal.close();

    const popup = new window.PaystackPop();
    popup.resumeTransaction(accessCode, {
      onSuccess: () => showConfirmation(bookingId),
      onCancel: () => {
        reopenModal();
        setStatus(
          "Payment not completed",
          "Your room is still held for a short time. Continue to pay to finish your booking.",
          { label: "Continue to payment", onClick: () => startPayment(bookingId) }
        );
      },
      onError: (error) => {
        reopenModal();
        setStatus(
          "Payment could not be completed",
          error?.message || "Please try again.",
          { label: "Try again", onClick: () => startPayment(bookingId) }
        );
      }
    });
  }

  async function startPayment(bookingId) {
    showStep("status");
    setStatus("Opening secure payment", "Please wait while we prepare your payment.", null);

    try {
      const { access_code: accessCode } = await initializeStayPayment(bookingId);
      if (typeof accessCode !== "string" || !accessCode) {
        throw new Error("Payment could not be started. Please try again.");
      }
      openCheckoutWindow(accessCode, bookingId);
    } catch (error) {
      setStatus(
        "Payment could not start",
        error.message,
        { label: "Try again", onClick: () => startPayment(bookingId) }
      );
    }
  }

  function openDetails(nextSelection, user) {
    selection = nextSelection;

    roomOutput.textContent = selection.room.name;
    datesOutput.textContent = `${formatStayDate(selection.checkIn)} to ${formatStayDate(selection.checkOut)}`;
    totalOutput.textContent = `${formatMoney(selection.total)} for ${selection.nights} ${selection.nights === 1 ? "night" : "nights"}`;

    nameInput.value = user?.user_metadata?.full_name ?? "";
    emailInput.value = user?.email ?? "";
    phoneInput.value = "";

    clearError();
    showStep("details");
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearError();

    if (!selection) return;

    const guestName = nameInput.value.trim();
    const guestEmail = emailInput.value.trim();
    const guestPhone = phoneInput.value.trim();

    if (!guestName || !guestEmail || !guestPhone) {
      setError("Please enter your name, email address and phone number.");
      return;
    }

    setPaying(true);

    try {
      const booking = await createBookingHold({
        roomId: selection.room.id,
        checkIn: selection.checkIn,
        checkOut: selection.checkOut,
        guests: selection.guests,
        breakfastIncluded: selection.rate === "breakfast",
        guestName,
        guestEmail,
        guestPhone
      });

      await startPayment(booking.id);
    } catch (error) {
      setError(error.message);
    } finally {
      setPaying(false);
    }
  });

  return { openDetails };
}
