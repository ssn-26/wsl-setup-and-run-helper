// WSL Control Panel - web-style SAMPLE. Everything here runs on fake data so
// the look and feel can be tried without touching WSL.
'use strict';

const $ = (s, el = document) => el.querySelector(s);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const ICON = {
  desktop: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/></svg>',
  term: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3m5 0h5"/></svg>',
  stop: '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
  play: '<svg viewBox="0 0 24 24"><path d="M7 5v14l11-7z"/></svg>',
  plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
  trash: '<svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
  key: '<svg viewBox="0 0 24 24"><circle cx="8" cy="15" r="4"/><path d="m11 12 9-9m-4 4 3 3"/></svg>',
};

// ---------------------------------------------------------------- fake data
const distros = [
  { name: 'Ubuntu-24.04', pretty: 'Ubuntu 24.04 LTS', initial: 'U', color: '#e95420', state: 'running',
    size: 12.3, port: 3390, systemd: true, isDefault: true, accounts: ['shreyas'] },
  { name: 'kali-linux', pretty: 'Kali Linux', initial: 'K', color: '#367bf0', state: 'stopped',
    size: 8.1, port: 3390, systemd: false, accounts: [] },
  { name: 'archlinux', pretty: 'Arch Linux', initial: 'A', color: '#1793d1', state: 'stopped',
    size: 3.4, port: 3391, systemd: true, accounts: ['shreyas'] },
];
const online = [
  ['Ubuntu', 'Ubuntu', '#e95420'], ['Ubuntu-24.04', 'Ubuntu 24.04 LTS', '#e95420'],
  ['Debian', 'Debian GNU/Linux', '#d70a53'], ['kali-linux', 'Kali Linux', '#367bf0'],
  ['archlinux', 'Arch Linux', '#1793d1'], ['FedoraLinux-42', 'Fedora Linux 42', '#51a2da'],
  ['openSUSE-Tumbleweed', 'openSUSE Tumbleweed', '#73ba25'], ['AlmaLinux-9', 'AlmaLinux OS 9', '#ff4649'],
];
const backups = [
  ['Ubuntu-24.04_2026-10-18_2140.tar', 2.4], ['archlinux_2026-10-12_0915.vhdx', 3.1], ['kali-linux_2026-09-30_1802.tar', 4.7],
];
const find = name => distros.find(d => d.name === name);

// ---------------------------------------------------------------- views
function show(view, arg) {
  document.querySelectorAll('.view').forEach(v => v.hidden = v.id !== 'view-' + view);
  document.querySelectorAll('.nav-item').forEach(n =>
    n.classList.toggle('active', n.dataset.view === (view === 'distro' ? 'distros' : view)));
  if (view === 'distros') renderGrid();
  if (view === 'distro') renderDetail(arg, 'accounts');
  if (view === 'backups') renderBackups();
}

function avatar(d, cls = '') {
  return `<div class="avatar ${cls}" style="background:${d.color}">${esc(d.initial)}</div>`;
}
function statePill(d) {
  return d.state === 'running'
    ? '<span class="pill on"><span class="dot on"></span>Running</span>'
    : '<span class="pill"><span class="dot"></span>Stopped</span>';
}

function renderGrid() {
  $('#distro-grid').innerHTML = distros.map(d => `
    <div class="card" data-open="${esc(d.name)}">
      <div class="card-top">
        ${avatar(d)}
        <div>
          <div class="card-name">${esc(d.pretty)}</div>
          <div class="card-meta">${d.size.toFixed(1)} GB &middot; WSL 2</div>
        </div>
        ${d.isDefault ? '<span class="badge">Default</span>' : ''}
      </div>
      <div>${statePill(d)}</div>
      <div class="card-actions">
        <button class="btn primary small" data-act="desktop" data-d="${esc(d.name)}">${ICON.desktop} Desktop</button>
        <button class="btn small" data-act="terminal" data-d="${esc(d.name)}">${ICON.term} Terminal</button>
      </div>
    </div>`).join('');
  const running = distros.filter(d => d.state === 'running').length;
  $('#wsl-mem').textContent = `${running} of ${distros.length} distros on · ${running ? (running * 3.1).toFixed(1) : 0} GB RAM`;
}

function renderDetail(name, tab) {
  const d = find(name);
  const tabs = ['accounts', 'settings', 'danger'].map(t =>
    `<button class="tab ${t === tab ? 'active' : ''}" data-tab="${t}" data-d="${esc(d.name)}">${{ accounts: 'Accounts', settings: 'Settings', danger: 'Danger zone' }[t]}</button>`).join('');
  let body = '';
  if (tab === 'accounts') {
    body = `<div class="list">${d.accounts.map(u => `
      <div class="item"><div class="user-icon">${esc(u[0].toUpperCase())}</div>
        <div class="grow"><b>${esc(u)}</b><div class="muted small">Admin (sudo) &middot; password saved, encrypted</div></div>
        <button class="btn small" data-act="toast" data-msg="Password for ${esc(u)} changed">${ICON.key} Change password</button>
        <button class="btn small ghost" data-act="toast" data-msg="Removed saved login ${esc(u)}">Remove</button>
      </div>`).join('') || '<div class="item"><div class="grow muted">No user yet - only root, which cannot log in to a desktop.</div></div>'}
      </div>
      <div class="row end"><button class="btn primary" data-act="adduser" data-d="${esc(d.name)}">${ICON.plus} Add a user</button></div>`;
  } else if (tab === 'settings') {
    body = `<div class="panel">
      <div class="folder"><div><b>Remote Desktop port</b><div class="muted small">Each distro can have its own, so two desktops can be open at once.</div></div>
        <input class="input" style="width:110px" value="${d.port}"></div>
      <div class="folder"><div><b>systemd</b><div class="muted small">Starts services (Docker, SSH, databases) properly. Applies after a restart of the distro.</div></div>
        <label class="switch"><input type="checkbox" ${d.systemd ? 'checked' : ''}><span></span></label></div>
      <div class="folder"><div><b>Compact disk</b><div class="muted small">Gives unused space in ext4.vhdx back to Windows.</div></div>
        <button class="btn small" data-act="compact" data-d="${esc(d.name)}">Compact</button></div>
    </div>`;
  } else {
    body = `<div class="panel danger-zone">
      <div class="folder"><div><b>Delete this distro</b><div class="muted small">Erases ${esc(d.pretty)} and every file inside it. Back it up first if you might need it.</div></div>
        <button class="btn danger small" data-act="delete" data-d="${esc(d.name)}">${ICON.trash} Delete</button></div>
    </div>`;
  }
  const runBtn = d.state === 'running'
    ? `<button class="btn" data-act="stop" data-d="${esc(d.name)}">${ICON.stop} Stop</button>`
    : `<button class="btn" data-act="start" data-d="${esc(d.name)}">${ICON.play} Start</button>`;
  $('#distro-detail').innerHTML = `
    <div class="hero">${avatar(d, 'big')}
      <div><h1>${esc(d.pretty)}</h1><div class="row">${statePill(d)}<span class="muted small mono">${esc(d.name)}</span></div></div>
      <div class="hero-actions">${runBtn}
        <button class="btn" data-act="terminal" data-d="${esc(d.name)}">${ICON.term} Terminal</button>
        <button class="btn primary" data-act="desktop" data-d="${esc(d.name)}">${ICON.desktop} Open desktop</button></div>
    </div>
    <div class="stats">
      <div class="stat"><span class="muted small">Disk</span><b>${d.size.toFixed(1)} GB</b></div>
      <div class="stat"><span class="muted small">Desktop port</span><b>${d.port}</b></div>
      <div class="stat"><span class="muted small">Default login</span><b>${esc(d.accounts[0] || 'root')}</b></div>
      <div class="stat"><span class="muted small">WSL version</span><b>2</b></div>
    </div>
    <div class="tabs">${tabs}</div>${body}`;
}

function renderBackups() {
  $('#backup-list').innerHTML = backups.map(([f, gb]) => `
    <div class="item">
      <div class="user-icon">${f.endsWith('.vhdx') ? 'V' : 'T'}</div>
      <div class="grow"><b class="mono">${esc(f)}</b><div class="muted small">${gb} GB</div></div>
      <button class="btn small" data-act="restore" data-f="${esc(f)}">Restore</button>
    </div>`).join('');
}

// ---------------------------------------------------------------- dialogs
function dialog(html, wide) {
  const dlg = $('#dialog');
  dlg.className = 'dialog' + (wide ? ' wide' : '');
  dlg.innerHTML = html;
  $('#overlay').hidden = false;
  const first = dlg.querySelector('input'); if (first) setTimeout(() => first.focus(), 30);
  return dlg;
}
function closeDialog() { $('#overlay').hidden = true; }

function toast(msg, kind) {
  const t = document.createElement('div');
  t.className = 'toast' + (kind ? ' ' + kind : '');
  t.textContent = msg;
  $('#toasts').appendChild(t);
  setTimeout(() => t.remove(), 3800);
}

const NAME_OK = /^[a-z_][a-z0-9_-]{0,31}$/;
function createUserDialog(d, then) {
  const dlg = dialog(`
    <h2>Create your Linux user</h2>
    <p class="muted">${esc(d.pretty)} only has root, which cannot log in to a desktop. This makes your own
      user with admin (sudo) rights, sets up the desktop session and saves the login (encrypted) for auto-login.</p>
    <div class="field"><label>Username</label><input class="input" id="u" value="shreyas" autocomplete="off">
      <span class="hint" id="u-hint">Lowercase letters, digits, - and _</span></div>
    <div class="field"><label>Password</label><input class="input" id="p1" type="password"></div>
    <div class="field"><label>Confirm password</label><input class="input" id="p2" type="password">
      <span class="hint" id="p-hint">&nbsp;</span></div>
    <div class="dialog-actions"><button class="btn" data-act="close">Not now</button>
      <button class="btn primary" id="u-ok" disabled>Create user</button></div>`);
  const check = () => {
    const u = $('#u').value, p1 = $('#p1').value, p2 = $('#p2').value;
    const uOk = NAME_OK.test(u);
    $('#u-hint').className = 'hint' + (u && !uOk ? ' bad' : '');
    $('#u-hint').textContent = u && !uOk ? 'Use lowercase letters, digits, - and _, starting with a letter' : 'Lowercase letters, digits, - and _';
    const pOk = p1.length > 0 && p1 === p2;
    $('#p-hint').className = 'hint ' + (p2 ? (pOk ? 'good' : 'bad') : '');
    $('#p-hint').textContent = p2 ? (pOk ? 'Passwords match' : 'The passwords do not match') : ' ';
    $('#u-ok').disabled = !(uOk && pOk);
  };
  dlg.addEventListener('input', check);
  $('#u-ok').onclick = () => {
    const u = $('#u').value;
    runTask(`Creating ${u} in ${d.pretty}`, [
      `Creating Linux user '${u}'...`, 'Installing the sudo package...', `Configuring admin rights for '${u}'...`,
      'Setting up XFCE session and audio forwarding...', 'Setting the password...', `'${u}' is now the default login.`,
    ], () => { d.accounts.push(u); toast(`${u} is ready in ${d.pretty}`); then && then(); });
  };
}

function runTask(title, lines, done) {
  dialog(`
    <h2>${esc(title)}</h2>
    <div class="task-row"><span id="t-step">Starting...</span><span id="t-pct">0%</span></div>
    <div class="progress"><div id="t-bar"></div></div>
    <div class="log" id="t-log"></div>
    <div class="dialog-actions"><button class="btn" data-act="close" id="t-close" disabled>Working...</button></div>`, true);
  let i = 0;
  const tick = () => {
    if (i < lines.length) {
      $('#t-log').textContent += '==> ' + lines[i] + '\n';
      $('#t-log').scrollTop = 1e9;
      $('#t-step').textContent = lines[i];
      const pct = Math.round((i + 1) / lines.length * 100);
      $('#t-bar').style.width = pct + '%'; $('#t-pct').textContent = pct + '%';
      i++; setTimeout(tick, 650);
    } else {
      $('#t-step').textContent = 'Done';
      $('#t-close').disabled = false; $('#t-close').textContent = 'Close';
      setTimeout(() => { closeDialog(); done && done(); }, 700);
    }
  };
  tick();
}

function deleteDialog(d) {
  const dlg = dialog(`
    <h2>Delete ${esc(d.pretty)}?</h2>
    <div class="warn-box">This permanently erases the distro and ALL files inside it. It cannot be undone.</div>
    <div class="field"><label>Type <span class="mono">${esc(d.name)}</span> to confirm</label>
      <input class="input mono" id="del-name" autocomplete="off"></div>
    <div class="dialog-actions"><button class="btn" data-act="close">Cancel</button>
      <button class="btn danger" id="del-ok" disabled>${ICON.trash} Delete forever</button></div>`);
  dlg.addEventListener('input', () => { $('#del-ok').disabled = $('#del-name').value !== d.name; });
  $('#del-ok').onclick = () => {
    distros.splice(distros.indexOf(d), 1); closeDialog(); show('distros'); toast(`${d.pretty} was deleted`, 'warn');
  };
}

function downloadDialog() {
  let pick = null;
  const dlg = dialog(`
    <h2>Download a Linux distro</h2>
    <p class="muted">From Microsoft's official list. The download is resumable and checked before it is installed.</p>
    <div class="picker">${online.map(([n, p, c]) => `
      <button class="pick" data-pick="${esc(n)}"><div class="avatar" style="background:${c}">${esc(p[0])}</div>
        <div><b>${esc(p)}</b><div class="muted small mono">${esc(n)}</div></div></button>`).join('')}</div>
    <div class="dialog-actions"><button class="btn" data-act="close">Cancel</button>
      <button class="btn primary" id="dl-ok" disabled>Download</button></div>`, true);
  dlg.addEventListener('click', e => {
    const b = e.target.closest('[data-pick]'); if (!b) return;
    dlg.querySelectorAll('.pick').forEach(x => x.classList.toggle('active', x === b));
    pick = online.find(o => o[0] === b.dataset.pick); $('#dl-ok').disabled = false;
  });
  $('#dl-ok').onclick = () => {
    const [n, p, c] = pick;
    runTask(`Downloading ${p}`, ['Reading the official distro list...', `Downloading ${n} (412 MB)...`,
      'Connection dropped - resuming (attempt 1 of 60)...', 'Checking the SHA-256 fingerprint... verified',
      `Installing ${n} into data\\linux\\${n}...`], () => {
      const d = { name: n, pretty: p, initial: p[0], color: c, state: 'stopped', size: 1.2, port: 3390, systemd: false, accounts: [] };
      distros.push(d); renderGrid();
      createUserDialog(d, () => toast(`${p} is ready - press Desktop to open it`));
    });
  };
}

// ---------------------------------------------------------------- actions
function openDesktop(d) {
  if (!d.accounts.length) { createUserDialog(d, () => openDesktop(d)); return; }
  runTask(`Opening the ${d.pretty} desktop`, [
    `Waking ${d.name}...`, 'Detecting desktop type... ' + (d.name.includes('kali') ? 'Win-KeX' : 'xrdp'),
    `Starting the desktop server on port ${d.port}...`, 'Opening Windows Remote Desktop...',
  ], () => { d.state = 'running'; refresh(d); toast(`${d.pretty} desktop opened as ${d.accounts[0]}`); });
}
function refresh(d) {
  if (!$('#view-distro').hidden) renderDetail(d.name, $('.tab.active')?.dataset.tab || 'accounts'); else renderGrid();
}

document.addEventListener('click', e => {
  const nav = e.target.closest('[data-view]');
  if (nav) { show(nav.dataset.view); return; }
  const tab = e.target.closest('[data-tab]');
  if (tab) { renderDetail(tab.dataset.d, tab.dataset.tab); return; }
  const act = e.target.closest('[data-act]');
  if (act) {
    e.stopPropagation();
    const d = act.dataset.d && find(act.dataset.d);
    switch (act.dataset.act) {
      case 'close': closeDialog(); break;
      case 'desktop': openDesktop(d); break;
      case 'terminal': d.state = 'running'; refresh(d); toast(`Terminal opened for ${d.pretty}`); break;
      case 'stop': d.state = 'stopped'; refresh(d); toast(`${d.pretty} is stopped`); break;
      case 'start': d.state = 'running'; refresh(d); toast(`${d.pretty} is running`); break;
      case 'adduser': createUserDialog(d, () => refresh(d)); break;
      case 'delete': deleteDialog(d); break;
      case 'compact': runTask(`Compacting ${d.pretty}`, ['Shutting WSL down so the disk file is free...', 'Compacting with diskpart...', 'Reclaimed 1.8 GB'], () => toast('Reclaimed 1.8 GB')); break;
      case 'restore': runTask('Restoring a backup', ['Importing ' + act.dataset.f + '...', 'Setting the default login...'], () => toast('Backup restored')); break;
      case 'toast': toast(act.dataset.msg); break;
    }
    return;
  }
  const card = e.target.closest('[data-open]');
  if (card) show('distro', card.dataset.open);
});

$('#btn-download').onclick = downloadDialog;
$('#btn-backup').onclick = () => runTask('Backing up Ubuntu 24.04 LTS', ['Stopping Ubuntu-24.04...', 'Exporting to data\\backups\\Ubuntu-24.04_2026-10-20_1012.tar...', 'Backup saved (2.4 GB)'], () => toast('Backup saved (2.4 GB)'));
$('#btn-restore').onclick = () => toast('A file picker opens here in the real panel');
$('#btn-update').onclick = () => toast('An administrator prompt appears here in the real panel');
$('#btn-limits').onclick = () => toast('Limits saved - active after Shut down all');
$('#btn-shutdown').onclick = () => { distros.forEach(d => d.state = 'stopped'); refresh(distros[0]); toast('WSL is shut down and its memory is freed'); };
$('#overlay').addEventListener('click', e => { if (e.target.id === 'overlay') closeDialog(); });
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeDialog(); });

// Settings sliders and presets
const syncSliders = () => {
  $('#mem-val').textContent = $('#mem').value + ' GB';
  $('#cpu-val').textContent = $('#cpu').value;
  $('#swap-val').textContent = $('#swap').value + ' GB';
};
['mem', 'cpu', 'swap'].forEach(id => $('#' + id).addEventListener('input', () => {
  syncSliders(); document.querySelectorAll('.preset').forEach(p => p.classList.remove('active'));
}));
$('#presets').addEventListener('click', e => {
  const p = e.target.closest('.preset'); if (!p) return;
  const [m, c, s] = p.dataset.p.split(',');
  $('#mem').value = m; $('#cpu').value = c; $('#swap').value = s; syncSliders();
  document.querySelectorAll('.preset').forEach(x => x.classList.toggle('active', x === p));
});

// Theme (remembered per viewer; works without storage too)
function setTheme(t) {
  document.documentElement.dataset.theme = t;
  $('#theme-label').textContent = t === 'dark' ? 'Dark' : 'Light';
  try { localStorage.setItem('wslpanel-theme', t); } catch (_) { }
}
$('#theme-toggle').onclick = () => setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
let saved = null;
try { saved = localStorage.getItem('wslpanel-theme'); } catch (_) { }
setTheme(saved || (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'));

// ?shot=<screen>&theme=<t> opens one screen directly (used for screenshots)
const q = new URLSearchParams(location.search);
if (q.get('theme')) setTheme(q.get('theme'));
show('distros');
switch (q.get('shot')) {
  case 'detail': show('distro', 'Ubuntu-24.04'); break;
  case 'user': createUserDialog(find('kali-linux')); $('#p1').value = 'x'; $('#p2').value = 'x'; $('#dialog').dispatchEvent(new Event('input')); break;
  case 'task': show('distro', 'kali-linux'); runTask('Installing the Kali desktop', ['Updating package lists...', 'Installing kali-desktop-xfce (1.2 GB)...', 'Installing kali-win-kex...', 'Setting up XFCE...', 'Starting Win-KeX...', 'Done']); break;
  case 'delete': show('distro', 'archlinux'); renderDetail('archlinux', 'danger'); deleteDialog(find('archlinux')); break;
  case 'download': downloadDialog(); $('[data-pick="Debian"]').click(); break;
  case 'settings': show('settings'); break;
}
