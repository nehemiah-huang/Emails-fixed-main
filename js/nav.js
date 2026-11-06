// Ɛdan nav enhancements. Load after main.js.
// main.js already handles the open/close toggle and the scrolled state.
(() => {
  const links = document.getElementById('navLinks');
  const toggle = document.getElementById('navToggle');
  if (!links || !toggle) return;

  // ---- settings ----
  const SUPABASE_URL = "https://afkegyueanjmktgrsnpn.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_AY-KPS5F2lxajImeHv83kw_UmMczbGS";
  const LOGIN_HREF = '/login/';
  const MEMBER_HREF = '/members/';
  const ADMIN_HREF = '/dashboard/';

  // "/stay/", "/stay/index.html" and "/stay" all become "/stay"; the home page becomes "/"
  const normalize = p => p.replace(/index\.html$/, '').replace(/\/+$/, '') || '/';
  const here = normalize(location.pathname);

  // mark the link for the current page (ignores #anchor links like /#why)
  function markCurrent(a) {
    const url = new URL(a.getAttribute('href'), location.href);
    if (!url.hash && normalize(url.pathname) === here) {
      a.setAttribute('aria-current', 'page');
    }
  }
  links.querySelectorAll('a').forEach(markCurrent);

  // ---- read the Supabase session from localStorage ----
  // Only this project's session is read, so a login left over from another
  // Supabase project can never be sent to this one.
  const SESSION_KEY_NAME = 'sb-tqgjgnohqzmvkakqxhcm-auth-token';

  function getSession() {
    try {
      const s = JSON.parse(localStorage.getItem(SESSION_KEY_NAME));
      return s && s.access_token && s.refresh_token ? s : null;
    } catch {
      return null;
    }
  }

  // ---- account badge: bottom-left on every page ----
  // signed out: tapping it goes to the login page
  // signed in:  shows a green dot, tapping it goes to the member page
  // (hidden on the login page itself)
  let badge = null;

  function buildBadge() {
    if (here === normalize(LOGIN_HREF) || document.getElementById('accountBadge')) return;

    const style = document.createElement('style');
style.textContent = `
  .account-badge {
    position: fixed;
    left: clamp(1rem, 2.4vw, 1.75rem);
    bottom: calc(clamp(1rem, 2.4vw, 1.75rem) + env(safe-area-inset-bottom, 0px));
    z-index: 95;
    box-sizing: border-box;
    width: 48px;
    height: 48px;
    padding: 12px;
    border-radius: 50%;
    display: grid;
    place-items: center;
    background: rgba(31, 25, 19, .55);
    border: 1px solid rgba(246, 239, 224, .45);
    -webkit-backdrop-filter: blur(8px);
    backdrop-filter: blur(8px);
    box-shadow: 0 6px 18px rgba(20, 16, 12, .28);
    transition: transform .25s cubic-bezier(.16, .84, .44, 1), background .25s ease;
  }
  .account-badge:hover { transform: scale(1.07); background: rgba(31, 25, 19, .85); }
  .account-badge:focus-visible { outline: 2px solid #F6EFE0; outline-offset: 3px; }
  .account-badge.is-signed-in { background: #1f1913; }
  .account-badge__icon {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: contain;
    opacity: .85;
  }
  .account-badge.is-signed-in .account-badge__icon { opacity: 1; }
  .account-badge__dot {
    display: none;
    position: absolute;
    top: 1px;
    right: 1px;
    width: 13px;
    height: 13px;
    border-radius: 50%;
    background: #6BCB77;
    border: 2px solid #1f1913;
  }
  .account-badge.is-signed-in .account-badge__dot { display: block; }
  .account-badge__icon {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  opacity: .85;
  transform: translateY(-3px);   /* try -1px to -3px */
}
`;
    document.head.append(style);

    badge = document.createElement('a');
    badge.id = 'accountBadge';
    badge.className = 'account-badge';
    badge.href = '/login/';
    badge.setAttribute('aria-label', 'Your account');
    badge.innerHTML = `
    <img class="account-badge__icon" src="/images/Favicon.png" alt="" width="48" height="48" decoding="async">
    <span class="account-badge__dot" aria-hidden="true"></span>`;
    document.body.append(badge);
  }

  function updateBadge(signedIn) {
    if (!badge) return;
    const label = signedIn ? 'Signed in. Open your member page' : 'Sign in';
    badge.href = signedIn ? MEMBER_HREF : LOGIN_HREF;
    badge.setAttribute('aria-label', label);
    badge.title = label;
    badge.classList.toggle('is-signed-in', signedIn);
  }

  buildBadge();

  // ---- add / remove a nav link ----
  function setLink(name, href, label, show) {
    let a = links.querySelector(`[data-nav-${name}]`);

    if (show) {
      if (a) return;
      a = document.createElement('a');
      a.href = href;
      a.textContent = label;
      a.setAttribute(`data-nav-${name}`, '');
      a.addEventListener('click', () => {
        if (links.classList.contains('open')) toggle.click();
      });
      links.append(a);
      markCurrent(a);
    } else if (a) {
      a.remove();
    }
  }

  // ---- admin check (asks your is_edan_admin function) ----
  const cacheKey = id => `edan-admin:${id}`;

  async function checkAdmin(session) {
    const userId = session.user && session.user.id;
    if (!userId) return;

    // show instantly if we already confirmed this user as admin this session
    let cached = null;
    try { cached = sessionStorage.getItem(cacheKey(userId)); } catch {}
    if (cached === '1') setLink('admin', ADMIN_HREF, 'Dashboard', true);

    // expired token on a page without the Supabase client: skip the request
    // and keep whatever the nav already shows
    if (session.expires_at && session.expires_at * 1000 < Date.now()) return;

    if (SUPABASE_URL.startsWith('YOUR_') || SUPABASE_PUBLISHABLE_KEY.startsWith('YOUR_')) return;

    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/is_edan_admin`, {
        method: 'POST',
        headers: {
          apikey: SUPABASE_PUBLISHABLE_KEY,
          Authorization: `Bearer ${session.access_token}`,
          'Content-Type': 'application/json'
        },
        body: '{}'
      });

      // rejected token on a page without the Supabase client: keep whatever we had
      if (!res.ok) return;

      const isAdmin = (await res.json()) === true;
      try { sessionStorage.setItem(cacheKey(userId), isAdmin ? '1' : '0'); } catch {}
      setLink('admin', ADMIN_HREF, 'Dashboard', isAdmin);
    } catch {
      // network error: leave the nav as it is
    }
  }

  // ---- sync everything with the current session ----
  function sync() {
    const session = getSession();
    setLink('member', MEMBER_HREF, 'Member', !!session);
    updateBadge(!!session);

    if (session) {
      checkAdmin(session);
    } else {
      setLink('admin', ADMIN_HREF, 'Dashboard', false);
    }
  }
  sync();

  // signing in or out in another tab updates this one
  window.addEventListener('storage', e => {
    if (e.key === SESSION_KEY_NAME) sync();
  });

  // Escape closes the mobile menu and returns focus to the button
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && links.classList.contains('open')) {
      toggle.click();
      toggle.focus();
    }
  });
})();