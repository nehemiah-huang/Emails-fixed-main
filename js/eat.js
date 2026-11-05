/* ============================================
   Ɛdan — Eat page interactions
   Front-end demo only it only displays the menu as instructed by Carina. 
   Replace sample menu data
   and prices with the confirmed café menu.
   ============================================ */
(() => {
  "use strict";

  const menuItems = [
  {
    "id": "jollof",
    "name": "Jollof rice",
    "category": "meals",
    "description": "A familiar favourite, served with your choice of accompaniment.",
    "price": 45,
    "image": "/images/jollof.webp",
    "featured": true,
    "eyebrow": "FROM THE KITCHEN"
  },
  {
    "id": "seasonal-bowl",
    "name": "Seasonal bowl",
    "category": "meals",
    "description": "A simple bowl built around seasonal ingredients.",
    "price": 40,
    "image": "/images/seasonal.jpg",
    "featured": true,
    "eyebrow": "SOMETHING FRESH"
  },
  {
    "id": "fried-rice",
    "name": "Fried rice",
    "category": "meals",
    "description": "A comforting rice dish with seasonal accompaniments.",
    "price": 45,
    "image": "/images/fried-rice.jpg",
    "featured": true,
    "eyebrow": "FROM THE KITCHEN"
  },
  {
    "id": "red-red",
    "name": "Red red & plantain",
    "category": "meals",
    "description": "Black-eyed beans served with ripe plantain.",
    "price": 40,
    "image": "/images/red-red.jpg",
    "featured": true,
    "eyebrow": "GHANAIAN FAVOURITE"
  },
  {
    "id": "sandwich",
    "name": "Kitchen sandwich",
    "category": "meals",
    "description": "A simple sandwich prepared fresh to order.",
    "price": 35,
    "image": "/images/sandwich.jpg",
    "featured": false
  },
  {
    "id": "Pasta",
    "name": "Pasta",
    "category": "meals",
    "description": "Italian style pasta",
    "price": 50,
    "image": "/images/noodles.jpg",
    "featured": false
  },
  {
    "id": "pastry",
    "name": "Pastry of the day",
    "category": "snacks",
    "description": "Ask us what has come out of the kitchen today.",
    "price": 18,
    "image": "/images/pastry.jpg",
    "featured": false
  },
  {
    "id": "cookies",
    "name": "House cookies",
    "category": "snacks",
    "description": "Something small to have with your drink.",
    "price": 12,
    "image": "/images/cookies.jpg",
    "featured": false
  },
  {
    "id": "plantain-chips",
    "name": "Plantain chips",
    "category": "snacks",
    "description": "A crisp little something to share.",
    "price": 15,
    "image": "/images/plantain-chips.jpg",
    "featured": false
  },
  {
    "id": "fresh-juice",
    "name": "Fresh juice",
    "category": "drinks",
    "description": "A chilled fruit juice, depending on the day.",
    "price": 20,
    "image": "/images/fresh-juice.jpg",
    "featured": false
  },
  {
    "id": "sobolo",
    "name": "Sobolo",
    "category": "drinks",
    "description": "A chilled hibiscus drink.",
    "price": 15,
    "image": "/images/sobolo.jpg",
    "featured": false
  },
  {
    "id": "coffee",
    "name": "Coffee",
    "category": "drinks",
    "description": "Made fresh when you order.",
    "price": 22,
    "image": "/images/coffee.jpg",
    "featured": false
  },
  {
    "id": "water",
    "name": "Bottled water",
    "category": "drinks",
    "description": "Still water, served chilled.",
    "price": 8,
    "image": "/images/water.jpg",
    "featured": false
  },
  {
    "id": "Soda",
    "name": "Carbonated Drinks",
    "category": "drinks",
    "description": "Coca-Cola, Sprite, Bel-Cola, Fanta",
    "price": 20,
    "image": "/images/soda.jpg",
    "featured": false,
  }
];
  const money = value => `GHS ${Number(value).toFixed(2)}`;
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  const categoryButtons = $$(".eat__category");
  const featured = $(".eat__featured");
  const menuList = $("#eat-menu-list");
  const categoryTitle = $("#eat-category-title");
  const menuHeadingNote = $(".eat__menu-heading p");
  const emptyMessage = $("#eat-empty");

  const basket = new Map();
  let activeCategory = "all";
  let activeSlide = 0;

  if (!featured || !menuList || !categoryButtons.length) return;

  const featuredProducts = menuItems.filter(item => item.featured);
  const categoryNames = {
    all: "The menu",
    meals: "Main dishes",
    snacks: "Snacks",
    drinks: "Drinks"
  };

  function addButton(item, compact = false) {
    return `<button class="eat__add${compact ? " eat__add--compact" : ""}" type="button"
      data-add="${item.id}" aria-label="Add ${item.name} to basket"><span aria-hidden="true"></span></button>`;
  }

  function renderCarousel() {
    featured.innerHTML = `
      <div class="eat__carousel-top">
        <div>
          <p class="eat__eyebrow">FROM THE ƐDAN KITCHEN</p>
          <h2 class="eat__carousel-title">Made for the table.</h2>
        </div>
        <div class="eat__carousel-controls">
          <span class="eat__carousel-count" aria-live="polite">01 / ${String(featuredProducts.length).padStart(2, "0")}</span>
          <button type="button" class="eat__carousel-arrow" data-slide="prev" aria-label="Previous dish">←</button>
          <button type="button" class="eat__carousel-arrow" data-slide="next" aria-label="Next dish">→</button>
        </div>
      </div>
      <div class="eat__carousel-viewport" tabindex="0" aria-label="Featured main dishes. Swipe or use the arrow buttons.">
        <div class="eat__carousel-track">
          ${featuredProducts.map((item, index) => `
            <article class="eat__slide${index === 0 ? " is-current" : ""}" data-slide-index="${index}">
              <div class="eat__slide-image-wrap">
                <img src="${item.image}" alt="${item.name}" ${index > 0 ? 'loading="lazy"' : 'fetchpriority="high"'} onerror="this.classList.add('image-missing')">
                <span class="eat__slide-number">${String(index + 1).padStart(2, "0")}</span>
              </div>
              <div class="eat__slide-copy">
                <div class="eat__slide-description">
                  <p class="eat__eyebrow">${item.eyebrow || "FROM THE KITCHEN"}</p>
                  <h3>${item.name}</h3>
                  <p>${item.description}</p>
                </div>
                <div class="eat__slide-action">
                  <span class="eat__price">${money(item.price)}</span>
                  ${addButton(item)}
                </div>
              </div>
            </article>`).join("")}
        </div>
      </div>
      <div class="eat__carousel-progress" aria-hidden="true"><span></span></div>
      <p class="eat__carousel-hint">Swipe to discover the menu</p>`;
    updateCarousel(0);
  }

  function updateCarousel(index) {
    const track = $(".eat__carousel-track");
    const slides = $$(".eat__slide", featured);
    if (!track || !slides.length) return;
    activeSlide = (index + slides.length) % slides.length;
    track.style.transform = `translateX(-${activeSlide * 100}%)`;
    slides.forEach((slide, i) => {
      slide.classList.toggle("is-current", i === activeSlide);
      slide.setAttribute("aria-hidden", i === activeSlide ? "false" : "true");
    });
    const count = $(".eat__carousel-count", featured);
    if (count) count.textContent = `${String(activeSlide + 1).padStart(2, "0")} / ${String(slides.length).padStart(2, "0")}`;
    const progress = $(".eat__carousel-progress span", featured);
    if (progress) progress.style.width = `${((activeSlide + 1) / slides.length) * 100}%`;
  }

  function renderMenu() {
    const filtered = menuItems
      .filter(item => !item.featured)
      .filter(item => activeCategory === "all" || item.category === activeCategory);

    menuList.innerHTML = filtered.map(item => `
      <article class="eat__menu-item" data-menu-item="${item.id}">
        <div class="eat__item-info">
          <h3>${item.name}</h3>
          <p>${item.description}</p>
        </div>
        <div class="eat__menu-item-action">
          <span class="eat__price">${money(item.price)}</span>
          ${addButton(item, true)}
        </div>
      </article>`).join("");

    const hasItems = filtered.length > 0;
    emptyMessage.hidden = hasItems;
    if (categoryTitle) categoryTitle.textContent = categoryNames[activeCategory] || "The menu";
    if (menuHeadingNote) {
      menuHeadingNote.textContent = activeCategory === "all"
        ? "Snacks and drinks for staying a little longer."
        : `A few good things from our ${activeCategory} menu.`;
    }
  }

  function setCategory(category) {
    activeCategory = category;
    categoryButtons.forEach(button => {
      const selected = button.dataset.category === category;
      button.classList.toggle("is-active", selected);
      button.setAttribute("aria-pressed", String(selected));
    });
    const showCarousel = category === "all" || category === "meals";
    featured.hidden = !showCarousel;
    renderMenu();
    if (showCarousel) updateCarousel(0);
  }

  function renderBasket() {
    const rows = $("#eat-basket-items");
    const countNode = $("#eat-basket-count");
    const totalNode = $("#eat-basket-total");
    const subtotalNode = $("#eat-subtotal");
    const checkoutTotal = $("#eat-checkout-total");
    const empty = $("#eat-basket-empty");
    const checkoutButton = $("#eat-checkout-open");

    let quantity = 0;
    let total = 0;

    if (rows) {
      rows.innerHTML = [...basket.entries()].map(([id, qty]) => {
        const item = menuItems.find(product => product.id === id);
        if (!item) return "";
        quantity += qty;
        total += item.price * qty;
        return `<div class="eat__basket-row">
          <div><h3>${item.name}</h3><p>${money(item.price)} each</p>
            <div class="eat__quantity">
              <button type="button" data-quantity="${id}" data-change="-1" aria-label="Remove one ${item.name}">−</button>
              <span>${qty}</span>
              <button type="button" data-quantity="${id}" data-change="1" aria-label="Add one ${item.name}">+</button>
            </div>
          </div>
          <strong>${money(item.price * qty)}</strong>
        </div>`;
      }).join("");
    }

    const distinctCount = [...basket.values()].reduce((sum, qty) => sum + qty, 0);
    total = [...basket.entries()].reduce((sum, [id, qty]) => {
      const item = menuItems.find(product => product.id === id);
      return sum + (item ? item.price * qty : 0);
    }, 0);

    if (countNode) countNode.textContent = `${distinctCount} ${distinctCount === 1 ? "item" : "items"}`;
    if (totalNode) totalNode.textContent = money(total);
    if (subtotalNode) subtotalNode.textContent = money(total);
    if (checkoutTotal) checkoutTotal.textContent = money(total);
    if (empty) empty.hidden = distinctCount > 0;
    if (checkoutButton) checkoutButton.disabled = distinctCount === 0;
  }

  function addToBasket(id, change = 1) {
    const item = menuItems.find(product => product.id === id);
    if (!item) return;
    const next = (basket.get(id) || 0) + change;
    if (next <= 0) basket.delete(id);
    else basket.set(id, next);
    renderBasket();
  }

  const basketPanel = $("#eat-basket");
  const overlay = $("#eat-overlay");
  const basketOpen = $("#eat-basket-open");
  const basketClose = $("#eat-basket-close");
  const checkoutOverlay = $("#eat-checkout-overlay");
  const checkoutOpen = $("#eat-checkout-open");
  const checkoutClose = $("#eat-checkout-close");
  const checkoutForm = $("#eat-checkout-form");
  const message = $("#eat-form-message");

  function openBasket() {
    if (!basketPanel || !overlay) return;
    basketPanel.classList.add("is-open");
    basketPanel.setAttribute("aria-hidden", "false");
    basketPanel.inert = false;
    overlay.hidden = false;
    basketOpen?.setAttribute("aria-expanded", "true");
    document.body.classList.add("eat-dialog-open");
    basketClose?.focus();
  }

  function closeBasket() {
    if (!basketPanel || !overlay) return;
    basketPanel.classList.remove("is-open");
    basketPanel.setAttribute("aria-hidden", "true");
    basketPanel.inert = true;
    overlay.hidden = true;
    basketOpen?.setAttribute("aria-expanded", "false");
    if (!checkoutOverlay || checkoutOverlay.hidden) document.body.classList.remove("eat-dialog-open");
    basketOpen?.focus();
  }

  function openCheckout() {
    if (!checkoutOverlay) return;
    closeBasket();
    checkoutOverlay.hidden = false;
    document.body.classList.add("eat-dialog-open");
    checkoutClose?.focus();
  }

  function closeCheckout() {
    if (!checkoutOverlay) return;
    checkoutOverlay.hidden = true;
    if (!basketPanel?.classList.contains("is-open")) document.body.classList.remove("eat-dialog-open");
    checkoutOpen?.focus();
  }

  document.addEventListener("click", event => {
    const categoryButton = event.target.closest(".eat__category");
    if (categoryButton) {
      setCategory(categoryButton.dataset.category);
      return;
    }

    const add = event.target.closest("[data-add]");
    if (add) {
      addToBasket(add.dataset.add);
      const original = add.innerHTML;
      add.innerHTML = "Added ✓";
      window.setTimeout(() => { if (add.isConnected) add.innerHTML = original; }, 900);
      return;
    }

    const slideButton = event.target.closest("[data-slide]");
    if (slideButton) {
      updateCarousel(activeSlide + (slideButton.dataset.slide === "next" ? 1 : -1));
      return;
    }

    const quantityButton = event.target.closest("[data-quantity]");
    if (quantityButton) {
      addToBasket(quantityButton.dataset.quantity, Number(quantityButton.dataset.change));
      return;
    }

    if (event.target.closest("#eat-basket-open")) openBasket();
    if (event.target.closest("#eat-basket-close") || event.target === overlay) closeBasket();
    if (event.target.closest("#eat-checkout-open")) openCheckout();
    if (event.target.closest("#eat-checkout-close")) closeCheckout();
    if (event.target === checkoutOverlay) closeCheckout();
  });

  // Pointer swipe support works with touch, pen and mouse dragging.
  let pointerStartX = null;
  let pointerStartY = null;
  featured.addEventListener("pointerdown", event => {
    if (!event.target.closest(".eat__carousel-viewport")) return;
    pointerStartX = event.clientX;
    pointerStartY = event.clientY;
  });
  featured.addEventListener("pointerup", event => {
    if (pointerStartX === null || !event.target.closest(".eat__carousel-viewport")) return;
    const dx = event.clientX - pointerStartX;
    const dy = event.clientY - pointerStartY;
    if (Math.abs(dx) > 45 && Math.abs(dx) > Math.abs(dy)) {
      updateCarousel(activeSlide + (dx < 0 ? 1 : -1));
    }
    pointerStartX = null;
    pointerStartY = null;
  });
  featured.addEventListener("pointercancel", () => {
    pointerStartX = null;
    pointerStartY = null;
  });
  featured.addEventListener("keydown", event => {
    if (!event.target.closest(".eat__carousel-viewport")) return;
    if (event.key === "ArrowRight") updateCarousel(activeSlide + 1);
    if (event.key === "ArrowLeft") updateCarousel(activeSlide - 1);
  });

  basketOpen?.addEventListener("keydown", event => {
    if (event.key === "Escape") closeBasket();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") {
      if (checkoutOverlay && !checkoutOverlay.hidden) closeCheckout();
      else if (basketPanel?.classList.contains("is-open")) closeBasket();
    }
  });

  $$('input[name="fulfilment"]').forEach(input => {
    input.addEventListener("change", () => {
      const tableField = $("#eat-table-field");
      if (tableField) tableField.hidden = input.value !== "dine_in" || !input.checked;
    });
  });

  checkoutForm?.addEventListener("submit", event => {
    event.preventDefault();
    if (!basket.size) {
      if (message) message.textContent = "Please add an item before placing an order.";
      return;
    }
    const formData = new FormData(checkoutForm);
    const orderDraft = {
      customerName: String(formData.get("customerName") || "").trim(),
      phone: String(formData.get("phone") || "").trim(),
      fulfilment: formData.get("fulfilment"),
      tableNumber: String(formData.get("tableNumber") || "").trim(),
      paymentMethod: formData.get("paymentMethod"),
      items: [...basket.entries()].map(([id, quantity]) => ({ id, quantity })),
      total: [...basket.entries()].reduce((sum, [id, quantity]) => {
        const item = menuItems.find(product => product.id === id);
        return sum + (item ? item.price * quantity : 0);
      }, 0)
    };

    console.info("Ɛdan order draft (not submitted):", orderDraft);
    if (message) {
      message.textContent = orderDraft.paymentMethod === "paystack"
        ? "Online payment is not connected yet. No payment has been taken."
        : "Order submission is not connected yet. This is a front-end demo.";
    }
  });

  renderCarousel();
  renderMenu();
  renderBasket();
  setCategory("all");
})();
