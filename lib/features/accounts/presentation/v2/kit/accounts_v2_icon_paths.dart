/// R39 Accounts Workspace V2 — the prototype's stroke icons, path for path.
///
/// Drawn at the prototype's stroke width (1.75 on a 24 grid) so cards, tabs and
/// buttons match it exactly. Generated from
/// `docs/yorks-v1/designs/accounts-workspace-v2-prototype.html`.
library;

/// SVG body (no outer tag) for each icon name the prototype uses.
const accountsV2IconPaths = <String, String>{
  'grid':
      '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  'doc':
      '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>',
  'chart': '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  'receipt':
      '<path d="M5 3h14v18l-3-2-2 2-2-2-2 2-2-2-3 2z"/><path d="M9 8h6M9 12h6"/>',
  'box':
      '<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="m3 8 9 5 9-5M12 13v8"/>',
  'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'check': '<path d="m5 12 5 5 9-10"/>',
  'alert': '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/>',
  'info': '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  'print':
      '<path d="M6 9V3h12v6M6 18H4v-6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v6h-2"/><path d="M6 14h12v7H6z"/>',
  'download': '<path d="M12 4v11m0 0-4-4m4 4 4-4M4 20h16"/>',
  'truck':
      '<path d="M3 6h11v10H3zM14 10h4l3 3v3h-7z"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
  'edit': '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
  'x': '<path d="M6 6l12 12M18 6 6 18"/>',
  'wallet':
      '<path d="M3 7a2 2 0 0 1 2-2h13v4"/><path d="M3 7v11a2 2 0 0 0 2 2h15V9H5a2 2 0 0 1-2-2z"/><path d="M16 14h.01"/>',
  'cheque':
      '<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 14h6M15 14h3M6 10h12"/>',
  'bldg':
      '<path d="M4 21V5l8-2v18M12 8l8 2v11M8 8h.01M8 12h.01M8 16h.01M16 13h.01M16 17h.01M2 21h20"/>',
  'trash': '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
  'users':
      '<circle cx="9" cy="8" r="3.5"/><path d="M2 20c.5-3.5 3.3-5.5 7-5.5s6.5 2 7 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.6c2 .7 3.5 2.6 4 5.4"/>',
  'chat': '<path d="M4 5h16v11H8l-4 4z"/>',
  'cog':
      '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
  'folder':
      '<path d="M3 6a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  'spark': '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
  'copy':
      '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
  'undo': '<path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>',
  'coins':
      '<ellipse cx="9" cy="7" rx="6" ry="3"/><path d="M3 7v5c0 1.7 2.7 3 6 3s6-1.3 6-3V7"/><path d="M9 15v2c0 1.7 2.7 3 6 3s6-1.3 6-3v-5c0-1.7-2.7-3-6-3"/>',
  'shield':
      '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/>',
  'hier':
      '<rect x="3" y="3" width="7" height="6" rx="1.5"/><rect x="14" y="9.5" width="7" height="5" rx="1.5"/><rect x="14" y="16.5" width="7" height="5" rx="1.5"/><path d="M6.5 9v10.5H14M6.5 12H14"/>',
  'clip':
      '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h6M9 18h4"/>',
  'archive':
      '<rect x="3" y="4" width="18" height="5" rx="1"/><path d="M5 9v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9M10 13h4"/>',
  'ret':
      '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3h6v1M15.5 13H9m0 0 2.5-2.5M9 13l2.5 2.5"/>',
  'usercog':
      '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.2-5.6 6.5-5.6 1.2 0 2.3.3 3.2.8"/><circle cx="17.5" cy="17.5" r="2.2"/><path d="M17.5 13.5v1.8M17.5 19.7v1.8M21.5 17.5h-1.8M15.3 17.5h-1.8"/>',
  'history':
      '<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1L3.5 8.4"/><path d="M3.5 3.5v4.9h4.9M12 7.5V12l3 2"/>',
  'pin':
      '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
  'panel':
      '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M9 4v16M13 10l2 2-2 2"/>',
  'arrowL': '<path d="M19 12H5m0 0 6-6m-6 6 6 6"/>',
  'arrowR': '<path d="M5 12h14m0 0-6-6m6 6-6 6"/>',
  'search': '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  'expand': '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
  'bell':
      '<path d="M6 16v-5a6 6 0 1 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  'cloud':
      '<path d="M7 18a5 5 0 0 1-.5-10A6 6 0 0 1 18 9a4.5 4.5 0 0 1-.5 9z"/><path d="m9.5 13 2 2 3.5-3.5"/>',
  'dots':
      '<circle cx="5" cy="12" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/><circle cx="19" cy="12" r="1.3" fill="currentColor"/>',
  'chevD': '<path d="m6 9 6 6 6-6"/>',
  'chevUD': '<path d="m8 9 4-4 4 4M8 15l4 4 4-4"/>',
  'caret': '<path d="M7 10h10l-5 5.5z" fill="currentColor" stroke="none"/>',
  'msgs': '<path d="M3 5h12v9H7l-4 3z"/><path d="M15 9h6v9l-3-2.5h-7V14"/>',
  'pen': '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13 7 4 4"/>',
  'sheet':
      '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M4 9h16M4 15h16M10 9v12"/>',
  'pdf':
      '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M8.5 17v-4.5h1.4a1.3 1.3 0 0 1 0 2.6H8.5M13 12.5V17h.9a2.25 2.25 0 0 0 0-4.5z"/>',
  'upload':
      '<path d="M7 18a5 5 0 0 1-.5-10A6 6 0 0 1 18 9a4.5 4.5 0 0 1-.5 9"/><path d="M12 12v8m0-8-3 3m3-3 3 3"/>',
  'list': '<path d="M4 6h16M4 12h10M4 18h7"/><path d="m15 17 2 2 4-4"/>',
  'company':
      '<path d="M3 21V8l6-4v17M9 21h12V10l-6-2.5V21M12.5 12.5h3M12.5 16.5h3M5.5 10h1M5.5 14h1M5.5 18h1M2 21h20"/>',
};
