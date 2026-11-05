import { fetchRoomAvailability, getSignedInUser } from "./stay-api.js";
import { createStayCheckout } from "./stay-checkout.js";

const DRAFT_KEY = "edanStayBookingDraft";
const LOGIN_RETURN_PATH = "/stay/?resume=1";

(() => {
  const modal = document.getElementById("stayBookingModal");
  const form = document.getElementById("stayBookingForm");

  if (!modal || !form) return;

  const checkIn = document.getElementById("stayCheckIn");
  const checkOut = document.getElementById("stayCheckOut");
  const guests = document.getElementById("stayGuests");
  const rateInputs = form.querySelectorAll('input[name="stayRate"]');
  const nightCount = document.getElementById("stayNightCount");
  const totalOutput = document.getElementById("stayTotal");
  const errorOutput = document.getElementById("stayBookingError");
  const resultsOutput = document.getElementById("stayResults");
  const submitButton = form.querySelector('[type="submit"]');
  const detailsStep = document.getElementById("stayDetailsStep");
  const statusStep = document.getElementById("stayStatusStep");

  const rates = {
    room: 650,
    breakfast: 700
  };

  const rateLabels = {
    room: "Room only",
    breakfast: "With breakfast"
  };

  const money = new Intl.NumberFormat("en-GH", {
    style: "currency",
    currency: "GHS",
    maximumFractionDigits: 0
  });

  let availabilityRequest = 0;

  const checkout = createStayCheckout({
    modal,
    form: document.getElementById("stayGuestForm"),
    nameInput: document.getElementById("stayGuestName"),
    emailInput: document.getElementById("stayGuestEmail"),
    phoneInput: document.getElementById("stayGuestPhone"),
    errorOutput: document.getElementById("stayGuestError"),
    roomOutput: document.getElementById("stayCheckoutRoom"),
    datesOutput: document.getElementById("stayCheckoutDates"),
    totalOutput: document.getElementById("stayCheckoutTotal"),
    payButton: document.getElementById("stayPayButton"),
    statusTitle: document.getElementById("stayStatusTitle"),
    statusText: document.getElementById("stayStatusText"),
    statusAction: document.getElementById("stayStatusAction"),
    showStep,
    formatMoney: (amount) => money.format(amount)
  });

  function localDateString(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function selectedRate() {
    return form.querySelector('input[name="stayRate"]:checked')?.value || "room";
  }

  function calculateNights() {
    if (!checkIn.value || !checkOut.value) return 0;

    const start = new Date(`${checkIn.value}T12:00:00`);
    const end = new Date(`${checkOut.value}T12:00:00`);

    return Math.round((end - start) / 86400000);
  }

  function updateSummary() {
    const nights = calculateNights();
    const price = rates[selectedRate()];

    if (nights < 1) {
      nightCount.textContent = "Choose valid dates";
      totalOutput.textContent = `${money.format(price)} / night`;
      return;
    }

    nightCount.textContent =
      `${nights} ${nights === 1 ? "night" : "nights"}`;

    totalOutput.textContent = money.format(nights * price);
  }

  function showError(message) {
    errorOutput.textContent = message;
    errorOutput.hidden = false;
  }

  function clearError() {
    errorOutput.textContent = "";
    errorOutput.hidden = true;
  }

  function showStep(name) {
    form.hidden = name !== "dates";
    resultsOutput.hidden = name !== "dates" || resultsOutput.childElementCount === 0;
    detailsStep.hidden = name !== "details";
    statusStep.hidden = name !== "status";
  }

  function clearResults() {
    availabilityRequest += 1;
    resultsOutput.replaceChildren();
    resultsOutput.hidden = true;
  }

  function setChecking(isChecking) {
    submitButton.disabled = isChecking;
    submitButton.textContent = isChecking ? "Checking availability…" : "Check availability";
  }

  function readSearch() {
    return {
      checkIn: checkIn.value,
      checkOut: checkOut.value,
      guests: Number(guests.value),
      rate: selectedRate(),
      nights: calculateNights()
    };
  }

  function buildSelection(room, search) {
    return {
      room,
      ...search,
      total: search.nights * rates[search.rate]
    };
  }

  function renderMessage(text) {
    const paragraph = document.createElement("p");
    paragraph.className = "stay-results__message";
    paragraph.textContent = text;
    resultsOutput.replaceChildren(paragraph);
    resultsOutput.hidden = false;
  }

  async function chooseRoom(room) {
    const search = readSearch();
    const user = await getSignedInUser();

    if (!user) {
      sessionStorage.setItem(DRAFT_KEY, JSON.stringify({ roomId: room.id, roomName: room.name, ...search }));
      window.location.assign(`/login/?next=${encodeURIComponent(LOGIN_RETURN_PATH)}`);
      return;
    }

    checkout.openDetails(buildSelection(room, search), user);
  }

  function renderRooms(rooms, search) {
    const total = search.nights * rates[search.rate];
    const nightsLabel = `${search.nights} ${search.nights === 1 ? "night" : "nights"}`;

    const title = document.createElement("h3");
    title.className = "stay-results__title";
    title.textContent = rooms.length === 1
      ? "1 room is free for your dates"
      : `${rooms.length} rooms are free for your dates`;

    const list = document.createElement("ul");
    list.className = "stay-results__list";

    rooms.forEach((room) => {
      const item = document.createElement("li");
      item.className = "stay-results__item";

      const copy = document.createElement("div");

      const name = document.createElement("strong");
      name.textContent = room.name;

      const detail = document.createElement("small");
      detail.textContent = `${rateLabels[search.rate]} · ${nightsLabel}`;

      const price = document.createElement("span");
      price.className = "stay-results__price";
      price.textContent = money.format(total);

      const selectButton = document.createElement("button");
      selectButton.type = "button";
      selectButton.className = "stay-button stay-button--dark stay-results__select";
      selectButton.textContent = "Select room";
      selectButton.addEventListener("click", () => chooseRoom(room));

      copy.append(name, detail);
      item.append(copy, price, selectButton);
      list.append(item);
    });

    resultsOutput.replaceChildren(title, list);
    resultsOutput.hidden = false;
  }

  async function loadAvailability(search) {
    const request = ++availabilityRequest;
    const rooms = await fetchRoomAvailability(search.checkIn, search.checkOut);
    if (request !== availabilityRequest) return null;
    return rooms;
  }

  function updateCheckoutMinimum() {
    if (!checkIn.value) return;

    const nextDay = new Date(`${checkIn.value}T12:00:00`);
    nextDay.setDate(nextDay.getDate() + 1);

    checkOut.min = localDateString(nextDay);

    if (checkOut.value && checkOut.value <= checkIn.value) {
      checkOut.value = "";
    }

    updateSummary();
  }

  function restoreDraft() {
    const raw = sessionStorage.getItem(DRAFT_KEY);
    sessionStorage.removeItem(DRAFT_KEY);
    if (!raw) return null;

    try {
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  async function resumeAfterLogin(draft) {
    checkIn.value = draft.checkIn;
    checkOut.value = draft.checkOut;
    guests.value = String(draft.guests);
    form.querySelector(`input[name="stayRate"][value="${draft.rate === "breakfast" ? "breakfast" : "room"}"]`).checked = true;
    updateCheckoutMinimum();
    updateSummary();

    modal.showModal();
    showStep("dates");
    setChecking(true);

    try {
      const search = readSearch();
      const rooms = await loadAvailability(search);
      if (!rooms) return;

      const room = rooms.find((candidate) => candidate.id === draft.roomId);
      if (room) {
        await chooseRoom(room);
        return;
      }

      renderRooms(rooms, search);
      showError("That room is no longer free. Choose another room below.");
    } catch (error) {
      showError(error.message);
    } finally {
      setChecking(false);
    }
  }

  const today = localDateString(new Date());
  checkIn.min = today;
  checkOut.min = today;

  document.querySelectorAll(".stay-book-trigger").forEach((button) => {
    button.addEventListener("click", () => {
      clearError();
      clearResults();
      showStep("dates");

      const todayValue = localDateString(new Date());
      checkIn.min = todayValue;

      if (!checkIn.value || checkIn.value < todayValue) {
        checkIn.value = "";
      }

      updateCheckoutMinimum();
      updateSummary();
      modal.showModal();
    });
  });

  document.querySelectorAll("[data-close-stay-modal]").forEach((button) => {
    button.addEventListener("click", () => modal.close());
  });

  document.getElementById("stayBackToDates").addEventListener("click", () => {
    clearError();
    showStep("dates");
  });

  checkIn.addEventListener("change", () => {
    clearResults();
    updateCheckoutMinimum();
  });
  checkOut.addEventListener("change", () => {
    clearResults();
    updateSummary();
  });
  guests.addEventListener("change", clearError);

  rateInputs.forEach((input) => {
    input.addEventListener("change", () => {
      clearResults();
      updateSummary();
    });
  });

  modal.addEventListener("click", (event) => {
    if (event.target === modal) modal.close();
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearError();

    const search = readSearch();

    if (!checkIn.value || !checkOut.value || search.nights < 1) {
      showError("Choose a valid check-in date and a check-out date at least one night later.");
      return;
    }

    if (checkIn.value < localDateString(new Date())) {
      showError("Your check-in date cannot be in the past.");
      return;
    }

    setChecking(true);

    try {
      const rooms = await loadAvailability(search);
      if (!rooms) return;

      if (rooms.length === 0) {
        renderMessage("Sorry, no rooms are free for these dates. Try different dates.");
      } else {
        renderRooms(rooms, search);
      }
    } catch (error) {
      clearResults();
      showError(error.message);
    } finally {
      setChecking(false);
    }
  });

  const draft = new URLSearchParams(window.location.search).get("resume") === "1" ? restoreDraft() : null;

  if (draft) {
    resumeAfterLogin(draft);
  }

  updateSummary();
})();
