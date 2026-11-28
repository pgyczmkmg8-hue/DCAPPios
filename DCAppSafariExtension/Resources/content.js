(function () {
  if (window.top !== window.self) return;
  var href = location.href || '';
  if (!/^https?:\/\/([^\/]+\.)?dcinside\.com(\/|$)/i.test(href)) return;
  // 로그인·인증 페이지는 자동 전환하지 않음
  if (/^https?:\/\/(sign|msign)\.dcinside\.com\b/i.test(href)) return;

  var appURL = 'dcappios://open?url=' + encodeURIComponent(href);

  // 같은 탭·같은 URL에서 무한 반복 방지
  var key = 'dcapp_safari_redirected';
  var already = false;
  try {
    already = sessionStorage.getItem(key) === href;
    if (!already) sessionStorage.setItem(key, href);
  } catch (e) {}

  if (!already) {
    try {
      location.href = appURL;
    } catch (e) {}
  }

  // Safari가 자동 전환을 막거나 사용자가 취소를 누른 경우를 대비한 상단 플로팅 버튼
  function mountOpenBanner() {
    if (document.getElementById('dcapp-safari-open-btn')) return;
    var root = document.body || document.documentElement;
    if (!root) return;

    var bar = document.createElement('div');
    bar.id = 'dcapp-safari-open-btn';
    bar.style.cssText = [
      'position:fixed',
      'top:calc(env(safe-area-inset-top, 0px) + 10px)',
      'right:12px',
      'z-index:2147483647',
      'display:flex',
      'align-items:center',
      'gap:6px',
      'padding:8px 14px',
      'border-radius:999px',
      'background:#3b4890',
      'color:#fff',
      'font-family:-apple-system,BlinkMacSystemFont,sans-serif',
      'font-size:13px',
      'font-weight:700',
      'box-shadow:0 4px 16px rgba(0,0,0,.25)',
      'cursor:pointer',
      'user-select:none'
    ].join('!important;') + '!important;';

    var link = document.createElement('a');
    link.href = appURL;
    link.textContent = 'DCApp에서 열기';
    link.style.cssText = 'color:#fff!important;text-decoration:none!important;';

    var closeBtn = document.createElement('span');
    closeBtn.textContent = '×';
    closeBtn.style.cssText = 'margin-left:4px;font-size:16px;line-height:1;opacity:.8;padding:0 2px;';
    closeBtn.addEventListener('click', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      if (bar.parentNode) bar.parentNode.removeChild(bar);
    });

    bar.appendChild(link);
    bar.appendChild(closeBtn);
    root.appendChild(bar);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mountOpenBanner, { once: true });
  } else {
    mountOpenBanner();
  }
})();
