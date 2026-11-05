document.addEventListener("DOMContentLoaded", () => {
  const contactLinks = document.querySelectorAll(
    '.page-contact a[href="#contact-details"]'
  );

  contactLinks.forEach((link) => {
    link.addEventListener("click", (event) => {
      const target = document.getElementById("contact-details");

      if (!target) return;

      event.preventDefault();

      target.scrollIntoView({
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
          ? "auto"
          : "smooth",
        block: "start"
      });

      history.replaceState(null, "", "#contact-details");
    });
  });

  const socialLinks = document.querySelectorAll(
    ".contact-social__link"
  );

  socialLinks.forEach((link) => {
    link.addEventListener("click", (event) => {
      const url = link.getAttribute("href");

      if (!url || url === "#") {
        event.preventDefault();
        console.info(
          "Replace this placeholder with the real contact URL:",
          link.getAttribute("aria-label")
        );
      }
    });
  });
});


document.addEventListener("DOMContentLoaded", () => {
  const form = document.getElementById("eventEnquiryForm");

  if (!form) return;

  const status = document.getElementById("eventFormStatus");
  const submitButton = document.getElementById("eventSubmit");
  const memberFields = document.querySelector(".event-member-fields");
  const externalFields = document.querySelector(".event-external-fields");
  const membershipInput = document.getElementById("event-membership");
  const organisationInput = document.getElementById("event-organisation");
  const preferredDate = document.getElementById("event-date");
  const alternativeDate = document.getElementById("event-alt-date");
  const startTime = document.getElementById("event-start");
  const finishTime = document.getElementById("event-end");

  const today = new Date();
  const localToday = [
    today.getFullYear(),
    String(today.getMonth() + 1).padStart(2, "0"),
    String(today.getDate()).padStart(2, "0")
  ].join("-");

  preferredDate.min = localToday;
  alternativeDate.min = localToday;

  preferredDate.addEventListener("change", () => {
    alternativeDate.min = preferredDate.value || localToday;

    if (
      alternativeDate.value &&
      alternativeDate.value < alternativeDate.min
    ) {
      alternativeDate.value = "";
    }
  });

  function updateEnquirerFields() {
    const selected = form.querySelector(
      'input[name="Enquirer type"]:checked'
    );

    const isMember = selected?.value === "Member";
    const isExternal = selected?.value === "External";

    memberFields.hidden = !isMember;
    externalFields.hidden = !isExternal;

    membershipInput.required = isMember;
    organisationInput.required = false;

    if (!isMember) membershipInput.value = "";
    if (!isExternal) organisationInput.value = "";
  }

  form.querySelectorAll('input[name="Enquirer type"]').forEach((input) => {
    input.addEventListener("change", updateEnquirerFields);
  });

  updateEnquirerFields();

  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    status.textContent = "";
    status.className = "event-form__status";

    if (finishTime.value <= startTime.value) {
      status.textContent =
        "Please choose a finish time later than the start time. For events ending after midnight, contact us directly.";
      status.classList.add("is-error");
      finishTime.focus();
      return;
    }

    const originalButtonText = submitButton.querySelector("span").textContent;

    submitButton.disabled = true;
    submitButton.querySelector("span").textContent = "Sending enquiry...";

    try {
      const field = (name) => (form.elements[name]?.value || "").trim();
      const needs = [...form.querySelectorAll('input[name="Requirements"]:checked')]
        .map((input) => input.value).join(", ");

      const lines = [
        `${field("Full name")} would like to host an event at Ɛdan.`,
        "",
        `Event: ${field("Working title") || "Untitled"} (${field("Event type")})`,
        `Format: ${field("Attendance format")}`,
        `Expected guests: ${field("Expected guests")}`,
        "",
        `Preferred date: ${field("Preferred date")}`,
        field("Alternative date") ? `Alternative date: ${field("Alternative date")}` : null,
        `Time: ${field("Start time")} to ${field("Finish time")}`,
        field("Setup time") ? `Setup time: ${field("Setup time")}` : null,
        "",
        "About the idea:",
        field("Event description"),
        needs ? `\nThey'll need: ${needs}` : null,
        field("Additional requirements") ? `\nNotes: ${field("Additional requirements")}` : null,
        "",
        "Contact:",
        `${field("Full name")} (${field("Enquirer type")})`,
        field("Organisation or collective") ? field("Organisation or collective") : null,
        field("Membership details") ? `Membership: ${field("Membership details")}` : null,
        `Email: ${field("Email")}`,
        field("Phone or WhatsApp") ? `Phone: ${field("Phone or WhatsApp")}` : null
      ].filter((line) => line !== null);

      const formData = new FormData();
      formData.append("name", field("Full name"));
      formData.append("email", field("Email"));
      formData.append("message", lines.join("\n"));
      ["_subject", "_template", "_captcha", "_honey"].forEach((key) => {
        formData.append(key, form.elements[key].value);
      });
            const action = form.action.replace(
              "https://formsubmit.co/",
              "https://formsubmit.co/ajax/"
            );

            const response = await fetch(action, {
              method: "POST",
              body: formData,
              headers: {
                Accept: "application/json"
              }
            });

            const result = await response.json();

            if (!response.ok || result.success === false || result.success === "false") {
        console.error("FormSubmit response:", result);
        throw new Error(result.message || "The enquiry could not be submitted.");
      }

      form.reset();
      updateEnquirerFields();

      preferredDate.min = localToday;
      alternativeDate.min = localToday;

      status.textContent =
        "Thank you for thinking of Ɛdan. Your event enquiry has been received, and our team will be in touch.";
      status.classList.add("is-success");
    } catch (error) {
      status.textContent =
        "We couldn't send your enquiry just now. Please try again or contact Ɛdan directly.";
      status.classList.add("is-error");
    } finally {
      submitButton.disabled = false;
      submitButton.querySelector("span").textContent = originalButtonText;
    }
  });
});
