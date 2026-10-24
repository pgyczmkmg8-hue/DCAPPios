// 이 파일은 디시 페이지에 주입되는 자바스크립트입니다.
// 차단(유저/디시콘/키워드), 요소 숨기기, 실베 알림·사이트 머리글 숨기기, 로그인 자동 입력, 자짤 첨부, 임시저장, 댓글창 고정, 캡처 준비를 담당해요.
// 버전 표시: 페이지 구조 진단 첫 줄의 "script:" 값으로 최신 파일인지 확인할 수 있어요.

enum ContentScript {
    static let source = #"""
// DCApp content script — 디시 모바일 페이지에 주입되어 차단/숨김/로그인 자동입력/캡처 준비를 담당
(function () {
  'use strict';
  if (window.__dcapp) {
    if (window.__DCAPP_CONFIG__) window.__dcapp.setConfig(window.__DCAPP_CONFIG__);
    return;
  }

  var cfg = window.__DCAPP_CONFIG__ || {};
  var IP_RE = /\((\d{1,3}\.\d{1,3})\)/;
  var NOTICE_CLASS_RE = /(^|[-_\s])(toast|noti|notice|alarm|alert|push|popup|pop|layer|banner|float)([-_\s]|$)/i;

  function post(type, data) {
    try {
      window.webkit.messageHandlers.dcapp.postMessage(Object.assign({ type: type }, data || {}));
    } catch (e) {}
  }
  function txt(el) { return el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
  function clsOf(el) { return (el && el.getAttribute && el.getAttribute('class')) || ''; }

  // ---------- 스타일 ----------
  var STYLE_ID = 'dcapp-style';
  function validSel(s) { try { document.querySelector(s); return true; } catch (e) { return false; } }
  function buildCSS() {
    var rules = [
      '.dcapp-hide{display:none!important}',
      '.dcapp-collapsed{position:relative!important;height:30px!important;min-height:0!important;max-height:30px!important;overflow:hidden!important;padding-top:0!important;padding-bottom:0!important}',
      '.dcapp-collapsed>*{visibility:hidden!important}',
      '.dcapp-collapsed::after{content:attr(data-dcapp-label);visibility:visible;position:absolute;left:0;right:0;top:0;bottom:0;line-height:30px;padding:0 12px;font-size:12px;color:#8e8e93;background:rgba(142,142,147,.12);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
      '.dcapp-dccon-off{display:none!important}',
      '.dcapp-home-off{display:none!important}',
      'html.dcapp-home-wait body{opacity:0!important}',
      '.dcapp-blockmode [data-dcapp-unit]{outline:1px dashed rgba(255,59,48,.6)!important;outline-offset:-1px!important}',
      '.dcapp-pick{outline:3px solid #ff3b30!important;outline-offset:-3px!important;background-color:rgba(255,59,48,.15)!important}',
      '[data-dcapp-unit],img[src*="dccon"],img[data-original*="dccon"]{-webkit-touch-callout:none}',
      '.dcapp-dory{display:none!important}',
      '.dcapp-dock-head{display:flex!important;align-items:center!important;justify-content:space-between!important;height:44px!important;padding:0 6px 0 16px!important;border-bottom:1px solid rgba(127,127,127,.18)!important;font-size:15px!important;color:#888!important}',
      '.dcapp-dock-close{width:44px!important;height:44px!important;font-size:22px!important;line-height:44px!important;color:#888!important;background:none!important;border:0!important;padding:0!important}',
      '.dcapp-docked{position:fixed!important;left:0!important;right:0!important;bottom:auto!important;width:auto!important;max-width:none!important;margin:0!important;z-index:2147483000!important;max-height:60vh!important;overflow-y:auto!important;box-shadow:0 -4px 14px rgba(0,0,0,.14)!important;box-sizing:border-box!important;transform:none!important}'
    ];
    (cfg.selectors || []).forEach(function (s) {
      if (s && validSel(s)) rules.push(s + '{display:none!important}');
    });
    return rules.join('\n');
  }
  function ensureStyle() {
    var st = document.getElementById(STYLE_ID);
    if (!st) {
      st = document.createElement('style');
      st.id = STYLE_ID;
      (document.head || document.documentElement).appendChild(st);
    }
    var css = buildCSS();
    if (st.textContent !== css) st.textContent = css;
  }

  // ---------- 글/댓글 단위 찾기 ----------
  function articleHead() { return document.querySelector('.gallview-tit-box, [class^="gallview-tit-box"]'); }
  function articleBody() { return document.querySelector('.thum-txtin'); }

  function findUnits() {
    var list = [];
    var seen = new Set();
    function add(el, kind) {
      if (seen.has(el)) return;
      seen.add(el);
      list.push({ el: el, kind: kind });
      if (el.getAttribute('data-dcapp-unit') !== kind) el.setAttribute('data-dcapp-unit', kind);
    }
    document.querySelectorAll('ul.gall-detail-lst > li').forEach(function (li) {
      if (/(^|\s)ad/.test(clsOf(li))) return;
      if (!li.querySelector('a')) return;
      add(li, 'post');
    });
    document.querySelectorAll('ul[class*="comment"] > li, ol[class*="comment"] > li').forEach(function (li) {
      if (li.closest('ul.gall-detail-lst')) return;
      if (!txt(li)) return;
      add(li, 'comment');
    });
    var head = articleHead();
    if (head) add(head, 'article');
    return list;
  }

  // ---------- 작성자 정보 ----------
  function nickElement(u) {
    var el = u.el;
    var byClass = el.querySelector('[class*="nick"]');
    if (u.kind === 'post') {
      var g = el.querySelector('.ginfo');
      if (g && g.children.length) return g.children.length >= 5 ? g.children[1] : g.children[0];
      return byClass;
    }
    if (u.kind === 'comment') return byClass || el.firstElementChild;
    if (u.kind === 'article') {
      if (byClass) return byClass;
      var info = el.children[1];
      return info && info.firstElementChild && (info.firstElementChild.firstElementChild || info.firstElementChild);
    }
    return byClass;
  }

  function identity(u) {
    var r = { nick: '', id: '', ip: '' };
    var el = u.el;
    var nickEl = nickElement(u);
    if (nickEl) {
      var raw = txt(nickEl);
      var m = raw.match(IP_RE);
      if (m) r.ip = m[1];
      r.nick = raw.replace(IP_RE, '').trim().slice(0, 40);
      if (!r.ip && nickEl.parentElement && nickEl.parentElement !== el.parentElement) {
        var m2 = txt(nickEl.parentElement).match(IP_RE);
        if (m2) r.ip = m2[1];
      }
    }
    var di = el.querySelector('[data-info]');
    if (di) {
      var v = (di.getAttribute('data-info') || '').trim();
      if (/^\d{1,3}\.\d{1,3}$/.test(v)) { if (!r.ip) r.ip = v; } else if (v) r.id = v;
    }
    if (!r.id) {
      var a = el.querySelector('a[href*="gallog"]');
      if (a) {
        var p = (a.getAttribute('href') || '').split(/[?#]/)[0].replace(/\/+$/, '').split('/');
        r.id = p[p.length - 1] || '';
      }
    }
    return r;
  }

  // ---------- 디시콘 ----------
  function mediaSrc(m) {
    var s = m.getAttribute('data-original') || m.getAttribute('data-src') || m.getAttribute('src') || '';
    if (!s && m.tagName === 'VIDEO') {
      var so = m.querySelector('source');
      if (so) s = so.getAttribute('src') || '';
    }
    return s;
  }
  function imgURL(x) {
    var s = x.getAttribute('data-original') || x.getAttribute('data-src') || x.currentSrc || x.src || '';
    if (!s || /^data:/.test(s)) return '';
    try { return new URL(s, location.href).href; } catch (e) { return ''; }
  }
  function dcconKey(m) {
    if (!m || !m.tagName || !/^(IMG|VIDEO)$/.test(m.tagName)) return null;
    var s = mediaSrc(m);
    if (!/dccon/i.test(s) && !/dccon/i.test(clsOf(m))) return null;
    var q = s.match(/[?&]no=([^&#]+)/);
    return q ? q[1] : (s.split('#')[0] || null);
  }

  // ---------- 차단 판정 ----------
  function blockedReason(u, idn, dset) {
    var users = cfg.users || [];
    for (var i = 0; i < users.length; i++) {
      var b = users[i];
      if ((b.k === 'id' && idn.id && idn.id === b.v) ||
          (b.k === 'ip' && idn.ip && idn.ip === b.v) ||
          (b.k === 'nick' && idn.nick && idn.nick === b.v)) return '차단한 유저';
    }
    var kws = cfg.keywords || [];
    if (kws.length) {
      var t = txt(u.el);
      if (u.kind === 'article') t += ' ' + txt(articleBody());
      t = t.toLowerCase();
      for (var j = 0; j < kws.length; j++) {
        if (kws[j] && t.indexOf(kws[j]) >= 0) return '차단 키워드';
      }
    }
    if (u.kind === 'comment' && dset.size) {
      var media = u.el.querySelectorAll('img, video');
      for (var k = 0; k < media.length; k++) {
        var key = dcconKey(media[k]);
        if (key && dset.has(key)) return '차단한 디시콘';
      }
    }
    return null;
  }

  function mark(el, reason, mode) {
    el.classList.remove('dcapp-hide', 'dcapp-collapsed');
    if (!reason) { el.removeAttribute('data-dcapp-label'); return; }
    if (mode === 'remove') {
      el.classList.add('dcapp-hide');
    } else {
      el.classList.add('dcapp-collapsed');
      el.setAttribute('data-dcapp-label', reason + ' · 탭해서 보기');
    }
  }

  // ---------- 실시간 베스트 알림 숨기기 ----------
  function looksLikeBestNotice(el) {
    var t = txt(el);
    if (!t || t.length > 300) return false;
    return /실시간\s*베스트|실베/.test(t);
  }
  function hideBestNotice() {
    // 1) 알림/토스트/팝업 성격의 클래스나 id를 가진 요소
    document.querySelectorAll('[class],[id]').forEach(function (el) {
      if (el === document.body || el === document.documentElement) return;
      var name = clsOf(el) + ' ' + (el.id || '');
      if (!NOTICE_CLASS_RE.test(name)) return;
      if (el.classList.contains('dcapp-hide')) return;
      if (looksLikeBestNotice(el)) el.classList.add('dcapp-hide');
    });
    // 2) 화면에 고정(fixed/sticky)으로 떠 있는 요소
    var roots = Array.prototype.slice.call(document.body ? document.body.children : []);
    roots.forEach(function (r) { roots = roots.concat(Array.prototype.slice.call(r.children)); });
    roots.forEach(function (el) {
      if (el.classList.contains('dcapp-hide')) return;
      var pos = getComputedStyle(el).position;
      if ((pos === 'fixed' || pos === 'sticky') && looksLikeBestNotice(el)) el.classList.add('dcapp-hide');
    });
  }

  // ---------- 사이트 상단 머리글(디시 로고·통합검색·갤러리/마이너갤/미니갤 메뉴) 숨기기 ----------
  // 앱의 남색 상단바와 하단 바가 같은 역할을 하므로 웹페이지 쪽 머리글은 숨김
  function topAncestor(el, maxH) {
    var best = null;
    for (var cur = el; cur && cur !== document.body && cur !== document.documentElement; cur = cur.parentElement) {
      var r = cur.getBoundingClientRect();
      var top = r.top + window.scrollY;
      if (top > 160 || r.height > maxH) break;
      best = cur;
    }
    return best;
  }
  function hideSiteHeader() {
    if (!/(^|\.)m\.dcinside\.com$/.test(location.hostname)) return;
    var targets = [];
    var inp = document.querySelector('input[placeholder*="통합검색"]');
    if (inp) targets.push(topAncestor(inp, 180));
    var lists = document.querySelectorAll('nav, ul');
    for (var i = 0; i < lists.length; i++) {
      var t = txt(lists[i]);
      if (t.length < 80 && /마이너갤/.test(t) && /미니갤/.test(t) && /인물갤/.test(t)) {
        targets.push(topAncestor(lists[i], 140));
        break;
      }
    }
    // 갤러리 이름 줄 ("아이패드 ⓜ (1,085,094) ☆ | ⓘ 설정 연관 글쓰기") — 앱 상단바에 갤러리 이름이 있으므로 숨김
    var rows = document.querySelectorAll('div, section, header');
    var row = null;
    for (var j = 0; j < rows.length; j++) {
      var rt = txt(rows[j]);
      if (rt.length < 80 && /연관/.test(rt) && /설정/.test(rt) && /글쓰기/.test(rt)) row = rows[j];   // 가장 안쪽 것으로 갱신
    }
    if (row) targets.push(topAncestor(row, 110));
    // 오른쪽 아래에 떠 있는 남색 글쓰기(연필) 버튼 — 앱 하단 바에 글쓰기가 있으므로 숨김
    document.querySelectorAll('#fab, button.fab').forEach(function (el) { targets.push(el); });   // 디시 모바일의 연필 버튼
    var writeBtns = document.querySelectorAll('a[href*="write"], button, [class*="write"], [class*="btn-top"]');
    for (var w = 0; w < writeBtns.length; w++) {
      var cand = writeBtns[w];
      var label = (cand.getAttribute('href') || '') + ' ' + clsOf(cand) + ' ' + txt(cand);
      if (!/write|글쓰기/i.test(label)) continue;
      for (var up = 0, el2 = cand; el2 && el2 !== document.body && up < 4; up++, el2 = el2.parentElement) {
        var pos = getComputedStyle(el2).position;
        if (pos === 'fixed' || pos === 'sticky') {
          var rr = el2.getBoundingClientRect();
          if (rr.width > 0 && rr.width < 130 && rr.height < 130 && rr.left > window.innerWidth / 2) targets.push(el2);
          break;
        }
      }
    }
    targets.forEach(function (el) { if (el) el.classList.add('dcapp-hide', 'dcapp-header-hidden'); });
  }

  // ---------- 홈 화면 → 실북갤 순위만 (펼친 상태) ----------
  function isHomePage() {
    return /(^|\.)m\.dcinside\.com$/.test(location.hostname) && /^\/(index(\.php)?)?$/.test(location.pathname);
  }
  function rankTab() {
    return document.querySelector('a[href*="rankHotgallChange(\'rank\')"], [onclick*="rankHotgallChange(\'rank\')"]');
  }
  function rankToggles() {
    return Array.prototype.slice.call(document.querySelectorAll('a[href*="rankopen_tap"], [onclick*="rankopen_tap"]'));
  }
  function isShown(el) { return !!(el && el.getClientRects().length && getComputedStyle(el).visibility !== 'hidden'); }
  function rankIsOpen() {
    // 펼쳐지면 목록 아래 '닫기'가 보임
    return rankToggles().some(function (a) { return /닫기/.test(txt(a)) && isShown(a); });
  }
  function commonAncestor(a, b) {
    for (var x = a; x; x = x.parentElement) if (x.contains(b)) return x;
    return null;
  }
  var homeTries = 0, homeOpened = false;
  function clearHomeRank() {
    document.querySelectorAll('.dcapp-home-off').forEach(function (el) { el.classList.remove('dcapp-home-off'); });
    document.documentElement.classList.remove('dcapp-home-wait');
  }
  function homeRankOnly() {
    if (!isHomePage() || cfg.homeRank === false) { clearHomeRank(); return; }
    var tab = rankTab();
    if (!tab) return;
    if (!homeOpened && rankIsOpen()) homeOpened = true;
    if (!homeOpened) {
      if (homeTries < 6 && typeof window.rankopen_tap === 'function') {
        homeTries++;
        try { window.rankopen_tap(); } catch (e) {}
        setTimeout(schedule, 350);
      }
      if (!rankIsOpen()) return;
      homeOpened = true;
    }
    var close = rankToggles().filter(function (a) { return /닫기/.test(txt(a)) && (isShown(a) || a.classList.contains('dcapp-home-off')); })[0];
    var panel = commonAncestor(tab, close) || tab;
    // 순위 판에 들어 있는 것만 남기고 홈의 나머지(실베, 개념글, 신설갤, 디시미디어 …)는 숨김
    for (var node = panel; node && node.parentElement && node !== document.body; node = node.parentElement) {
      var sibs = node.parentElement.children;
      for (var i = 0; i < sibs.length; i++) {
        var sib = sibs[i];
        if (sib === node) continue;
        var tag = sib.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'LINK' || tag === 'META') continue;
        if (/dcapp/.test(clsOf(sib) + ' ' + (sib.id || ''))) continue;
        sib.classList.add('dcapp-home-off');
      }
    }
    // 펼침 상태를 유지하도록 '닫기' / '더보기' 버튼은 숨김
    rankToggles().forEach(function (a) {
      if (panel.contains(a) || /더보기|닫기/.test(txt(a))) a.classList.add('dcapp-home-off');
    });
    document.documentElement.classList.remove('dcapp-home-wait');
  }
  if (isHomePage() && cfg.homeRank !== false) {
    document.documentElement.classList.add('dcapp-home-wait');
    setTimeout(function () { document.documentElement.classList.remove('dcapp-home-wait'); }, 1500);   // 못 찾아도 화면은 보이게
  }

  // ---------- 전체 적용 ----------
  // ---------- 로그인 후 '비밀번호 변경 안내' 건너뛰기 ----------
  var PW_SKIP_RE = /^(다음에|나중에)|(다음에|나중에|\d+(일|개월)(후|뒤)에?)변경|^(변경하지않기|건너뛰기|다음에하기|그냥계속)/;
  function pwSkipButtons() {
    return Array.prototype.filter.call(document.querySelectorAll('button, a, input[type="button"], input[type="submit"], [role="button"]'), function (b) {
      return PW_SKIP_RE.test((txt(b) || b.value || '').replace(/\s/g, ''));
    });
  }
  /// 버튼 주변(가까운 조상 5단계 안)에 '비밀번호 … 변경' 문구가 있어야 진짜 안내창으로 봄
  /// (글 화면에 숨어 있는 부매니저 임명 팝업의 '다음에 다시 확인' 같은 버튼을 잘못 누르지 않도록)
  function pwNagButton() {
    return pwSkipButtons().filter(function (b) {
      if (!visible(b)) return false;
      if (b.closest && b.closest('[id*="appoint"]')) return false;
      for (var el = b.parentElement, up = 0; el && el !== document.body && up < 5; el = el.parentElement, up++) {
        var t = txt(el);
        if (t.length > 600) break;
        if (/비밀번호/.test(t) && /변경/.test(t)) return true;
      }
      return false;
    })[0] || null;
  }
  function skipPwChange() {
    if (cfg.skipPwChange === false || !/(^|\.)dcinside\.com$/.test(location.hostname)) return;
    var b = pwNagButton();
    if (!b) return;
    var key = 'dcapp-pwskip', last = 0;
    try { last = +(sessionStorage.getItem(key) || 0); } catch (e) {}
    if (Date.now() - last < 5000) return;               // 연속 클릭 방지
    try { sessionStorage.setItem(key, String(Date.now())); } catch (e) {}
    b.click();
    post('pwskip', { label: txt(b) || b.value || '' });
  }

  // ---------- 댓글돌이 (뉴스 링크를 다는 자동 댓글 봇) ----------
  // 만두 모양 아이콘(클래스나 그림 주소에 dory)으로만 구분 → 그 댓글 칸(li)을 숨김
  // (닉네임만 '댓글돌이'인 사람은 숨기지 않음)
  function doryItems() {
    var out = [];
    function add(el) {
      var li = el && el.closest ? el.closest('li') : null;
      if (li && out.indexOf(li) < 0) out.push(li);
    }
    document.querySelectorAll('[class*="dory"], img[src*="dory"]').forEach(add);
    return out;
  }
  function hideDory() {
    var on = cfg.hideDory !== false;
    document.querySelectorAll('.dcapp-dory').forEach(function (el) { if (!on) el.classList.remove('dcapp-dory'); });
    if (on) doryItems().forEach(function (li) { li.classList.add('dcapp-dory'); });
  }

  function apply() {
    ensureStyle();
    try { hideDory(); } catch (e) {}
    try { skipPwChange(); } catch (e) {}
    var enabled = cfg.enabled !== false;
    var mode = cfg.mode || 'collapse';
    var dset = new Set(cfg.dccons || []);
    findUnits().forEach(function (u) {
      var reason = null;
      if (enabled && u.el.getAttribute('data-dcapp-revealed') !== '1') reason = blockedReason(u, identity(u), dset);
      mark(u.el, reason, mode);
      if (u.kind === 'article') {
        var body = articleBody();
        if (body) body.classList.toggle('dcapp-hide', !!reason);
      }
    });
    document.querySelectorAll('img, video').forEach(function (m) {
      var k = dcconKey(m);
      if (k) m.classList.toggle('dcapp-dccon-off', enabled && dset.has(k));
    });
    if (enabled && cfg.hideBest) hideBestNotice();
    try { homeRankOnly(); } catch (e) {}
    if (cfg.hideHeader !== false) hideSiteHeader();
    else document.querySelectorAll('.dcapp-header-hidden').forEach(function (el) { el.classList.remove('dcapp-hide', 'dcapp-header-hidden'); });
  }

  // ---------- 길게 누르기 → 차단 메뉴 ----------
  function describe(unitEl, target) {
    var d = { kind: 'dccon', nick: '', userId: '', ip: '', snippet: '', dcconKey: '', dcconSrc: '' };
    if (unitEl) {
      var u = { el: unitEl, kind: unitEl.getAttribute('data-dcapp-unit') };
      var idn = identity(u);
      d.kind = u.kind; d.nick = idn.nick; d.userId = idn.id; d.ip = idn.ip;
      d.snippet = txt(unitEl).slice(0, 80);
    }
    var m = target && target.closest ? target.closest('img, video') : null;
    var key = dcconKey(m);
    if (!key && unitEl) {
      var all = Array.prototype.filter.call(unitEl.querySelectorAll('img, video'), dcconKey);
      if (all.length === 1) { m = all[0]; key = dcconKey(m); }
    }
    if (key) { d.dcconKey = key; d.dcconSrc = mediaSrc(m); }
    return d;
  }

  var lp = null;
  var suppressClickUntil = 0;
  function clearLP() { if (lp) { clearTimeout(lp.timer); lp = null; } }

  document.addEventListener('touchstart', function (e) {
    if (pick.on || blockPick || e.touches.length !== 1) return;
    var target = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!target || !target.closest) return;
    var unitEl = target.closest('[data-dcapp-unit]');
    var media = target.closest('img, video');
    if (!unitEl && !dcconKey(media)) return;
    if (unitEl && unitEl.classList.contains('dcapp-collapsed')) return;
    var t = e.touches[0];
    clearLP();
    lp = {
      x: t.clientX, y: t.clientY,
      timer: setTimeout(function () {
        lp = null;
        suppressClickUntil = Date.now() + 800;
        post('longpress', describe(unitEl, target));
      }, 550)
    };
  }, { capture: true, passive: true });
  document.addEventListener('touchmove', function (e) {
    if (!lp) return;
    var t = e.touches[0];
    if (Math.abs(t.clientX - lp.x) > 10 || Math.abs(t.clientY - lp.y) > 10) clearLP();
  }, { capture: true, passive: true });
  document.addEventListener('touchend', clearLP, { capture: true, passive: true });
  document.addEventListener('touchcancel', clearLP, { capture: true, passive: true });

  // ---------- 요소 선택해서 숨기기 ----------
  var pick = { on: false, el: null };
  var blockPick = false;   // 탭해서 유저 차단 모드
  function cleanClasses(el) {
    return clsOf(el).split(/\s+/).filter(function (c) {
      return c && !/^dcapp-/.test(c) && /^[A-Za-z_-][\w-]*$/.test(c) && !/\d{3,}/.test(c);
    });
  }
  function selPart(el) {
    if (el.id && /^[A-Za-z][\w-]*$/.test(el.id) && !/\d{3,}/.test(el.id)) return '#' + el.id;
    var c = cleanClasses(el);
    return el.tagName.toLowerCase() + (c.length ? '.' + c.slice(0, 3).join('.') : '');
  }
  function selectorFor(el) {
    var parts = [], cur = el, depth = 0;
    while (cur && cur.nodeType === 1 && cur !== document.body && cur !== document.documentElement && depth < 5) {
      var p = selPart(cur);
      parts.unshift(p);
      if (p.charAt(0) === '#') break;
      if (depth >= 1 && cleanClasses(cur).length && document.querySelectorAll(parts.join(' > ')).length === 1) break;
      cur = cur.parentElement;
      depth++;
    }
    return parts.join(' > ');
  }
  function clearPick() {
    if (pick.el) pick.el.classList.remove('dcapp-pick');
    pick.el = null;
  }
  function choose(el, delay) {
    clearPick();
    if (!el || el === document.body || el === document.documentElement) return;
    pick.el = el;
    el.classList.add('dcapp-pick');
    var sel = selectorFor(el);
    var count = 0;
    try { count = document.querySelectorAll(sel).length; } catch (e) {}
    setTimeout(function () {
      post('picked', { selector: sel, count: count, snippet: txt(el).slice(0, 60), tag: el.tagName.toLowerCase() });
    }, delay || 0);
  }

  // ---------- 클릭 처리 (길게누르기 후 클릭 무시 / 접힌 글 펼치기 / 선택모드 / 로그인 저장) ----------
  document.addEventListener('click', function (e) {
    var target = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (blockPick) {
      e.preventDefault(); e.stopPropagation();
      var unitEl = target && target.closest ? target.closest('[data-dcapp-unit]') : null;
      var media = target && target.closest ? target.closest('img, video') : null;
      if (unitEl || dcconKey(media)) post('longpress', describe(unitEl, target));
      else post('blockmiss', {});
      return;
    }
    if (pick.on) {
      e.preventDefault(); e.stopPropagation();
      choose(target, 0);
      return;
    }
    if (Date.now() < suppressClickUntil) {
      e.preventDefault(); e.stopPropagation();
      suppressClickUntil = 0;
      return;
    }
    var c = target && target.closest && target.closest('.dcapp-collapsed');
    if (c) {
      e.preventDefault(); e.stopPropagation();
      c.setAttribute('data-dcapp-revealed', '1');
      apply();
      return;
    }
    // 글 속 사진 탭 → 앱 사진 보기 (아래로 쓸어 닫기 / 확대 / 넘기기)
    var tapped = target && target.closest ? target.closest('img') : null;
    var abody = tapped ? articleBody() : null;
    if (abody && abody.contains(tapped) && !dcconKey(tapped)) {
      var shots = Array.prototype.filter.call(abody.querySelectorAll('img'), function (x) {
        return !dcconKey(x) && imgURL(x) && ((x.naturalWidth || x.width) > 40 || x === tapped);
      });
      var at = shots.indexOf(tapped);
      if (at >= 0) {
        e.preventDefault(); e.stopPropagation();
        post('images', { urls: shots.map(imgURL), index: at });
        return;
      }
    }
    if (isLoginPage() && target && target.closest && target.closest('button, input[type="submit"], input[type="button"], a, [role="button"]')) {
      captureCreds();
    }
  }, true);

  // ---------- 로그인 ----------
  function isLoginPage() { return /^msign\./.test(location.hostname); }
  function loginFields() {
    var pw = document.querySelector('input[type="password"]');
    if (!pw) return null;
    var scope = pw.form || document;
    var ids = Array.prototype.filter.call(scope.querySelectorAll('input'), function (i) {
      return ['text', 'email', 'tel'].indexOf(i.type) >= 0 && !i.disabled &&
        (pw.compareDocumentPosition(i) & Node.DOCUMENT_POSITION_PRECEDING);
    });
    return { pw: pw, id: ids[ids.length - 1] || null, form: pw.form };
  }
  function captureCreds() {
    var f = loginFields();
    if (f && f.id && f.id.value && f.pw.value) post('credentials', { id: f.id.value, pw: f.pw.value });
  }
  document.addEventListener('submit', function () { if (isLoginPage()) captureCreds(); }, true);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && isLoginPage()) captureCreds();
  }, true);

  function setVal(el, v) {
    var d = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    d.set.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  // force: 계정 전환처럼 사용자가 직접 고른 경우 → 재시도 방지(60초) 규칙을 건너뜀
  function fillLogin(id, pw, auto, tries, force) {
    tries = tries || 0;
    var f = loginFields();
    if (!f || !f.id) {
      if (tries < 10) setTimeout(function () { fillLogin(id, pw, auto, tries + 1, force); }, 300);
      return 'waiting';
    }
    setVal(f.id, id);
    setVal(f.pw, pw);
    if (!auto) return 'filled';
    var key = 'dcapp-autologin', last = 0;
    try { last = +(sessionStorage.getItem(key) || 0); } catch (e) {}
    if (!force && Date.now() - last < 60000) return 'skipped'; // 실패 시 무한 재시도 방지
    try { sessionStorage.setItem(key, String(Date.now())); } catch (e) {}
    var scope = f.form || document;
    var btn = scope.querySelector('button[type="submit"], input[type="submit"]') ||
      Array.prototype.find.call(scope.querySelectorAll('button, a, input[type="button"], [role="button"]'), function (b) {
        return /^\s*로그인\s*$/.test(txt(b) || b.value || '');
      });
    setTimeout(function () {
      if (btn) btn.click();
      else if (f.form) { if (f.form.requestSubmit) f.form.requestSubmit(); else f.form.submit(); }
    }, 300);
    return 'submitted';
  }

  // ---------- 캡처 준비 (지연 로딩 이미지 강제 로드) ----------
  function prepareCapture() {
    clearPick();
    var n = 0;
    document.querySelectorAll('img').forEach(function (img) {
      var d = img.getAttribute('data-original') || img.getAttribute('data-src');
      if (d && img.getAttribute('src') !== d) { img.setAttribute('src', d); n++; }
      try { img.loading = 'eager'; } catch (e) {}
    });
    return n;
  }

  // ---------- 자짤 (글쓰기 화면에 사진 자동 첨부) ----------
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function findFileInput() {
    // 디시 글쓰기 본문 사진 첨부 칸을 가장 먼저 (편집기 팝업 안의 칸은 뒤로)
    var main = document.querySelector('input[type="file"]#upload, input[type="file"][name="upload[]"]');
    if (main && !main.disabled) return main;
    var inputs = Array.prototype.filter.call(document.querySelectorAll('input[type="file"]'), function (i) {
      return !i.disabled;
    });
    var img = inputs.filter(function (i) {
      var a = (i.getAttribute('accept') || '').toLowerCase();
      return !a || a.indexOf('image') >= 0 || a.indexOf('.jpg') >= 0 || a.indexOf('.gif') >= 0;
    });
    return img[0] || inputs[0] || null;
  }
  async function attachImage(b64, name, mime, force) {
    var key = 'dcapp-autoimg:' + location.pathname;
    if (!force) {
      var last = 0;
      try { last = +(sessionStorage.getItem(key) || 0); } catch (e) {}
      if (Date.now() - last < 10 * 60 * 1000) return 'already';   // 새로고침해도 중복 첨부 방지
    }
    var input = null;
    for (var t = 0; t < 15 && !input; t++) {
      input = findFileInput();
      if (!input) await sleep(400);
    }
    if (!input) return 'noinput';
    try {
      var bin = atob(b64);
      var bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      var file = new File([bytes], name, { type: mime });
      var dt = new DataTransfer();
      dt.items.add(file);
      input.files = dt.files;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (e) {
      return 'error:' + e.message;
    }
    try { sessionStorage.setItem(key, String(Date.now())); } catch (e) {}
    return 'attached';
  }

  // ---------- 임시저장 (글쓰기 제목/본문 읽기·쓰기, 자동 저장) ----------
  function visible(el) { return !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length)); }
  function area(el) { var r = el.getBoundingClientRect(); return r.width * r.height; }
  function writeFields() {
    var texts = Array.prototype.filter.call(document.querySelectorAll('input'), function (i) {
      return ['text', 'search'].indexOf(i.type) >= 0 && !i.disabled && visible(i);
    });
    function label(i) { return ((i.name || '') + ' ' + (i.id || '') + ' ' + (i.getAttribute('placeholder') || '')).toLowerCase(); }
    var title = texts.filter(function (i) { return /subject|title|제목/.test(label(i)); })[0] ||
      texts.filter(function (i) { return !/name|nick|pass|pw|닉네임|비밀번호|search|keyword|검색/.test(label(i)); })[0] || null;
    var editables = Array.prototype.filter.call(document.querySelectorAll('[contenteditable="true"], [contenteditable=""]'), visible);
    var body = null, html = false;
    if (editables.length) {
      body = editables.sort(function (a, b) { return area(b) - area(a); })[0];
      html = true;
    } else {
      var tas = Array.prototype.filter.call(document.querySelectorAll('textarea'), function (t) { return !t.disabled && visible(t); });
      if (tas.length) body = tas.sort(function (a, b) { return area(b) - area(a); })[0];
    }
    return { title: title, body: body, html: html };
  }
  function getDraft() {
    var f = writeFields();
    return {
      ok: !!(f.title || f.body),
      title: f.title ? f.title.value : '',
      body: f.body ? (f.html ? f.body.innerHTML : f.body.value) : '',
      text: f.body ? (f.html ? txt(f.body) : f.body.value).slice(0, 200) : '',
      html: f.html
    };
  }
  function setField(el, v) {
    var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function setDraft(title, body, html) {
    var f = writeFields();
    if (!f.title && !f.body) return 'nofield';
    if (f.title && title != null) setField(f.title, title);
    if (f.body && body != null) {
      if (f.html) {
        f.body.innerHTML = html ? body : body.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n/g, '<br>');
        f.body.dispatchEvent(new Event('input', { bubbles: true }));
      } else {
        var plain = body;
        if (html) { var tmp = document.createElement('div'); tmp.innerHTML = body.replace(/<br\s*\/?>/gi, '\n'); plain = tmp.textContent; }
        setField(f.body, plain);
      }
    }
    return 'restored';
  }
  var autosaveTimer = null, lastDraftSig = '';
  function startAutosave() {
    if (autosaveTimer) return true;
    lastDraftSig = '';
    var d0 = getDraft();
    lastDraftSig = d0.title + '\u0000' + d0.body;   // 처음 열었을 때 상태는 저장하지 않음
    autosaveTimer = setInterval(function () {
      var d = getDraft();
      if (!d.ok) return;
      var sig = d.title + '\u0000' + d.body;
      if (sig === lastDraftSig) return;
      lastDraftSig = sig;
      if (!d.title.trim() && !d.text.trim()) return;
      post('draft', d);
    }, 15000);
    return true;
  }

  // ---------- 댓글창을 키보드 바로 위에 고정 (공식 앱처럼) ----------
  var dock = { el: null, ph: null };
  function isCommentField(el) {
    if (!el || el.nodeType !== 1) return false;
    if (/\/write/.test(location.pathname)) return false;          // 글쓰기 화면 본문은 제외
    if (!(el.tagName === 'TEXTAREA' || el.isContentEditable)) return false;
    if (el.classList.contains('comment-caption')) return true;     // 디시 모바일 댓글칸
    var lab = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('placeholder') || '') + ' ' + clsOf(el)).toLowerCase();
    return /comment|cmt|reply|memo|댓글/.test(lab) || !!el.closest('[class*="comment"],[id*="comment"],[class*="cmt"]');
  }
  // 닉네임/비번/코드 칸을 눌렀을 때도 같은 댓글창으로 인식
  function commentFieldNear(el) {
    if (isCommentField(el)) return el;
    if (!el || el.tagName !== 'INPUT') return null;
    var cur = el.parentElement;
    for (var i = 0; cur && cur !== document.body && i < 6; i++, cur = cur.parentElement) {
      var tas = cur.querySelectorAll('textarea, [contenteditable="true"]');
      for (var j = 0; j < tas.length; j++) if (isCommentField(tas[j])) return tas[j];
    }
    return null;
  }
  function inputCount(el) {
    return Array.prototype.filter.call(el.querySelectorAll('input'), function (i) {
      return ['text', 'password', 'tel', 'number', ''].indexOf(i.type) >= 0 && visible(i);
    }).length;
  }
  function hasSubmit(el) {
    return Array.prototype.some.call(el.querySelectorAll('button, a, input[type="button"], input[type="submit"]'), function (b) {
      return /^\s*(등록|작성|확인)\s*$/.test(txt(b) || b.value || '');
    });
  }
  function containsList(el) {
    return !!el.querySelector('[data-dcapp-unit="comment"], ul[class*="comment"] > li, ol[class*="comment"] > li');
  }
  /// 댓글 입력 영역 고르기: 등록 버튼을 포함하는 가장 작은 박스에서 시작해서,
  /// 바로 위 부모가 닉네임/비번/코드 같은 입력칸을 더 담고 있을 때만 한 단계씩 넓힘
  /// (댓글 수·정렬 같은 머리글이나 댓글 목록은 포함하지 않음)
  function commentContainer(field) {
    var vh = window.innerHeight, best = null;
    var cur = field.parentElement;
    for (var i = 0; cur && cur !== document.body && i < 8; i++, cur = cur.parentElement) {
      if (cur.getBoundingClientRect().height > vh * 0.55 || containsList(cur)) break;
      if (hasSubmit(cur)) { best = cur; break; }
    }
    if (!best) {
      var form = field.closest('form');
      best = (form && form.getBoundingClientRect().height <= vh * 0.55) ? form : field.parentElement;
    }
    while (best.parentElement && best.parentElement !== document.body) {
      var p = best.parentElement;
      if (p.getBoundingClientRect().height > vh * 0.55 || containsList(p)) break;
      if (inputCount(p) <= inputCount(best)) break;
      best = p;
    }
    return best;
  }
  function positionDock() {
    positionTDock();
    if (!dock.el) return;
    var vv = window.visualViewport;
    var h = dock.el.offsetHeight;
    var top = vv ? vv.offsetTop + vv.height - h : window.innerHeight - h;
    dock.el.style.setProperty('top', Math.max(0, Math.round(top)) + 'px', 'important');
  }
  function dockOn(field) {
    var c = commentContainer(field);
    if (!c || dock.el === c) { positionDock(); return; }
    undock();
    var ph = document.createElement('div');            // 원래 자리가 비어서 화면이 튀지 않게
    ph.className = 'dcapp-dock-ph';
    ph.style.height = c.getBoundingClientRect().height + 'px';
    c.parentNode.insertBefore(ph, c);
    var bg = getComputedStyle(c).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = getComputedStyle(document.body).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = '#fff';
    var head = document.createElement('div');           // 공식 앱처럼 오른쪽 위 X 버튼
    head.className = 'dcapp-dock-head';
    head.innerHTML = '<span>댓글 작성</span><button type="button" class="dcapp-dock-close" aria-label="닫기">✕</button>';
    head.querySelector('button').addEventListener('click', function (e) {
      e.preventDefault(); e.stopPropagation();
      var a = document.activeElement;
      if (a && a.blur) a.blur();                          // 키보드 내리기
      undock();
    });
    c.insertBefore(head, c.firstChild);
    c.classList.add('dcapp-docked');
    c.style.setProperty('background-color', bg, 'important');
    dock.el = c; dock.ph = ph; dock.head = head;
    if (window.ResizeObserver) {                       // 댓글창 안 내용이 늘어나면 위치 다시 맞추기
      dock.ro = new ResizeObserver(function () { positionDock(); });
      dock.ro.observe(c);
    }
    positionDock();
  }
  function undock() {
    if (!dock.el) return;
    dock.el.classList.remove('dcapp-docked');
    dock.el.style.removeProperty('top');
    dock.el.style.removeProperty('background-color');
    if (dock.ph && dock.ph.parentNode) dock.ph.parentNode.removeChild(dock.ph);
    if (dock.head && dock.head.parentNode) dock.head.parentNode.removeChild(dock.head);
    if (dock.ro) { dock.ro.disconnect(); dock.ro = null; }
    dock.el = null; dock.ph = null; dock.head = null;
  }
  document.addEventListener('focusin', function (e) {
    if (cfg.dockComment === false) return;
    var f = commentFieldNear(e.target);
    if (f) dockOn(f);
  }, true);

  // 디시콘 버튼을 누르면 고정을 풀고(디시 원래 방식대로 목록이 펼쳐지게) 목록이 보이도록 스크롤
  function isDcconButton(el) {
    for (var cur = el, i = 0; cur && i < 4; i++, cur = cur.parentElement) {
      if (cur.nodeType !== 1) continue;
      var label = clsOf(cur) + ' ' + (cur.id || '') + ' ' + (cur.getAttribute('alt') || '') + ' ' +
                  (cur.getAttribute('title') || '') + ' ' + (cur.getAttribute('onclick') || '') + ' ' + txt(cur).slice(0, 10);
      if (/dccon|디시콘/i.test(label)) return true;
    }
    return false;
  }
  function revealDcconList(tries) {
    tries = tries || 0;
    var lists = Array.prototype.filter.call(document.querySelectorAll('[class*="dccon"], [id*="dccon"]'), function (el) {
      var r = el.getBoundingClientRect();
      return visible(el) && r.height > 80 && r.width > window.innerWidth * 0.5;
    });
    if (lists.length) {
      var target = lists.sort(function (a, b) { return area(b) - area(a); })[0];
      if (getComputedStyle(target).position !== 'fixed') target.scrollIntoView({ block: 'center', behavior: 'smooth' });
    } else if (tries < 8) {
      setTimeout(function () { revealDcconList(tries + 1); }, 150);
    }
  }
  document.addEventListener('click', function (e) {
    if (!dock.el) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!t || !dock.el.contains(t) || !isDcconButton(t)) return;
    var a = document.activeElement;
    if (a && a.blur) a.blur();
    var formEl = dock.el;
    undock();
    setTimeout(function () {
      formEl.scrollIntoView({ block: 'start' });
      revealDcconList(0);
    }, 120);
  }, true);

  // 댓글 "등록"을 누르면 등록이 진행되도록 잠깐 기다렸다가 키보드 내리고 댓글창 원래 자리로
  document.addEventListener('click', function (e) {
    if (!dock.el) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    var b = t && t.closest && t.closest('button, a, input[type="submit"], input[type="button"]');
    if (!b || !dock.el.contains(b)) return;
    if (!/^\s*(등록|작성|확인)\s*$/.test(txt(b) || b.value || '')) return;
    setTimeout(function () {
      var a = document.activeElement;
      if (a && a.blur) a.blur();
      undock();
    }, 350);
  }, true);

  // ---------- 글쓰기: 사진·동영상·디시콘 등 편집 도구줄을 키보드 바로 위에 고정 ----------
  var tdock = { el: null, ph: null };
  function isWritePage() { return /\/write/.test(location.pathname); }
  function isWriteField(el) {
    if (!el || el.nodeType !== 1 || !isWritePage()) return false;
    var f = writeFields();
    return el === f.title || el === f.body || (f.body && f.body.contains(el)) || el.isContentEditable;
  }
  function editorToolbar() {
    var vh = window.innerHeight;
    // 1) 디시 글쓰기 도구 아이콘(사진·동영상·디시콘·유튜브…)이 모여 있는 줄
    var icons = Array.prototype.filter.call(
      document.querySelectorAll('.sp-write-form-icon, [class*="write-form-icon"]'), visible);
    if (icons.length) {
      var need = Math.min(3, icons.length);
      for (var cur = icons[0].parentElement, i = 0; cur && cur !== document.body && i < 6; i++, cur = cur.parentElement) {
        var cnt = icons.filter(function (b) { return cur.contains(b); }).length;
        if (cnt >= need) {
          return cur.getBoundingClientRect().height < vh * 0.25 ? cur : icons[0].parentElement;
        }
      }
    }
    // 2) 못 찾으면: 사진 첨부 칸 근처에서 버튼이 3개 이상 가로로 늘어선 낮은 줄
    var vw = window.innerWidth;
    var start = findFileInput();
    if (!start) return null;
    var best = null;
    for (var c = start, j = 0; c && c !== document.body && j < 6; j++, c = c.parentElement) {
      if (c.classList.contains('dcapp-docked')) break;
      var r = c.getBoundingClientRect();
      if (r.height > 90) break;
      var n = c.querySelectorAll('button, label, [role="button"]').length;
      if (r.width >= vw * 0.6 && n >= 3) best = c;
    }
    return best;
  }
  function positionTDock() {
    if (!tdock.el) return;
    var vv = window.visualViewport;
    var h = tdock.el.offsetHeight;
    var top = vv ? vv.offsetTop + vv.height - h : window.innerHeight - h;
    tdock.el.style.setProperty('top', Math.max(0, Math.round(top)) + 'px', 'important');
  }
  function tdockOn() {
    var bar = editorToolbar();
    if (!bar || tdock.el === bar) { positionTDock(); return; }
    tundock();
    var ph = document.createElement('div');
    ph.style.height = bar.getBoundingClientRect().height + 'px';
    bar.parentNode.insertBefore(ph, bar);
    var bg = getComputedStyle(document.body).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = '#fff';
    bar.classList.add('dcapp-docked');
    bar.style.setProperty('background-color', bg, 'important');
    tdock.el = bar; tdock.ph = ph;
    positionTDock();
  }
  function tundock() {
    if (!tdock.el) return;
    tdock.el.classList.remove('dcapp-docked');
    tdock.el.style.removeProperty('top');
    tdock.el.style.removeProperty('background-color');
    if (tdock.ph && tdock.ph.parentNode) tdock.ph.parentNode.removeChild(tdock.ph);
    tdock.el = null; tdock.ph = null;
  }
  document.addEventListener('focusin', function (e) {
    if (cfg.dockComment === false) return;
    if (isWriteField(e.target)) tdockOn();
  }, true);
  document.addEventListener('focusout', function () {
    setTimeout(function () {
      if (tdock.el && !isWriteField(document.activeElement)) tundock();
    }, 250);
  }, true);
  // 댓글창 바깥을 누르면 원래 자리로
  // (키보드 위 ✓ 버튼을 없앴으므로 바깥을 누르면 키보드도 내려감)
  document.addEventListener('touchstart', function (e) {
    if (dock.el && !dock.el.contains(e.target)) {
      var a = document.activeElement;
      if (a && dock.el.contains(a) && a.blur) a.blur();
      undock();
    }
  }, { capture: true, passive: true });
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', positionDock);
    window.visualViewport.addEventListener('scroll', positionDock);
  }
  window.addEventListener('scroll', positionDock, { passive: true });

  // ---------- 스와이프 뒤로가기 보조: 가로로 스크롤되는 영역(말머리 탭 등)에서 시작한 스와이프는 무시 ----------
  var lastTouchInHScroll = false;
  function inHScroll(el) {
    for (var cur = el; cur && cur !== document.documentElement; cur = cur.parentElement) {
      if (cur.nodeType !== 1) continue;
      if (cur.scrollWidth > cur.clientWidth + 2) {
        var ox = getComputedStyle(cur).overflowX;
        if (ox === 'auto' || ox === 'scroll') return true;
      }
    }
    return false;
  }
  document.addEventListener('touchstart', function (e) {
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    lastTouchInHScroll = inHScroll(t);
  }, { capture: true, passive: true });

  // ---------- 댓글 새로고침: 디시 댓글 머리글의 ⟳ 버튼을 대신 눌러줌 ----------
  function commentRefreshButton() {
    var cands = document.querySelectorAll('[class*="refresh"], [class*="reload"], [onclick*="omment"], [href*="omment"]');
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      if (!visible(c)) continue;
      var label = (clsOf(c) + ' ' + (c.id || '') + ' ' + (c.getAttribute('onclick') || '') + ' ' + (c.getAttribute('href') || '')).toLowerCase();
      var inComment = !!c.closest('[class*="comment"], [id*="comment"]');
      if (/refresh|reload/.test(label) && (inComment || /comment|cmt/.test(label))) return c;
    }
    return null;
  }
  function refreshComments() {
    var b = commentRefreshButton();
    if (!b) return 'none';
    b.click();
    var box = document.getElementById('comment_box') || b.closest('[class*="comment"]');
    if (box) box.scrollIntoView({ block: 'start', behavior: 'smooth' });
    return 'clicked';
  }
  function scrollToComments() {
    var box = document.getElementById('comment_box') || document.querySelector('[class*="comment-box"], [class*="comment_box"]');
    if (box) box.scrollIntoView({ block: 'start' });
    return !!box;
  }

  // ---------- 말머리 목록 읽기 (갤러리 목록 위의 전체/일반/공지/정보… 탭) ----------
  // 갤러리 목록 위에는 "전체/개념글/공지" 줄(목록 종류)과 "전체/자유/공식정보…" 줄(말머리)이 따로 있음.
  // 목록 종류 줄은 말머리가 아니므로 제외 (정식 갤러리는 말머리 줄이 없어서 빈 목록이 됨)
  var LIST_TABS = /^(개념글|념글|공지|추천|전체글|인기글|베스트)$/;
  function tabRows() {
    var rows = [];
    Array.prototype.forEach.call(document.querySelectorAll('ul, nav, div'), function (r) {
      var it = r.querySelectorAll('a, button');
      if (it.length < 2) it = r.children;
      if (it.length < 2 || it.length > 60) return;
      if (txt(it[0]) !== '전체') return;
      if (r.getBoundingClientRect().height > 120) return;
      rows.push({ el: r, items: Array.prototype.slice.call(it) });
    });
    return rows;
  }
  function headHref(a) {
    var h = (a.getAttribute && a.getAttribute('href')) || '';
    if (h && !/^\s*(#|javascript:)/i.test(h)) return a.href;
    // 링크 대신 onclick / data-* 에 말머리 번호가 들어 있는 경우 → 지금 주소에 headid 붙이기
    var inner = a.querySelector ? a.querySelector('a[href]') : null;
    if (inner && !/^\s*(#|javascript:)/i.test(inner.getAttribute('href') || '')) return inner.href;
    // 예: href="javascript:headText_change(10);" → 10
    var raw = h + ' ' + (a.getAttribute('onclick') || '');
    Array.prototype.forEach.call(a.attributes || [], function (x) { if (/^data-/.test(x.name)) raw += ' ' + x.value; });
    var m = raw.match(/(\d+)/);
    if (!m) return '';
    var u = new URL(location.href);
    u.searchParams.delete('page');
    u.searchParams.set('headid', m[1]);
    return u.href;
  }
  function headTabs() {
    var out = [], seen = {};
    function push(a) {
      var name = txt(a), href = headHref(a);
      if (!name || name.length > 12 || name === '전체' || LIST_TABS.test(name) || !href || seen[name]) return;
      seen[name] = 1;
      out.push({ name: name, url: href });
    }
    // 1) 말머리 번호(headid)가 들어간 링크
    var byParam = document.querySelectorAll('a[href*="headid"], a[href*="head_id"]');
    Array.prototype.forEach.call(byParam, push);
    if (out.length) return out;
    // 2) "전체"로 시작하는 짧은 탭 줄 중 목록 종류(개념글/공지) 줄이 아닌 것
    var rows = tabRows();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].items.some(function (a) { return LIST_TABS.test(txt(a)); })) continue;
      rows[i].items.slice(1).forEach(push);
      if (out.length) return out;
    }
    return out;
  }

  // ---------- 글쓰기 등록 (상단바의 등록 버튼 → 디시 등록 버튼 대신 누르기) ----------
  function submitButtons() {
    return Array.prototype.filter.call(document.querySelectorAll('button, a, input[type="button"], input[type="submit"]'), function (b) {
      if (b.closest && b.closest('.dcapp-dock-head')) return false;
      return /^\s*(등록|작성완료|완료)\s*$/.test(txt(b) || b.value || '');
    });
  }
  function submitWrite() {
    if (!isWritePage()) return 'notwrite';
    var c = submitButtons();
    if (!c.length) return 'nobutton';
    // '등록' 우선, 그중 보이는 것 우선 (사이트 상단을 숨겨서 안 보이는 버튼도 눌림)
    c.sort(function (a, b) {
      var ra = /등록/.test(txt(a) || a.value || '') ? 0 : 1, rb = /등록/.test(txt(b) || b.value || '') ? 0 : 1;
      if (ra !== rb) return ra - rb;
      return (visible(b) ? 1 : 0) - (visible(a) ? 1 : 0);
    });
    c[0].click();
    return 'clicked';
  }

  // ---------- 구조 진단 ----------
  function diagnose() {
    var out = ['script: v26-dory', 'URL: ' + location.href, 'UA: ' + navigator.userAgent];
    var units = findUnits();
    var counts = {};
    units.forEach(function (u) { counts[u.kind] = (counts[u.kind] || 0) + 1; });
    out.push('units: ' + JSON.stringify(counts));
    units.slice(0, 4).forEach(function (u) { out.push('identity[' + u.kind + ']: ' + JSON.stringify(identity(u))); });
    var dory = doryItems();
    out.push('댓글돌이(아이콘 기준): ' + dory.length + '개');
    // 아이콘 이름 확인용: 닉네임이 '댓글돌이'인 칸의 HTML (숨기지는 않음)
    var named = Array.prototype.filter.call(document.querySelectorAll('.nick, [class*="nick"], button, strong, b, span'), function (n) {
      return /^댓글\s*돌이$/.test(txt(n));
    }).map(function (n) { return n.closest('li') || n.parentElement; })[0];
    if (named) out.push('닉네임 댓글돌이 칸: ' + named.outerHTML.replace(/\s+/g, ' ').slice(0, 500));
    function snap(label, el, max) {
      out.push('--- ' + label + ' ---');
      out.push(el ? el.outerHTML.replace(/\s+/g, ' ').slice(0, max || 2000) : '(없음)');
    }
    if (isHomePage()) {
      var rt = rankTab();
      out.push('--- 홈 순위 --- tab=' + (rt ? rt.tagName + '.' + clsOf(rt) : '(못 찾음)') + ' open=' + rankIsOpen() +
               ' opened=' + homeOpened + ' tries=' + homeTries + ' rankopen_tap=' + (typeof window.rankopen_tap));
      var cl = rankToggles().filter(function (a) { return /닫기/.test(txt(a)); })[0];
      var pn = rt && cl ? commonAncestor(rt, cl) : null;
      out.push('panel: ' + (pn ? pn.tagName + '.' + clsOf(pn) + ' #' + (pn.id || '') : '(없음)'));
      out.push('toggles: ' + rankToggles().map(function (a) { return txt(a) + (isShown(a) ? '(보임)' : '(숨김)'); }).join(', '));
    }
    snap('list li', document.querySelector('ul.gall-detail-lst > li'));
    var cm = units.filter(function (u) { return u.kind === 'comment'; })[0];
    snap('comment li', cm && cm.el);
    var cul = document.querySelector('[class*="comment"]');
    snap('first [class*=comment]', cul, 1500);
    snap('article head', articleHead());
    var dc = Array.prototype.filter.call(document.querySelectorAll('img, video'), dcconKey)[0];
    snap('dccon', dc, 600);
    var fixed = [];
    document.querySelectorAll('body *').forEach(function (el) {
      if (fixed.length >= 20) return;
      var p = getComputedStyle(el).position;
      if (p === 'fixed' || p === 'sticky') fixed.push(el.tagName + '.' + clsOf(el) + ' #' + (el.id || '') + ' [' + p + '] ' + txt(el).slice(0, 60));
    });
    out.push('--- fixed/sticky ---');
    out = out.concat(fixed);
    var rb = commentRefreshButton();
    out.push('--- comment refresh --- ' + (rb ? rb.tagName + '.' + clsOf(rb) + ' onclick=' + (rb.getAttribute('onclick') || '') : '(못 찾음)'));
    out.push('--- 알림 관련 요청 (최근) ---');
    var net = window.__dcappNet || [];
    if (!net.length) out.push('(아직 없음 — 로그인 상태에서 알림 종을 누르거나 잠시 기다린 뒤 다시 진단해주세요)');
    net.slice(-15).forEach(function (n) {
      out.push('[' + n.t + '] ' + n.kind + ' ' + n.method + ' ' + n.status + ' ' + n.url);
      if (n.body) out.push('    → ' + n.body);
    });
    if (isLoginPage() || pwNagButton()) {
      out.push('--- 로그인/비번 페이지 --- ' + txt(document.body).slice(0, 300));
      out.push('buttons: ' + Array.prototype.filter.call(document.querySelectorAll('button, a, input[type="button"], input[type="submit"], [role="button"]'), visible)
        .map(function (b) { return (txt(b) || b.value || '').slice(0, 20) + '(' + b.tagName + '.' + clsOf(b) + ')'; }).slice(0, 30).join(' , '));
      out.push('skip 후보: ' + pwSkipButtons().map(function (b) { return txt(b) || b.value; }).join(' / ') +
               ' → 누를 것: ' + (pwNagButton() ? txt(pwNagButton()) : '(없음)'));
    }
    out.push('--- 알림 관련 링크/요소 ---');
    Array.prototype.slice.call(document.querySelectorAll('a[href*="alarm"], a[href*="noti"], [class*="alarm"], [class*="bell"], [onclick*="alarm"], [onclick*="noti"]'), 0, 12).forEach(function (el) {
      out.push(el.tagName + '.' + clsOf(el) + ' #' + (el.id || '') + ' href=' + (el.getAttribute('href') || '') +
               ' onclick=' + (el.getAttribute('onclick') || '').slice(0, 80) + ' : ' + txt(el).slice(0, 40));
    });
    out.push('--- 말머리 --- ' + JSON.stringify(headTabs()).slice(0, 3000));
    if (typeof window.headText_change === 'function') {
      out.push('headText_change: ' + String(window.headText_change).replace(/\s+/g, ' ').slice(0, 600));
    }
    tabRows().slice(0, 6).forEach(function (r) {
      // 첫 칸은 HTML 그대로, 나머지는 이름 → 주소/onclick 만 짧게 (전부 표시)
      out.push('row ' + r.el.tagName + '.' + clsOf(r.el) + ' (' + r.items.length + '): ' +
               r.items[0].outerHTML.replace(/\s+/g, ' ').slice(0, 200));
      out.push('   items: ' + r.items.map(function (x) {
        return txt(x) + '→' + ((x.getAttribute && x.getAttribute('href')) || '') + (x.getAttribute && x.getAttribute('onclick') ? ' {' + x.getAttribute('onclick').slice(0, 60) + '}' : '');
      }).join(' , '));
    });
    if (isWritePage()) {
      out.push('--- 등록 버튼 --- ' + submitButtons().map(function (b) {
        return b.tagName + '.' + clsOf(b) + ' "' + (txt(b) || b.value || '') + '" vis=' + visible(b);
      }).join(' / '));
    }
    out.push('--- dccon layers ---');
    Array.prototype.slice.call(document.querySelectorAll('[class*="dccon"], [id*="dccon"]'), 0, 12).forEach(function (el) {
      var r = el.getBoundingClientRect();
      out.push(el.tagName + '.' + clsOf(el) + ' #' + (el.id || '') + ' [' + getComputedStyle(el).position + ' z=' + getComputedStyle(el).zIndex + '] ' +
               Math.round(r.width) + 'x' + Math.round(r.height) + ' vis=' + visible(el));
    });
    var ct = document.querySelector('textarea');
    out.push('--- comment ---');
    out.push('first textarea: ' + (ct ? ct.outerHTML.slice(0, 200) + ' isComment=' + isCommentField(ct) : '(없음)'));
    if (ct && isCommentField(ct)) { var cc = commentContainer(ct); out.push('container: ' + cc.tagName + '.' + clsOf(cc) + ' #' + (cc.id || '')); }
    var wf = writeFields();
    out.push('--- write fields ---');
    out.push('title: ' + (wf.title ? wf.title.outerHTML.slice(0, 200) : '(없음)'));
    out.push('body: ' + (wf.body ? wf.body.tagName + '.' + clsOf(wf.body) + ' html=' + wf.html : '(없음)'));
    out.push('iframes: ' + document.querySelectorAll('iframe').length + ', textareas: ' + document.querySelectorAll('textarea').length);
    var files = document.querySelectorAll('input[type="file"]');
    if (files.length) {
      out.push('--- file inputs ---');
      Array.prototype.forEach.call(files, function (i) {
        out.push('name=' + i.name + ' id=' + i.id + ' accept=' + i.getAttribute('accept') + ' multiple=' + i.multiple + ' class=' + clsOf(i) + ' parent=' + (i.parentElement ? i.parentElement.tagName + '.' + clsOf(i.parentElement) : ''));
      });
    }
    var f = loginFields();
    if (f) {
      out.push('--- login ---');
      Array.prototype.forEach.call((f.form || document).querySelectorAll('input, button'), function (i) {
        out.push(i.tagName + ' type=' + i.type + ' name=' + i.name + ' id=' + i.id);
      });
    }
    return out.join('\n');
  }

  // ---------- 변화 감지 ----------
  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () { scheduled = false; try { apply(); } catch (e) {} }, 80);
  }
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });

  window.__dcapp = {
    setConfig: function (c) { cfg = c || {}; apply(); return true; },
    setPickMode: function (on) { pick.on = !!on; clearPick(); return true; },
    setBlockPickMode: function (on) {
      blockPick = !!on;
      document.documentElement.classList.toggle('dcapp-blockmode', blockPick);
      if (blockPick) findUnits();
      return true;
    },
    articleAuthor: function () {
      findUnits();
      var h = articleHead();
      return h ? describe(h, null) : null;
    },
    pickParent: function () {
      if (pick.el && pick.el.parentElement) choose(pick.el.parentElement, 400);
      return true;
    },
    clearPick: function () { clearPick(); return true; },
    fillLogin: fillLogin,
    attachImage: attachImage,
    getDraft: getDraft,
    setDraft: setDraft,
    startAutosave: startAutosave,
    undock: function () { undock(); return true; },
    lastTouchInHScroll: function () { return lastTouchInHScroll; },
    refreshComments: refreshComments,
    headTabs: headTabs,
    submitWrite: submitWrite,
    scrollToComments: scrollToComments,
    prepareCapture: prepareCapture,
    diagnose: diagnose,
    _identity: function (el) { return identity({ el: el, kind: el.getAttribute('data-dcapp-unit') }); }
  };
  try { apply(); } catch (e) {}
})();
"""#

    /// 페이지 맨 처음(문서 시작)에 넣는 네트워크 기록 스크립트 — 알림 주소를 찾기 위한 진단용
    static let netLog = #"""
// DCApp 네트워크 기록 — 페이지가 몰래 불러오는 주소 중 알림 관련(alarm/noti/push/alim/bell/memo) 것만 기록
(function () {
  if (window.__dcappNet) return;
  var log = window.__dcappNet = [];
  var RE = /alarm|noti|push|alim|bell|memo|recv|message/i;
  function add(kind, method, url, status, body) {
    try {
      if (!RE.test(String(url))) return;
      log.push({ t: new Date().toISOString().slice(11, 19), kind: kind, method: method, url: String(url).slice(0, 300),
                 status: status, body: String(body || '').replace(/\s+/g, ' ').slice(0, 400) });
      if (log.length > 30) log.shift();
    } catch (e) {}
  }
  var XO = XMLHttpRequest.prototype.open, XS = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (m, u) { this.__dcapp = { m: m, u: u, h: '' }; return XO.apply(this, arguments); };
  var XH = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function (k, v) {   // 알림 요청에 붙는 헤더(csrf 등)도 기록
    try { if (this.__dcapp) this.__dcapp.h += ' ' + k + '=' + String(v).slice(0, 24); } catch (e) {}
    return XH.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (b) {
    var x = this, info = x.__dcapp || {};
    var reqBody = typeof b === 'string' ? b : '';
    x.addEventListener('loadend', function () {
      var text = '';
      try { text = (x.responseType === '' || x.responseType === 'text') ? x.responseText : '[' + x.responseType + ']'; } catch (e) {}
      add('xhr', info.m, info.u + (reqBody ? '  <BODY ' + reqBody.slice(0, 200) + '>' : '') + (info.h ? '  <H' + info.h + '>' : ''), x.status, text);
    });
    return XS.apply(this, arguments);
  };
  if (window.fetch) {
    var F = window.fetch;
    window.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var method = (init && init.method) || 'GET';
      return F.apply(this, arguments).then(function (res) {
        try { res.clone().text().then(function (t) { add('fetch', method, url, res.status, t); }); } catch (e) {}
        return res;
      });
    };
  }
  if (window.EventSource) {
    var ES = window.EventSource;
    window.EventSource = function (u, c) { add('sse', 'GET', u, 0, ''); return new ES(u, c); };
  }
  if (window.WebSocket) {
    var WS = window.WebSocket;
    window.WebSocket = function (u, p) {
      // 웹소켓은 주소와 상관없이 모두 기록 (실시간 알림에 쓰일 수 있음)
      log.push({ t: new Date().toISOString().slice(11, 19), kind: 'ws', method: 'WS', url: String(u).slice(0, 300), status: 0, body: '' });
      return p ? new WS(u, p) : new WS(u);
    };
  }
})();
"""#
}
