// ============================================
// Ɛdan — homepage prototype
// Section 1: nav + hero behaviour only.
// More gets added here as each new section is approved.
// ============================================

const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ---- nav: solid background after scrolling past hero ---- */
/* pages with no hero (labs/spaces/about) never get the transparent-over-photo moment,
   so the nav should just start in its solid "scrolled" look permanently on those pages */
const nav = document.getElementById('siteNav');
const navToggle = document.getElementById('navToggle');
const navLinks = document.getElementById('navLinks');
const hasHero = !!document.getElementById('heroMedia');

/* the bar hides while scrolling down and returns on any scroll up, and always shows at the top */
let lastY = 0;
function onScroll(){
  const y = Math.max(0, window.scrollY);   // iOS rubber-banding can report negative values

  // if(!hasHero || y > 60){
  //   nav.classList.add('scrolled');
  // } else {
  //   nav.classList.remove('scrolled');
  // }
  nav.classList.add('scrolled');

// AFTER
  /* the bar shows only at the very top of the page (or while the mobile menu is open) */
  if(nav.classList.contains('menu-open') || y <= 60){
    nav.classList.remove('nav-hidden');
  } else {
    nav.classList.add('nav-hidden');
  }
  lastY = y;
  lastY = y;
}
window.addEventListener('scroll', onScroll, { passive: true });
nav.addEventListener('focusin', () => nav.classList.remove('nav-hidden'));  // keyboard users can always reach it
onScroll();

/* ---- mobile nav toggle ---- */
navToggle.addEventListener('click', () => {
  const isOpen = navLinks.classList.toggle('open');
  navToggle.classList.toggle('open', isOpen);
  nav.classList.toggle('menu-open', isOpen);
  navToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
});

navLinks.querySelectorAll('a').forEach(link => {
  link.addEventListener('click', () => {
    navLinks.classList.remove('open');
    navToggle.classList.remove('open');
    nav.classList.remove('menu-open');
    navToggle.setAttribute('aria-expanded', 'false');
  });
});

/* ---- hero: gentle parallax on the background image ---- */
/* guarded: labs.html / spaces.html / about.html have no hero section at all */
const heroMedia = document.getElementById('heroMedia');

if(heroMedia && !reduceMotion){
  window.addEventListener('scroll', () => {
    const y = window.scrollY;
    // moves slower than scroll, capped so it never overshoots the -8% inset
    const offset = Math.min(y * 0.15, 90);
    heroMedia.style.transform = `translateY(${offset}px)`;
  }, { passive: true });
}

/* ---- scroll reveal: fades/slides in any .reveal element once visible ---- */
/* every new section added later just needs the "reveal" class — no extra JS required */
const revealTargets = document.querySelectorAll('.reveal');

if(reduceMotion || !('IntersectionObserver' in window)){
  revealTargets.forEach(el => el.classList.add('in'));
} else {
  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if(entry.isIntersecting){
        entry.target.classList.add('in');
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -60px 0px' });

  revealTargets.forEach(el => revealObserver.observe(el));
}

/* ---- generic parallax: any <img class="parallax-img"> drifts as its container crosses the viewport ---- */
/* new sections just need the class — no extra JS required per-image */
const parallaxImgs = document.querySelectorAll('.parallax-img');

if(parallaxImgs.length && !reduceMotion){
  function updateParallax(){
    const vh = window.innerHeight;
    parallaxImgs.forEach(img => {
      const rect = img.parentElement.getBoundingClientRect();
      const centerOffset = (rect.top + rect.height / 2) - vh / 2;
      const speed = 0.12;
      const max = rect.height * 0.11; // stays within the -12% / 124% CSS bleed, never reveals an edge
      let offset = centerOffset * speed * -1;
      offset = Math.max(-max, Math.min(max, offset));
      img.style.transform = `translateY(${offset}px)`;
    });
  }
  window.addEventListener('scroll', updateParallax, { passive: true });
  window.addEventListener('resize', updateParallax);
  updateParallax();
}
