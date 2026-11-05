/* Ɛdan Labs — interactive field relationship map */
(() => {
  const instrument = document.querySelector("[data-research-instrument]");
  if (!instrument) return;

  const fieldData = {
    sonic: {
      category: "FIELD 01 / LISTENING",
      question: "What can the everyday sound of a city tell us about belonging?",
      description: "Listen for the rhythms, noise, silence and memory held in urban soundscapes.",
      target: "#sonic"
    },
    ground: {
      category: "FIELD 02 / PLACE-MAKING",
      question: "Who gets to shape the ground beneath a city?",
      description: "Explore the ground as a site of knowledge, collaboration, public art and resistance.",
      target: "#ground-works"
    },
    ai: {
      category: "FIELD 03 / PUBLIC KNOWLEDGE",
      question: "How can technology amplify a community without extracting from it?",
      description: "Consider AI as a public tool for local narratives, collective memory and community-led problem solving.",
      target: "#ai-commons"
    },
    fabric: {
      category: "FIELD 04 / MATERIAL MEMORY",
      question: "What stories are carried by the things we make and pass on?",
      description: "Follow textiles and craft as material culture, social infrastructure, and records of care and migration.",
      target: "#fabric"
    }
  };

  const tabs = [...instrument.querySelectorAll("[data-field]")];
  const nodes = [...instrument.querySelectorAll("[data-map-node]")];
  const category = document.getElementById("readout-category");
  const question = document.getElementById("readout-question");
  const description = document.getElementById("readout-description");
  const link = document.getElementById("readout-link");

  function activateField(key, moveFocus = false) {
    const data = fieldData[key];
    if (!data) return;

    tabs.forEach((tab) => {
      const active = tab.dataset.field === key;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-pressed", String(active));
    });

    nodes.forEach((node) => {
      const active = node.dataset.mapNode === key;
      node.classList.toggle("is-active", active);
      node.setAttribute("aria-hidden", "true");
    });

    category.textContent = data.category;
    question.textContent = data.question;
    description.textContent = data.description;
    link.href = data.target;
    link.innerHTML = 'Enter this lab <span aria-hidden="true">↘</span>';

    if (moveFocus) {
      const selected = tabs.find((tab) => tab.dataset.field === key);
      if (selected) selected.focus();
    }
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => activateField(tab.dataset.field));
    tab.addEventListener("keydown", (event) => {
      let nextIndex = index;
      if (event.key === "ArrowDown" || event.key === "ArrowRight") nextIndex = (index + 1) % tabs.length;
      else if (event.key === "ArrowUp" || event.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === "Home") nextIndex = 0;
      else if (event.key === "End") nextIndex = tabs.length - 1;
      else return;
      event.preventDefault();
      activateField(tabs[nextIndex].dataset.field, true);
    });
  });

  nodes.forEach((node) => {
    node.setAttribute("aria-hidden", "true");
    node.addEventListener("click", () => activateField(node.dataset.mapNode));
  });

  // The SVG is an illustration, while the buttons below it are the accessible controls.
  activateField("sonic");
})();
