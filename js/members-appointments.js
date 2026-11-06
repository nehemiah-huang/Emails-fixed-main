(() => {
  "use strict";

  const SUPABASE_URL = "https://afkegyueanjmktgrsnpn.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_AY-KPS5F2lxajImeHv83kw_UmMczbGS";

  // Card grid (browse view)
  const typeList   = document.getElementById("appointmentTypeList");
  // Booking form elements
  const form       = document.getElementById("appointmentForm");
  const radioList  = document.getElementById("appointmentTypeList2");
  const dateSelect = document.getElementById("appointmentDate");
  const calendar   = document.getElementById("appointmentCalendar");
  const slotList   = document.getElementById("appointmentSlotList");
  const slotInput  = document.getElementById("appointmentSlot");
  const nameInput  = document.getElementById("appointmentName");
  const emailInput = document.getElementById("appointmentEmail");
  const whatsInput = document.getElementById("appointmentWhatsapp");
  const noteInput  = document.getElementById("appointmentNote");
  const reviewEl   = document.getElementById("appointmentReview");
  const statusEl   = document.getElementById("appointmentStatus");
  const submitBtn  = document.getElementById("appointmentSubmit");
  // Navigation
  const backBtn    = document.getElementById("apptBack");
  const nextBtn    = document.getElementById("apptNext");
  // Steps
  const stepEls    = document.querySelectorAll(".members__appt-step");
  const fieldsets  = [
    document.getElementById("apptStepType"),
    document.getElementById("apptStepDate"),
    document.getElementById("apptStepTime"),
    document.getElementById("apptStepDetails"),
    document.getElementById("apptStepReview"),
  ];
  // Upcoming + confirmation
  const list           = document.getElementById("appointmentList");
  const confirmation   = document.getElementById("appointmentConfirmation");
  const confirmDetails = document.getElementById("appointmentConfirmationDetails");

  if (!form) return;

  let client, currentUser;
  let types  = [];
  let step   = 0; // 0–4

  const PHOTOS = [
    "/images/our story people.jpg",
    "/images/our story intro.jpg",
    "/images/sharing.webp",
    "/images/breeze-block-detail.webp",
  ];

  const dateFormat     = new Intl.DateTimeFormat(undefined, { weekday: "long", day: "numeric", month: "long" });
  const timeFormat     = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });
  const dateTimeFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

  function setStatus(text) { statusEl.textContent = text; }

  function formatDuration(minutes) {
    return Number.isFinite(minutes) && minutes > 0 ? `${minutes} minutes` : "Duration to be confirmed";
  }

  // ── Step navigation ──────────────────────────────────────────────────────

  function goToStep(n) {
    step = Math.max(0, Math.min(4, n));
    fieldsets.forEach((fs, i) => { if (fs) fs.hidden = i !== step; });
    stepEls.forEach((el, i) => {
      el.classList.toggle("is-active", i === step);
      el.classList.toggle("is-done",   i < step);
    });
    backBtn.hidden   = step === 0;
    nextBtn.hidden   = step === 4;
    submitBtn.hidden = step !== 4;
    if (step === 4) updateReview();
    statusEl.textContent = "";
  }

  function canAdvance() {
    if (step === 0) return !!radioList?.querySelector("input[type=radio]:checked");
    if (step === 1) return !!dateSelect?.value;
    if (step === 2) return !!slotInput?.value;
    if (step === 3) return !!(nameInput?.value.trim() && emailInput?.value.trim());
    return false;
  }

  nextBtn?.addEventListener("click", () => {
    if (!canAdvance()) {
      setStatus("Please complete this step before continuing.");
      return;
    }
    goToStep(step + 1);
  });

  backBtn?.addEventListener("click", () => goToStep(step - 1));

  // ── Type cards (browse section) ──────────────────────────────────────────

  function renderTypeCards() {
    if (!typeList) return;
    typeList.replaceChildren();
    types.forEach((type, idx) => {
      const card = document.createElement("article");
      card.className = "members__appt-type-card";

      const photoWrap = document.createElement("div");
      photoWrap.className = "members__appt-type-card-photo";
      const img = document.createElement("img");
      img.src = PHOTOS[idx % PHOTOS.length];
      img.alt = "";
      img.loading = "lazy";
      photoWrap.append(img);

      const body = document.createElement("div");
      body.className = "members__appt-type-card-body";

      const heading = document.createElement("h4");
      heading.textContent = type.title;

      const desc = document.createElement("p");
      desc.textContent = type.description;

      const dur = document.createElement("span");
      dur.className = "members__appt-duration";
      dur.textContent = formatDuration(type.duration_minutes).replace("Duration: ", "");

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "members__appt-book-btn";
      btn.textContent = "Book appointment →";
      btn.addEventListener("click", () => {
        // Pre-select in the form radio list and jump to booking section
        const radio = radioList?.querySelector(`input[value="${type.id}"]`);
        if (radio) { radio.checked = true; }
        goToStep(0);
        document.getElementById("bookAppointmentTitle")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });

      body.append(heading, desc, dur, btn);
      card.append(photoWrap, body);
      typeList.append(card);
    });
  }

  // ── Radio list (step 1 in booking form) ─────────────────────────────────

  function renderRadioList() {
    if (!radioList) return;
    radioList.replaceChildren();
    types.forEach(type => {
      const label = document.createElement("label");
      label.className = "members__appt-radio-item";
      const input = document.createElement("input");
      input.type  = "radio";
      input.name  = "appointmentType";
      input.value = type.id;
      const span = document.createElement("span");
      span.textContent = type.title;
      label.append(input, span);
      radioList.append(label);
    });
  }

  // ── Dates & slots ────────────────────────────────────────────────────────

  let calendarMonth;

  function renderDates() {
    if (!dateSelect || !calendar) return;

    const firstDate = new Date();
    firstDate.setHours(12, 0, 0, 0);
    const lastDate = new Date(firstDate);
    lastDate.setDate(lastDate.getDate() + 179);
    const firstMonth = new Date(firstDate.getFullYear(), firstDate.getMonth(), 1);
    const lastMonth = new Date(lastDate.getFullYear(), lastDate.getMonth(), 1);
    if (!calendarMonth || calendarMonth < firstMonth || calendarMonth > lastMonth) calendarMonth = firstMonth;

    const availableDates = new Set();
    const month = calendarMonth.getMonth();
    const year = calendarMonth.getFullYear();
    const monthLabel = new Intl.DateTimeFormat(undefined, { month: "long", year: "numeric" }).format(calendarMonth);
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const firstWeekday = new Date(year, month, 1).getDay();
    const heading = document.createElement("div");
    heading.className = "members__appt-calendar-heading";
    const previous = document.createElement("button");
    previous.type = "button";
    previous.className = "members__appt-calendar-nav";
    previous.textContent = "Previous";
    previous.disabled = calendarMonth <= firstMonth;
    previous.addEventListener("click", () => {
      calendarMonth = new Date(year, month - 1, 1);
      renderDates();
    });
    const label = document.createElement("strong");
    label.textContent = monthLabel;
    const next = document.createElement("button");
    next.type = "button";
    next.className = "members__appt-calendar-nav";
    next.textContent = "Next";
    next.disabled = calendarMonth >= lastMonth;
    next.addEventListener("click", () => {
      calendarMonth = new Date(year, month + 1, 1);
      renderDates();
    });
    heading.append(previous, label, next);

    const weekdays = document.createElement("div");
    weekdays.className = "members__appt-calendar-weekdays";
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].forEach(day => {
      const weekday = document.createElement("span");
      weekday.textContent = day;
      weekdays.append(weekday);
    });

    const grid = document.createElement("div");
    grid.className = "members__appt-calendar-grid";
    for (let index = 0; index < firstWeekday; index += 1) grid.append(document.createElement("span"));

    dateSelect.replaceChildren(new Option("Choose a date", ""));
    for (let day = 1; day <= daysInMonth; day += 1) {
      const date = new Date(year, month, day, 12);
      const value = date.toISOString().slice(0, 10);
      const button = document.createElement("button");
      button.type = "button";
      button.className = "members__appt-calendar-day";
      button.textContent = String(day);
      button.disabled = date < firstDate || date > lastDate;
      button.setAttribute("aria-label", `${dateFormat.format(date)}${button.disabled ? ", unavailable" : ", available"}`);
      button.addEventListener("click", () => {
        dateSelect.value = value;
        calendar.querySelectorAll(".members__appt-calendar-day").forEach(dayButton => dayButton.classList.remove("is-selected"));
        button.classList.add("is-selected");
        renderTimeSlots();
      });
      grid.append(button);
      if (!button.disabled) dateSelect.append(new Option(dateFormat.format(date), value));
    }

    calendar.replaceChildren(heading, weekdays, grid);
  }

  function renderTimeSlots() {
    if (!slotList || !slotInput) return;
    const date = dateSelect?.value || "";
    slotList.replaceChildren();
    slotInput.value = "";
    if (!date) return;
    for (let hour = 9; hour <= 17; hour += 1) {
      [0, 30].forEach(minute => {
        if (hour === 17 && minute === 30) return;
        const time = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "members__appt-slot-btn";
        btn.textContent = time;
        btn.addEventListener("click", () => {
          slotList.querySelectorAll(".members__appt-slot-btn").forEach(b => b.classList.remove("is-selected"));
          btn.classList.add("is-selected");
          slotInput.value = `${date}T${time}`;
        });
        slotList.append(btn);
      });
    }
  }

  dateSelect?.addEventListener("change", renderTimeSlots);

  // ── Review ───────────────────────────────────────────────────────────────

  function selectedType() {
    const checked = radioList?.querySelector("input[type=radio]:checked");
    return checked ? types.find(t => t.id === checked.value) : null;
  }

  function selectedRequestedStart() {
    return slotInput?.value ? new Date(slotInput.value).toISOString() : null;
  }

  function updateReview() {
    const type = selectedType();
    const requestedStart = selectedRequestedStart();
    const name = nameInput?.value.trim() || "—";
    const email = emailInput?.value.trim() || "—";
    submitBtn.disabled = !(type && requestedStart && nameInput?.value.trim() && emailInput?.value.trim());
    if (reviewEl) {
      reviewEl.textContent = (type && requestedStart)
        ? [
            `Appointment: ${type.title}`,
            `When: ${dateTimeFormat.format(new Date(requestedStart))}`,
            `Duration: ${formatDuration(type.duration_minutes)}`,
            `Name: ${name}`,
            `Email: ${email}`,
          ].join("\n")
        : "Choose an appointment type, date and time to review your request.";
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  form.addEventListener("submit", async event => {
    event.preventDefault();
    const type = selectedType();
    const requestedStart = selectedRequestedStart();
    if (!type || !requestedStart) return;

    submitBtn.disabled = true;
    setStatus("Saving your request…");

    const { data, error } = await client.rpc("create_member_appointment", {
      p_appointment_type_id: type.id,
      p_requested_start_at:  requestedStart,
      p_member_name:         nameInput.value.trim(),
      p_member_email:        emailInput.value.trim(),
      p_whatsapp_number:     whatsInput?.value.trim() || "",
      p_member_note:         noteInput?.value.trim()  || "",
    });

    if (error || !data?.[0]) {
      setStatus("We could not save that request. Please choose another date and time.");
      submitBtn.disabled = false;
      await loadSlots();
      return;
    }

    const booking = data[0];
    if (confirmDetails) {
      confirmDetails.replaceChildren();
      [
        ["Appointment", booking.appointment_title],
        ["When",        dateTimeFormat.format(new Date(booking.starts_at))],
        ["Reference",   booking.booking_reference],
      ].forEach(([label, value]) => {
        const dt = document.createElement("dt"); dt.textContent = label;
        const dd = document.createElement("dd"); dd.textContent = value;
        confirmDetails.append(dt, dd);
      });
    }

    if (confirmation) {
      confirmation.hidden = false;
      confirmation.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    form.reset();
    setStatus("");
    goToStep(0);
    const session = (await client.auth.getSession()).data.session;
    if (session) {
      try {
        const notificationResponse = await fetch(`${SUPABASE_URL}/functions/v1/admin-notifications`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ type: "appointment", appointment_id: booking.id }),
        });
        if (!notificationResponse.ok) {
          setStatus("Your request was saved, but the confirmation email could not be sent.");
        }
      } catch {
        setStatus("Your request was saved, but the confirmation email could not be sent.");
      }
    }
    await loadBookings();
  });

  // ── Bookings list ────────────────────────────────────────────────────────

  function renderBookings(bookings) {
    if (!list) return;
    list.replaceChildren();
    if (!bookings.length) {
      list.innerHTML = `<div class="members__appt-empty">
        <span class="members__appt-empty-icon" aria-hidden="true">□</span>
        <strong>You have no upcoming appointments.</strong>
        <p>Book an appointment to get started.</p>
        <a class="members__appt-btn--sm" href="#bookAppointmentTitle">Book an appointment →</a>
      </div>`;
      return;
    }
    bookings.forEach(b => {
      const item = document.createElement("article");
      item.className = "members__appointment-booking-card";
      const title = document.createElement("h4");
      title.textContent = b.member_appointment_types?.title || "Appointment";
      const time = document.createElement("p");
      const startsAt = b.member_appointment_slots?.starts_at || b.requested_start_at;
      time.textContent = startsAt ? dateTimeFormat.format(new Date(startsAt)) : "Time pending";
      const meta = document.createElement("span");
      meta.textContent = `${b.status} · ${b.booking_reference}`;
      item.append(title, time, meta);
      list.append(item);
    });
  }

  async function loadBookings() {
    if (!list) return;
    const { data, error } = await client
      .from("member_appointments")
      .select("id, booking_reference, status, requested_start_at, member_appointment_types(title), member_appointment_slots(starts_at, ends_at)")
      .in("status", ["requested", "confirmed"])
      .order("created_at", { ascending: false });
    if (error) { list.textContent = "Your appointments could not be loaded right now."; return; }
    renderBookings(data || []);
  }

  async function loadSlots() {
    renderDates();
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  async function init() {
    if (!window.supabase) return;
    client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
    const { data } = await client.auth.getSession();
    if (!data.session) return;
    currentUser = data.session.user;
    if (nameInput)  nameInput.value  = currentUser.user_metadata?.full_name || "";
    if (emailInput) emailInput.value = currentUser.email || "";

    const { data: typeData, error: typeError } = await client
      .from("member_appointment_types")
      .select("id, title, description, duration_minutes")
      .order("sort_order");

    if (typeError) {
      if (typeList) typeList.textContent = "Appointment options could not be loaded.";
      return;
    }

    types = typeData || [];
    renderTypeCards();
    renderRadioList();
    goToStep(0);
    await Promise.all([loadSlots(), loadBookings()]);
  }

  init().catch(err => {
    console.error("Appointment page error:", err);
    setStatus("Appointments are temporarily unavailable.");
  });
})();
