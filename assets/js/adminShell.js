const toggle = document.getElementById('adminSidebarToggle');
const closeButton = document.getElementById('adminSidebarClose');
const backdrop = document.getElementById('adminSidebarBackdrop');
const accountToggle = document.getElementById('adminAccountMenuToggle');
const accountMenu = document.getElementById('adminAccountMenu');

function setSidebar(open) {
  document.body.classList.toggle('admin-sidebar-open', Boolean(open));
  toggle?.setAttribute('aria-expanded', open ? 'true' : 'false');
}

function setAccountMenu(open) {
  accountMenu?.classList.toggle('open', Boolean(open));
  accountToggle?.setAttribute('aria-expanded', open ? 'true' : 'false');
}

toggle?.addEventListener('click', () => {
  const next = !document.body.classList.contains('admin-sidebar-open');
  setSidebar(next);
  if (next) setAccountMenu(false);
});
closeButton?.addEventListener('click', () => setSidebar(false));
backdrop?.addEventListener('click', () => setSidebar(false));

document.querySelectorAll('.admin-sidebar-link').forEach((link) => {
  link.addEventListener('click', () => {
    if (window.matchMedia('(max-width: 900px)').matches) setSidebar(false);
  });
});

accountToggle?.addEventListener('click', (event) => {
  event.stopPropagation();
  const next = !accountMenu?.classList.contains('open');
  setAccountMenu(next);
  if (next) setSidebar(false);
});
accountMenu?.addEventListener('click', (event) => event.stopPropagation());
document.addEventListener('click', () => setAccountMenu(false));
window.addEventListener('resize', () => {
  if (!window.matchMedia('(max-width: 900px)').matches) setSidebar(false);
  setAccountMenu(false);
});
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    setSidebar(false);
    setAccountMenu(false);
  }
});
