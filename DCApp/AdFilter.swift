import Foundation

/// 광고 차단: 애드가드 갤러리 필터(github.com/hooray804/adguard-gallery-filter)의 디시 관련 규칙을 옮긴 것
/// (도메인 차단은 애드가드 DNS 보호가 맡고, 여기서는 화면에 남는 광고·팝업을 가림)
/// 필터가 업데이트되면 아래 hide 목록만 고치면 됨
extension ContentScript {
    static let adFilter = #"""
(function () {
  if (window.__dcappAd) return;
  window.__dcappAd = 1;
  var host = location.hostname;
  if (!/(^|\.)dcinside\.com$/.test(host)) return;
  var isM = host === 'm.dcinside.com';

  var hide = [
    // 공통 규칙 (General rules)
    '.ad-view', '.ad400__100', '.banner_m', '.happy-under-player-mobile', "[alt$='광고']",
    "[class*='ad'][id^='AD']:not([class*='add']):not([id^='ADD'])", "[class^='basic-banner'][id]",
    "[class^='happy-header']", "[id^='hd_pop']", 'iframe[src*="//ad.adnmore.co.kr"]',
    "[target='_blank']:has([src*='/banner/']):not([title^='새']):not([class*='slide'] > *)",
    // dcinside.com
    "li:has(> [href*='https://ads.dcinside.com/'])"
  ];
  if (isM) hide.push(
    // m.dcinside.com
    '.layer-bottom-popup', '.survey', '.view-btm-con', 'li:not(.notice):has(> .detail-top-lnk)',
    '#light_tipbox', '.alarm-popup.roundtype.silbe-alarm', '.outside-search-box',
    'section.grid > .md-tit-box:has(> div > .daumtxt)', '#moveOverlay'
  );
  // 규칙마다 따로 써서 하나가 잘못돼도 나머지는 적용되게
  var css = hide.map(function (s) { return s + '{display:none!important}'; }).join('\n') +
    '\n.imgwrap > .num{opacity:.6!important}' +
    (isM ? '\nbutton.btn-imgcomment{transform:scale(.7) translate(21.5px,15.3px)!important;opacity:.6!important}' : '');

  function addStyle() {
    var root = document.head || document.documentElement;
    if (!root || document.getElementById('dcapp-adfilter')) return;
    var st = document.createElement('style');
    st.id = 'dcapp-adfilter';
    st.textContent = css;
    root.appendChild(st);
  }
  addStyle();

  // 사진을 원본 크기로 보기 (trusted-set-local-storage-item imgSizeSetting = ori)
  if (isM) { try { localStorage.setItem('imgSizeSetting', 'ori'); } catch (e) {} }

  function t(el) { return el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
  var SPAM = /^(https?:\/\/)[A-Za-z0-9]{2,10}(\.[a-z]{2,7}|\.co\.kr)(\/(?=.*[a-z])(?=.*[0-9])[A-Za-z0-9_]{5,9})$/;
  var SPAM_OK = /git|g2sh|img|tebin|sendanywhe|twitter|rentry|x\.com|youtu|ibb\.co|archive\.md|t\.me|streamable|dev/i;

  function run() {
    addStyle();
    if (document.body) document.body.classList.remove('topBanner--on');   // remove-class topBanner--on
    // 단축 주소만 달린 홍보 댓글은 흐리게
    document.querySelectorAll("li[id^='comment_']").forEach(function (li) {
      var ps = li.querySelectorAll("p[class*='txt']");
      for (var i = 0; i < ps.length; i++) {
        var s = t(ps[i]);
        if (SPAM.test(s) && !SPAM_OK.test(s)) { li.style.setProperty('opacity', '0.5', 'important'); break; }
      }
    });
    if (!isM) return;
    // 글 정보에 작성 환경 표시 (APP / MOBILE / PC)
    document.querySelectorAll('section.grid > .gallview-tit-box > div > ul.ginfo2:not([data-dcapp-dev])').forEach(function (ul) {
      var box = ul.parentElement && ul.parentElement.parentElement;
      if (!box) return;
      ul.setAttribute('data-dcapp-dev', '1');
      var label = box.querySelector('span.sp-app') ? 'APP'
        : box.querySelector('span.sp-mweb') ? 'MOBILE'
        : !box.querySelector('span.sp-icon') ? 'PC' : '';
      if (label) { var li = document.createElement('li'); li.textContent = label; ul.appendChild(li); }
    });
    // 동영상 다운로드 버튼
    document.querySelectorAll('.video-info-area .info-sub .rt').forEach(function (rt) {
      if (rt.querySelector('.sp-download')) return;
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'sp-download';
      b.textContent = '다운';
      b.addEventListener('click', function () {
        var so = document.querySelector('#video_tag source');
        if (so && typeof window.movieDown === 'function') window.movieDown(so.src);
      });
      rt.appendChild(b);
    });
  }

  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () { scheduled = false; try { run(); } catch (e) {} }, 120);
  }
  new MutationObserver(function () { addStyle(); schedule(); }).observe(document, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', schedule);
})();
"""#
}
