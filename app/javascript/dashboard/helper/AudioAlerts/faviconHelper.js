// Renders a dynamic favicon with an unread-count badge (WhatsApp Web style)
// and mirrors the count in the browser tab title.
//
// The badge counts unread messages across conversations assigned to the
// current user and updates reactively as messages arrive or are read.

const FAVICON_SELECTOR = 'link.favicon';
const BADGE_COLOR = '#f7371f';
const BADGE_TEXT_COLOR = '#ffffff';
const RENDER_SIZE = 64;
const MAX_DISPLAY_COUNT = 99;

let baseTitle = null;
let baseIconPromise = null;
let watcherRegistered = false;

const getFaviconLinks = () => {
  let links = Array.from(document.querySelectorAll(FAVICON_SELECTOR));
  if (!links.length) {
    // Some installations (DISPLAY_MANIFEST disabled) ship no `.favicon`
    // links. Create one so the badge always has something to update.
    const link = document.createElement('link');
    link.className = 'favicon';
    link.rel = 'icon';
    link.type = 'image/png';
    const existing = document.querySelector('link[rel="icon"]');
    link.href = existing ? existing.href : '/favicon-32x32.png';
    document.head.appendChild(link);
    links = [link];
  }
  return links;
};

const captureOriginals = links => {
  links.forEach(link => {
    if (!link.dataset.originalHref) {
      link.dataset.originalHref = link.href;
    }
  });
  if (baseTitle === null) {
    baseTitle = document.title
      .replace(/^\(\d+\+?\)\s*/, '')
      .replace(/\s+/g, ' ')
      .trim();
  }
};

const loadBaseIcon = href =>
  new Promise(resolve => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = href;
  });

const renderBadgeDataUrl = (baseImg, label) => {
  const size = RENDER_SIZE;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;

  if (baseImg) {
    ctx.drawImage(baseImg, 0, 0, size, size);
  }

  const radius = size * 0.3;
  const cx = size - radius;
  const cy = radius;

  ctx.beginPath();
  ctx.arc(cx, cy, radius, 0, Math.PI * 2);
  ctx.fillStyle = BADGE_COLOR;
  ctx.fill();

  ctx.fillStyle = BADGE_TEXT_COLOR;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const fontSize = label.length > 2 ? size * 0.34 : size * 0.44;
  ctx.font = `bold ${fontSize}px Arial, sans-serif`;
  ctx.fillText(label, cx, cy + size * 0.02);

  return canvas.toDataURL('image/png');
};

const restoreFavicon = links => {
  links.forEach(link => {
    if (link.dataset.originalHref) {
      link.href = link.dataset.originalHref;
    }
  });
};

export const setUnreadBadge = async count => {
  const links = getFaviconLinks();
  captureOriginals(links);

  const safeCount = Number(count) || 0;

  if (safeCount <= 0) {
    document.title = baseTitle;
    restoreFavicon(links);
    return;
  }

  const label =
    safeCount > MAX_DISPLAY_COUNT ? `${MAX_DISPLAY_COUNT}+` : String(safeCount);
  document.title = `(${label}) ${baseTitle}`;

  const baseHref = links[0].dataset.originalHref;
  if (!baseIconPromise) {
    baseIconPromise = loadBaseIcon(baseHref);
  }
  const baseImg = await baseIconPromise;
  const dataUrl = renderBadgeDataUrl(baseImg, label);
  if (dataUrl) {
    links.forEach(link => {
      link.href = dataUrl;
    });
  }
};

const computeUnreadCount = store => {
  const mineChats = store.getters.getMineChats({
    assigneeType: 'me',
    status: 'open',
  });
  return mineChats.reduce(
    (total, chat) => total + (chat.unread_count || 0),
    0
  );
};

// Registers a reactive watcher that keeps the favicon badge and tab title in
// sync with the number of unread messages assigned to the current user.
export const initUnreadFaviconBadge = store => {
  if (watcherRegistered || !store) return;
  watcherRegistered = true;

  store.watch(() => computeUnreadCount(store), setUnreadBadge, {
    immediate: true,
  });
};
