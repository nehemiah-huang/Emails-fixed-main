// Ɛdan, "Behind the scenes": entrance + interaction.
// Everything visual lives in css/pages/about.css; this file only flips classes
// and passes the pointer position. Safe to remove: the section is complete without it.
(() => {
  const root = document.querySelector('.bts');
  if (!root) return;

  const figure = root.querySelector('.bts__figure');
  const key = root.querySelector('.bts__key');
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // 1. number the pencil paths and the blocks so css can stagger them,
  //    and normalise path length so one dash = the whole line (for the draw-on effect)
  root.querySelectorAll('.bts__sketch path, .bts__guide').forEach((path, i) => {
    path.setAttribute('pathLength', '1');
    path.style.setProperty('--i', i);
  });
  root.querySelectorAll('.bts__blocks use').forEach((block, i) => {
    block.style.setProperty('--i', i);
  });

  // 2. play the entrance once, when the section is in view
  const enter = () => {
    root.classList.add('is-in');
    window.setTimeout(() => root.classList.add('is-done'), 4200);
  };
  if (reduce || !('IntersectionObserver' in window)) {
    root.classList.add('is-in', 'is-done');
  } else {
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        enter();
        io.disconnect();
      }
    }, { threshold: 0.2 });
    io.observe(root);
  }

  if (reduce) return;

  // 3. the key swings when hovered or tapped
  if (key) {
    key.addEventListener('pointerenter', () => {
      if (!root.classList.contains('is-done') || key.classList.contains('is-swing')) return;
      key.classList.add('is-swing');
      key.addEventListener('animationend', (e) => {
        if (e.animationName === 'bts-key-swing') key.classList.remove('is-swing');
      }, { once: true });
    });
  }

  // 4. depth: with a mouse, the layers drift slightly as the pointer moves
  const mouse = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  if (mouse && figure) {
    let frame = 0;
    let x = 0;
    let y = 0;
    root.addEventListener('pointermove', (e) => {
      const r = root.getBoundingClientRect();
      x = ((e.clientX - r.left) / r.width - 0.5) * 2;
      y = ((e.clientY - r.top) / r.height - 0.5) * 2;
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        figure.style.setProperty('--px', x.toFixed(3));
        figure.style.setProperty('--py', y.toFixed(3));
      });
    });
    root.addEventListener('pointerleave', () => {
      figure.style.setProperty('--px', 0);
      figure.style.setProperty('--py', 0);
    });
  }
})();
