// Ɛdan: loads shared HTML pieces (like the footer) into any page.
// Use:  <div data-include="partials/footer.html"></div>
// Needs Live Server (or any web server). It will not work if you double-click the .html file.
document.querySelectorAll('[data-include]').forEach(async (slot) => {
  try {
    const res = await fetch(slot.dataset.include);
    if (!res.ok) throw new Error(res.status + ' ' + res.statusText);
    slot.outerHTML = await res.text();   // replaces the placeholder with the real markup
  } catch (err) {
    console.error('include failed for', slot.dataset.include, err);
  }
});