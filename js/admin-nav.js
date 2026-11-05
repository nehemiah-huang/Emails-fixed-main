const links = [...document.querySelectorAll(".admin__tabbar-link")];

function setActiveSection(sectionId) {
  links.forEach(link => {
    const isActive = link.dataset.section === sectionId;
    link.classList.toggle("is-active", isActive);
    if (isActive) {
      link.setAttribute("aria-current", "true");
    } else {
      link.removeAttribute("aria-current");
    }
  });
}

const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) setActiveSection(entry.target.id);
  });
}, { rootMargin: "-40% 0px -55% 0px" });

links.forEach(link => {
  const section = document.getElementById(link.dataset.section);
  if (section) observer.observe(section);
});
