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
      // 사이트 자체의 우측 하단 버튼 묶음(댓글 바로가기 등) — 앱의 새로고침 버튼으로 대신함
      '.fab-wrap{display:none!important}',
      // 글 아래 목록보기·글쓰기·수정·삭제 버튼 줄 — 앱 컨트롤바/수정·삭제 버튼으로 대신함 (수정·삭제는 숨긴 채로 앱이 대신 누름)
      '#view_btn_area{display:none!important}',
      // 글 화면 맨 아래: 사진(실베·개념·디시미디어·디시이슈 탭) · 다음 검색 · 푸터
      'section.grid:has(.view-btm-con),section.grid:has(.outside-search-box),body:has(.view-btm-con) .footer,body:has(.view-btm-con) .adv-group{display:none!important}',
      '.dcapp-pinned-off{display:none!important}',
      // 다크모드 배경 살짝 밝게 (디시 야간 모드는 거의 검정이라 너무 어두움)
      'html.darkmode,.darkmode body,.darkmode .header,.darkmode .grid,.darkmode .sec-wrap .grid,.darkmode .sec-wrap-sub .grid,.darkmode .all-comment-lst .comment,.darkmode .all-comment-lst .comment-full,.darkmode .all-comment,.darkmode .gall-lst,.darkmode .main-gall-lst,.darkmode .lg-tit-box,.darkmode .sel-box,.darkmode .paging.alg-full .prev,.darkmode .paging.alg-full .next,.darkmode .comment-write .ipt,.darkmode .comment-write .btm-wrt-btns,.darkmode .con-search-box .con-search-inner,.darkmode .wrt-tit-box,.darkmode .wrt-form-box,.darkmode .wrt-form-box .ipt,.darkmode .dccon-lywrap,.darkmode .power-lst,.darkmode .pp-box,.darkmode .con-tit-box,.darkmode .sub-tit-box,.darkmode .onemore,.darkmode .update-re{background-color:#272729!important}',
      '.darkmode .comment-write .comment-caption,.darkmode .comment-write .who-txt,.darkmode .comment-write-btm,.darkmode .gall-detail-lst li .rt,.darkmode .btm-btns-both,.darkmode .con-search-box,.darkmode .pwd-box .ipt,.darkmode .search-wrap.bg,.darkmode .dccon-lywrap .btm-area{background-color:#2d2d30!important}',
      '.darkmode .lg-tit-box.paging,.darkmode .tab-basic .tab-lst,.darkmode .tab-basic .tab-lst .sel,.darkmode .md-tit-box,.darkmode .power-tit,.darkmode .tab-lst .sel-box,.darkmode .con-child-tit,.darkmode .gall-lst-group .livebest-tab{background-color:#333336!important}',
      '.darkmode .search-wrap2 .search-box .fld-sch,.darkmode .adv-group,.darkmode .view-btm-more .lnk,.darkmode .btn-line-gray{background-color:#3d3d41!important}',
      '.ginfo-ly{display:none!important}',
      // 디시 웹 알림 배너(새글·실베 등) — 앱 알림이 대신함
      '.alarm-popup{display:none!important}',
      // 앱 말머리 탭
      '#dcapp-headbar{display:flex;gap:0;overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:none;padding:0 6px;margin:0;width:auto;background:#fff;border-bottom:1px solid rgb(223,225,238)}',
      '#dcapp-headbar::-webkit-scrollbar{display:none}',
      'html.darkmode #dcapp-headbar{background:#272729;border-bottom-color:#3d3d41}',
      'html.darkmode #dcapp-headbar button{color:#ddd}',
      'html.darkmode #dcapp-headbar button.on{color:#a9b4f0;border-bottom-color:#a9b4f0}',
      // 말머리 탭: 공식 앱처럼 글자 탭 + 고른 탭 밑줄
      '#dcapp-headbar button{flex:0 0 auto;border:0;margin:0;padding:13px 14px 10px;border-radius:0;font-size:14px;line-height:1.2;font-weight:400;color:#222;background:transparent;border-bottom:3px solid transparent;-webkit-appearance:none}',
      '#dcapp-headbar button.on{color:#3b4890;font-weight:600;border-bottom-color:#3b4890}',
      // 글 목록 한 줄: 글자 글 아이콘은 빼고(사진 글만 아이콘), 정보 줄은 닉네임·조회·추천 → 오른쪽 끝에 말머리·시간
      'ul.gall-detail-lst > li .sp-lst-txt{display:none!important}',
      'ul.gall-detail-lst > li.dcapp-filtered{display:none!important}',
      // 글자 글은 아이콘 자리(왼쪽 여백)도 없애고, 맨 끝으로 옮긴 시간 뒤의 구분선은 숨김
      'ul.gall-detail-lst > li:has(.sp-lst-txt) .subject-add{padding-left:0!important}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-time::after, ul.gall-detail-lst > li ul.ginfo > li.dcapp-time::before{display:none!important}',
      'ul.gall-detail-lst > li ul.ginfo{display:flex!important;flex-wrap:nowrap!important;align-items:center}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-head{order:9;margin-left:auto}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-time{order:10}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-time:not(.dcapp-after-head){margin-left:auto}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-head-default{display:none!important}',
      '.dcapp-cmt{margin-left:.3em;color:rgb(41,121,255)!important;font-weight:600;white-space:nowrap}',
      // 오른쪽 댓글 칸을 없앤 자리까지 제목이 쓰도록
      '.gall-detail-lnk:has(> .rt.dcapp-hide) > .lt{width:100%!important;max-width:none!important;padding-right:0!important;margin-right:0!important}',
      'li.dcapp-read a.lt .subjectin, li.dcapp-read a.lt .subject-add, li.dcapp-read a.lt .detail-txt{color:#6d459e!important}',
      '.dcapp-collapsed{position:relative!important;height:30px!important;min-height:0!important;max-height:30px!important;overflow:hidden!important;padding-top:0!important;padding-bottom:0!important}',
      '.dcapp-collapsed>*{visibility:hidden!important}',
      // 안내 문구는 회색 칸 한가운데 (가로·세로 가운데 정렬)
      '.dcapp-collapsed::after{content:attr(data-dcapp-label);visibility:visible;position:absolute;left:0;right:0;top:0;bottom:0;display:flex;align-items:center;justify-content:center;text-align:center;line-height:1.2;padding:0 12px;font-size:12px;color:#8e8e93;background:rgba(142,142,147,.12);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
      '.dcapp-dccon-label{display:inline-flex;align-items:center;justify-content:center;min-width:90px;height:30px;padding:0 10px;font-size:12px;color:#8e8e93;background:rgba(142,142,147,.12);border-radius:6px;vertical-align:middle}',
      '.dcapp-dccon-off{display:none!important}',
      '.dcapp-home-off{display:none!important}',
      'html.dcapp-home-wait body{opacity:0!important}',
      '.dcapp-blockmode [data-dcapp-unit]{outline:1px dashed rgba(255,59,48,.6)!important;outline-offset:-1px!important}',
      '.dcapp-pick{outline:3px solid #ff3b30!important;outline-offset:-3px!important;background-color:rgba(255,59,48,.15)!important}',
      // 닉네임·디시콘만 길게 누르기 메뉴를 쓰므로 iOS 기본 메뉴(복사 등)를 막고, 나머지 글자는 평소처럼 선택·복사 가능
      '.dcapp-lp-nick,.dcapp-memo,img[src*="dccon"],img[data-original*="dccon"]{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none}',
      '[data-dcapp-unit="post"]{-webkit-user-select:none;user-select:none}',
      '.dcapp-dory{display:none!important}',
      // 메모: 상자 없이 글자만 (닉네임 뒤에 주황 글씨)
      '.dcapp-memo{display:inline;margin:0 8px 0 4px;padding:0;background:none;border-radius:0;font-size:12px;color:#c56a00;font-weight:normal;white-space:nowrap}',
      'html.darkmode .dcapp-memo{color:#ffaa45}',
      // 글 제목 블록: 폴더(스크랩)·갤로그 가기 숨김, 닉네임 아래 한 줄에 조회수|추천|작성일, 오른쪽에 댓글 수 칸
      '.gallview-tit-box .btm{display:flex!important;align-items:center;justify-content:space-between}',
      '.gallview-tit-box .btm ul.ginfo2{float:none!important;flex:1;min-width:0}',
      '.gallview-tit-box .btm ul.ginfo2>li{display:block!important;float:none!important}',
      '.gallview-tit-box .btm ul.ginfo2>li.dcapp-datehide{display:none!important}',
      '.gallview-tit-box .btm .rt{float:none!important;position:static!important;margin:0 0 0 10px;flex:none}',
      '.gallview-tit-box .btm .rt>*:not(.dcapp-cmtbox){display:none!important}',
      '.gallview-tit-box .btm .rt>.dcapp-titicon{display:inline-block!important;margin-right:6px;vertical-align:middle}',
      '.gall-thum-btm-inner>ul.ginfo2{display:none!important}',
      '.dcapp-meta{margin-top:14px;font-size:13px;color:#777;font-weight:normal}',
      '.dcapp-meta i{display:inline-block;width:1px;height:10px;margin:0 8px;background:#ccc;vertical-align:-1px}',
      '.dcapp-cmtbox{display:inline-flex;align-items:center;gap:4px;height:24px;padding:0 9px;border:1px solid #c9c9cf;border-radius:4px;background:transparent;color:#3b4890;font-size:11px;font-weight:600}',
      '.dcapp-cmtbox svg{width:11px;height:11px}',
      'html.darkmode .dcapp-meta{color:#a5a5ab}',
      'html.darkmode .dcapp-meta i{background:#55565c}',
      'html.darkmode .dcapp-cmtbox{border-color:#55565c;color:#9db0ff}',
      // 개념/비추 버튼: 네모 칸(아이콘 칸 | 숫자) + 실베추·펌·신고는 아이콘만
      // 글 본문 가독성: 제목·본문 글씨를 키우고 줄 간격을 넓히고, 사진은 가로 폭에 맞춤 (공식앱처럼)
      '.gallview-tit-box .tit{font-size:18px!important;line-height:1.4!important;font-weight:400!important}',
      '.gallview-tit-box .btm{margin-top:8px!important}',
      '.thum-txtin{font-size:16px!important;line-height:1.7!important;word-break:keep-all}',
      'li.comment .txt{font-size:14px!important}',
      '.thum-txtin img{max-width:100%!important;height:auto!important}',
      '.gall-thum-btm{padding-top:14px!important}',
      // 댓글 입력 칸: 한 줄에서 시작해 줄이 늘면 같이 커지고, 10줄을 넘으면 스크롤 (높이는 fitCommentBox가 맞춤)
      '#comment_memo.comment-caption{min-height:44px!important;resize:none!important;white-space:pre-wrap!important;padding:12px 16px!important;box-sizing:border-box!important;line-height:20px!important}',
      // 댓글 헤더: 새로고침·본문·정렬 드롭다운은 숨기고, 등록순/최신순/답글순 체크 버튼으로 대신함
      '.all-comment-tit .sp-reload{display:none!important}',
      '.all-comment-tit .rt>*:not(.dcapp-sort){display:none!important}',
      '.dcapp-sort{display:flex;align-items:center;gap:15px}',
      '.dcapp-sort button{display:inline-flex;align-items:center;gap:3px;border:0;background:none;padding:6px 0;font-size:16px;color:#8a8a90}',
      '.dcapp-sort button.on{color:#222;font-weight:600}',
      '.dcapp-sort svg{width:24px;height:24px;flex:none;color:#b5b5bb}',
      '.dcapp-sort button.on svg{color:#3b4890}',
      'html.darkmode .dcapp-sort button{color:#a5a5ab}',
      'html.darkmode .dcapp-sort button.on{color:#eee}',
      'html.darkmode .dcapp-sort button.on svg{color:#9db0ff}',
      '.reco-area{display:none!important}',
      '.dcapp-vote{display:flex;align-items:center;justify-content:center;flex-wrap:nowrap;gap:5px;margin:10px 0 6px}',
      '.dcapp-vbox{display:flex;align-items:stretch;height:28px;border:1px solid #c9c9cf;border-radius:5px;overflow:hidden;flex:none}',
      '.dcapp-vcell{width:28px;flex:none;border:0;border-right:1px solid #c9c9cf;background:#ececf0;color:#3b4890;display:flex;align-items:center;justify-content:center;padding:0}',
      '.dcapp-vbox.down .dcapp-vcell{color:#8a8a90}',
      '.dcapp-vcell svg{width:16px;height:16px}',
      '.dcapp-vcell.on{background:#3b4890;color:#ffd54a}',
      '.dcapp-vcell.on svg path{fill:#ffd54a}',
      '.dcapp-vnum{display:flex;align-items:center;justify-content:center;text-align:center;white-space:nowrap;min-width:30px;padding:0 6px;font-size:13px;line-height:1;color:#3b4890}',
      '.dcapp-vbox.down .dcapp-vnum{color:#8a8a90}',
      '.dcapp-vmem{display:flex;align-items:center;justify-content:center;white-space:nowrap;gap:3px;padding:0 6px 0 0;font-size:13px;line-height:1;color:#3b4890}',
      '.dcapp-vmem::before{content:"";width:1px;height:12px;background:#d8d8dd;margin-right:6px}',
      '.dcapp-vmem svg{width:12px;height:12px;flex:none}',
      '.dcapp-vmem b{font-weight:normal}',
      '.dcapp-vicons{display:flex;gap:0;margin-left:0;flex:none}',
      '.dcapp-vicons button{width:26px;height:28px;border:0;background:none;display:flex;align-items:center;justify-content:center;color:#7d7d84;padding:0}',
      '.dcapp-vicons svg{width:18px;height:18px}',
      'html.darkmode .dcapp-vbox{border-color:#55565c}',
      'html.darkmode .dcapp-vcell{background:#3d3d41;border-right-color:#55565c;color:#9db0ff}',
      'html.darkmode .dcapp-vbox.down .dcapp-vcell{color:#a5a5ab}',
      'html.darkmode .dcapp-vcell.on{background:#3b4890;color:#ffd54a}',
      'html.darkmode .dcapp-vnum,html.darkmode .dcapp-vmem{color:#9db0ff}',
      'html.darkmode .dcapp-vbox.down .dcapp-vnum{color:#a5a5ab}',
      'html.darkmode .dcapp-vmem::before{background:#55565c}',
      'html.darkmode .dcapp-vicons button{color:#a5a5ab}',
      // 내 글·댓글: 닉네임 글자 둘레를 어두운 하늘색 상자로 칠함(흰 글자), 디시가 내 댓글에 칠하는 파란 배경은 지움
      // 닉네임 글자만 감싼 span에 칠해서 글씨 크기에 딱 맞게 (버튼·칸 여백까지 칠하지 않도록)
      // 연한 하늘색 상자에 글자가 위아래 가운데 오도록 (inline-flex로 상자 높이를 글자에 맞춤)
      'html.darkmode .dcapp-mine-name{background:rgb(52,78,112)!important;color:#e8eefc!important}',
      '.dcapp-mine-name{display:inline-flex!important;align-items:center!important;height:1.45em!important;padding:0 4px!important;vertical-align:middle!important;background:rgb(207,230,255)!important;color:#111!important;border-radius:3px!important;line-height:1!important;box-sizing:border-box!important}',
      // 디시는 내 댓글 li에 'on' 클래스를 붙여 파랗게 칠함 → 디시 쪽 규칙보다 우선하도록 클래스를 겹쳐 씀
      'li.comment.on.dcapp-mine.dcapp-mine.dcapp-mine>*{background:none!important;background-color:transparent!important;box-shadow:none!important}',
      'li.comment.on.dcapp-mine.dcapp-mine.dcapp-mine::before,li.comment.on.dcapp-mine.dcapp-mine.dcapp-mine::after{background:none!important;box-shadow:none!important}',
      // 글 목록 페이지 이동 (디시 페이지 번호 대신 앱이 만든 큰 버튼)
      // 아래 여백: 맨 끝까지 내려도 앱의 떠 있는 버튼(새로고침 등)에 가리지 않게
      '#dcapp-pager{display:flex;flex-direction:column;gap:8px;padding:14px 12px 84px;box-sizing:border-box}',
      '#dcapp-pager .dcapp-pg-row{display:flex;gap:6px;justify-content:center}',
      '#dcapp-pager a{flex:1 1 0;max-width:58px;height:44px;display:flex;align-items:center;justify-content:center;border-radius:10px;background:rgba(127,127,127,.12);color:#222;font-size:17px;font-weight:500;text-decoration:none;-webkit-tap-highlight-color:transparent}',
      '#dcapp-pager a:active{background:rgba(127,127,127,.28)}',
      '#dcapp-pager a.on{background:#3b4890;color:#fff;font-weight:700}',
      '#dcapp-pager a.dcapp-pg-arw{font-size:24px;font-weight:600;line-height:1}',
      '#dcapp-pager a.off{opacity:.3;pointer-events:none}',
      '#dcapp-pager .dcapp-pg-sub a{max-width:none;height:38px;font-size:14px}',
      'html.darkmode #dcapp-pager a{color:#ddd;background:rgba(255,255,255,.1)}',
      'html.darkmode #dcapp-pager a.on{background:#5a6bc4;color:#fff}',
      '.dcapp-dock-head{display:flex!important;align-items:center!important;justify-content:space-between!important;height:44px!important;padding:0 6px 0 16px!important;border-bottom:1px solid rgba(127,127,127,.18)!important;font-size:15px!important;color:#888!important}',
      '.dcapp-dock-close{width:44px!important;height:44px!important;font-size:22px!important;line-height:44px!important;color:#888!important;background:none!important;border:0!important;padding:0!important}',
      '.dcapp-docked .all-comment-tit{display:none!important}',
      '.dcapp-docked{position:fixed!important;left:0!important;right:0!important;bottom:auto!important;width:auto!important;max-width:none!important;margin:0!important;z-index:2147483000!important;max-height:60vh!important;overflow-y:auto!important;box-shadow:0 -4px 14px rgba(0,0,0,.14)!important;box-sizing:border-box!important;transform:none!important}'
    ];
    (cfg.selectors || []).forEach(function (s) {
      if (s && validSel(s)) rules.push(s + '{display:none!important}');
    });
    var fs = cfg.fontSizes || {};
    if (fs.title) rules.push('.gallview-tit-box .tit{font-size:' + fs.title + 'px!important}');
    if (fs.body) rules.push('.thum-txtin{font-size:' + fs.body + 'px!important}');
    if (fs.cmt) rules.push('li.comment .txt{font-size:' + fs.cmt + 'px!important}');
    if (fs.list) rules.push('.gall-detail-lst .subjectin{font-size:' + fs.list + 'px!important}');
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
  // ---------- 읽은 글: 앱이 기억한 글은 목록에서 보라색 (웹뷰 방문 기록이 지워져도 유지) ----------
  var readSet = null;
  function postKeyOf(href) {
    var m = String(href || '').match(/\/(board|mini|person)\/([^\/?#]+)\/(\d+)/);
    if (!m) return null;
    var g = m[2].replace(/^(mi|pr)\$/, '');
    return (m[1] === 'mini' ? 'mi$' : (m[1] === 'person' ? 'pr$' : '')) + g + '/' + m[3];
  }
  function markReadRows() {
    if (!readSet) return;
    document.querySelectorAll('ul.gall-detail-lst > li').forEach(function (li) {
      var a = li.querySelector('a.lt, a[href]');
      var k = a && postKeyOf(a.getAttribute('href'));
      li.classList.toggle('dcapp-read', !!(k && readSet.has(k)));
    });
  }
  /// 글 목록 정보 줄 칸 나누기 (자리는 CSS order로만 옮김 — 칸 순서는 그대로라 차단·메모 판정에 영향 없음)
  function listRowLayout() {
    document.querySelectorAll('ul.gall-detail-lst > li ul.ginfo').forEach(function (g) {
      if (g.getAttribute('data-dcapp-layout') === '1') return;
      var lis = Array.prototype.filter.call(g.children, function (c) { return c.tagName === 'LI'; });
      if (lis.length < 4) return;
      var hasHead = lis.length >= 5;
      var time = lis[hasHead ? 2 : 1];
      if (time && /^\s*[\d.:\-\/]+\s*$/.test(txt(time))) time.classList.add('dcapp-time');
      if (hasHead) {
        var head = lis[0];
        head.classList.add('dcapp-head');
        if (/^\s*일반\s*$/.test(txt(head))) head.classList.add('dcapp-head-default');   // 기본 말머리는 숨김
        else if (time) time.classList.add('dcapp-after-head');
      }
      g.setAttribute('data-dcapp-layout', '1');
    });
  }
  // ---------- 게시물 필터 (앱 상단바 깔때기): 읽음 여부·추천·댓글·조회 수 ----------
  var listFilter = null;
  function numIn(li, label) {
    var n = -1;
    li.querySelectorAll('ul.ginfo > li').forEach(function (x) {
      var m = txt(x).match(new RegExp(label + '\\s*([\\d,]+)'));
      if (m) n = parseInt(m[1].replace(/,/g, ''), 10);
    });
    return n;
  }
  function applyListFilter() {
    document.querySelectorAll('ul.gall-detail-lst > li').forEach(function (li) {
      var hide = false;
      if (listFilter && li.querySelector('ul.ginfo')) {
        var f = listFilter;
        var a = li.querySelector('a.lt, a[href]');
        var k = a && postKeyOf(a.getAttribute('href'));
        var isRead = !!(k && readSet && readSet.has(k));
        if (f.read === 'read' && !isRead) hide = true;
        if (f.read === 'unread' && isRead) hide = true;
        if (f.rec >= 0 && numIn(li, '추천') < f.rec) hide = true;
        if (f.view >= 0 && numIn(li, '조회') < f.view) hide = true;
        if (f.cmt >= 0) {
          var ct = li.querySelector('.ct');
          var c = ct ? parseInt((ct.textContent || '').replace(/[^0-9]/g, '') || '0', 10) : 0;
          if (c < f.cmt) hide = true;
        }
      }
      li.classList.toggle('dcapp-filtered', hide);
    });
  }
  // ---------- 글 목록 맨 아래에서 위로 더 당기면 → 디시 '더보기'(v) 눌러 다음 글 이어 붙이기 ----------
  (function pullForMore() {
    var base = null, armed = false, tip = null;
    function moreBtn() {
      var b = document.getElementById('listMore');
      return b && b.offsetParent !== null && document.querySelector('ul.gall-detail-lst') ? b : null;
    }
    function atBottom() {
      var se = document.scrollingElement || document.documentElement;
      return window.scrollY + window.innerHeight >= se.scrollHeight - 4;
    }
    function showTip(on) {
      if (on && !tip) {
        tip = document.createElement('div');
        tip.textContent = '놓으면 다음 글 불러오기';
        tip.style.cssText = 'position:fixed;left:50%;bottom:120px;transform:translateX(-50%);z-index:2147483000;padding:8px 14px;border-radius:999px;background:rgba(59,72,144,.92);color:#fff;font-size:14px;pointer-events:none';
        document.body.appendChild(tip);
      } else if (!on && tip) { tip.remove(); tip = null; }
    }
    document.addEventListener('touchstart', function () { base = null; armed = false; }, { passive: true });
    document.addEventListener('touchmove', function (e) {
      if (!moreBtn() || e.touches.length !== 1) return;
      var y = e.touches[0].clientY;
      if (!atBottom()) { base = null; if (armed) { armed = false; showTip(false); } return; }
      if (base === null) base = y;                 // 맨 아래에 닿은 순간부터 잰 당긴 거리
      var pulled = base - y > 90;
      if (pulled !== armed) { armed = pulled; showTip(armed); }
    }, { passive: true });
    document.addEventListener('touchend', function () {
      showTip(false);
      if (!armed) return;
      armed = false; base = null;
      var b = moreBtn();
      if (b) { if (typeof window.list_more === 'function') window.list_more(); else b.click(); }
    }, { passive: true });
  })();

  /// 글 목록 페이지 이동: 디시 페이지 번호는 숨기고 앱이 큰 버튼으로 다시 그림
  /// « 처음 · ‹ 이전 · 지금 페이지 앞뒤 번호 · › 다음 · 이동(번호 입력). 검색 결과면 아래 줄에 이전/다음 검색·날짜 이동
  function buildPager() {
    var pg = document.getElementById('pagination_div');
    if (!pg || !document.querySelector('ul.gall-detail-lst')) return;
    var sig = location.href + '|' + pg.innerHTML.length;
    var bar = document.getElementById('dcapp-pager');
    if (bar && bar.getAttribute('data-sig') === sig) return;
    var links = Array.prototype.slice.call(pg.querySelectorAll('.paging-inner a'));
    var nums = links.map(function (a) { return parseInt(txt(a), 10); }).filter(function (n) { return n > 0; });
    var curEl = pg.querySelector('.paging-inner strong');
    var cur = parseInt(curEl ? txt(curEl) : '', 10);
    var base = new URL(links.length ? links[0].href : location.href);
    if (!(cur > 0)) cur = parseInt(new URL(location.href).searchParams.get('page'), 10) || 1;
    var prev = pg.querySelector('a.prev'), next = pg.querySelector('a.next');
    function isSearchJump(a) { return !!a && /[?&]s_pos=/.test(a.getAttribute('href') || '') && !/[?&]s_pos=/.test(base.search); }
    // 일반 목록: 디시 '다음'이 있으면 뒤 페이지가 더 있음. 없으면 보이는 마지막 번호가 끝
    var hasMore = !!next && !isSearchJump(next);
    var last = hasMore ? Infinity : Math.max(cur, nums.length ? Math.max.apply(null, nums) : cur);
    function pageURL(n) { var u = new URL(base.toString()); u.searchParams.set('page', String(n)); u.hash = ''; return u.toString(); }
    function btn(label, href, cls, aria) {
      var a = document.createElement('a');
      a.textContent = label;
      if (href) a.href = href; else a.className = 'off';
      if (cls) a.className = (a.className ? a.className + ' ' : '') + cls;
      if (aria) a.setAttribute('aria-label', aria);
      return a;
    }
    var start = Math.max(1, cur - 2), end = start + 4;
    if (end > last) { end = last; start = Math.max(1, end - 4); }
    var row = document.createElement('div');
    row.className = 'dcapp-pg-row';
    row.appendChild(btn('«', cur > 1 ? pageURL(1) : null, 'dcapp-pg-arw', '처음'));
    row.appendChild(btn('‹', cur > 1 ? pageURL(cur - 1) : null, 'dcapp-pg-arw', '이전 페이지'));
    for (var n = start; n <= end; n++) row.appendChild(btn(String(n), n === cur ? null : pageURL(n), n === cur ? 'on' : null));
    row.querySelectorAll('a.off.on').forEach(function (a) { a.classList.remove('off'); });
    row.appendChild(btn('›', cur < last ? pageURL(cur + 1) : null, 'dcapp-pg-arw', '다음 페이지'));
    var go = btn('이동', 'javascript:void(0)', null, '페이지 번호로 이동');
    go.addEventListener('click', function (e) {
      e.preventDefault();
      var v = window.prompt('이동할 페이지 번호 (지금 ' + cur + '페이지)', '');
      var to = parseInt((v || '').replace(/[^0-9]/g, ''), 10);
      if (to > 0 && to !== cur) location.href = pageURL(isFinite(last) ? Math.min(to, last) : to);
    });
    row.appendChild(go);
    var box = document.createElement('div');
    box.id = 'dcapp-pager';
    box.setAttribute('data-sig', sig);
    box.appendChild(row);
    // 검색 결과: 디시는 검색을 구간으로 나눠서 '이전/다음 검색'과 날짜 이동이 따로 있음
    var dateBtn = pg.querySelector('button.sch-move');
    if (isSearchJump(prev) || isSearchJump(next) || /[?&]s_pos=/.test(base.search)) {
      var sub = document.createElement('div');
      sub.className = 'dcapp-pg-row dcapp-pg-sub';
      if (prev && /[?&]s_pos=/.test(prev.getAttribute('href') || '')) sub.appendChild(btn('이전 검색', prev.href));
      if (dateBtn) {
        var d = btn('날짜로 이동', 'javascript:void(0)');
        d.addEventListener('click', function (e) { e.preventDefault(); dateBtn.click(); });
        sub.appendChild(d);
      }
      if (next && /[?&]s_pos=/.test(next.getAttribute('href') || '')) sub.appendChild(btn('다음 검색', next.href));
      if (sub.children.length) box.appendChild(sub);
    }
    if (bar) bar.parentNode.removeChild(bar);
    pg.classList.add('dcapp-hide');
    pg.parentNode.insertBefore(box, pg.nextSibling);
  }

  /// 글 목록: 페이지 번호 아래(개념글보기·글쓰기 버튼, 검색칸, 디시 바닥글)는 전부 숨김 — 앱 컨트롤바에 다 있음
  function hideBelowPaging() {
    var pg = document.getElementById('pagination_div');
    if (!pg || !document.querySelector('ul.gall-detail-lst')) return;
    var sec = pg.closest('section') || pg;
    for (var n = sec.nextElementSibling; n; n = n.nextElementSibling) {
      if (/^(SECTION|FOOTER)$/.test(n.tagName) || n.classList.contains('footer')) n.classList.add('dcapp-hide');
    }
    document.querySelectorAll('footer, .footer').forEach(function (f) { f.classList.add('dcapp-hide'); });
  }
  function setListFilter(f) { listFilter = f || null; applyListFilter(); return true; }
  function setReadPosts(keys) { readSet = new Set(keys || []); markReadRows(); return readSet.size; }
  // 글 화면의 글쓴이 (작성한 글 기록용)
  function articleIdentity() {
    var h = articleHead();
    if (!h) return null;
    var r = identity({ el: h, kind: 'article' });
    r.title = txt(h.querySelector('.tit') || h).replace(/^\s*\[[^\]]*\]\s*/, '').trim();
    return r;
  }
  // 디시 원래 글쓰기 화면에서 등록을 누르면 → 앱에 알림 (작성한 글 기록)
  (function hookWriteSubmit() {
    if (!/\/write/.test(location.pathname)) return;
    var tries = 0;
    var t = setInterval(function () {
      if (++tries > 40) { clearInterval(t); return; }
      if (typeof window.write_submit !== 'function' || window.write_submit.__dcapp) return;
      clearInterval(t);
      var orig = window.write_submit;
      var wrapped = function () {
        try {
          var s = document.getElementById('subject'), n = document.getElementById('name');
          post('websubmit', { title: s ? s.value : '', nick: n ? n.value : '' });
        } catch (e) {}
        return orig.apply(this, arguments);
      };
      wrapped.__dcapp = true;
      window.write_submit = wrapped;
    }, 250);
  })();

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
      // li만 셈 (닉네임 뒤에 붙인 메모 span 때문에 칸 수가 달라지지 않게)
      var lis = g ? Array.prototype.filter.call(g.children, function (c) { return c.tagName === 'LI'; }) : [];
      if (lis.length) return lis.length >= 5 ? lis[1] : lis[0];
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
  /// 지금 보고 있는 갤러리 아이디 (/board/{id}, /mini/{id}) — 갤러리별 차단·메모용
  function currentGalleryId() {
    var p = location.pathname.split('/');
    return (p[1] === 'board' || p[1] === 'mini' || p[1] === 'person') ? (p[2] || '') : '';
  }

  function blockedReason(u, idn, dset) {
    // 디시 자체 차단창으로 막은 사람: 디시는 block-disable 표시만 붙여 흐리게 보여줌 → 앱 차단처럼 가림
    if (u.el.classList.contains('block-disable')) return '디시 차단';
    var users = cfg.users || [], gid = currentGalleryId();
    for (var i = 0; i < users.length; i++) {
      var b = users[i];
      if (b.g && b.g !== gid) continue;                  // 다른 갤러리 전용 차단
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
    // 갤러리 이름 줄 ("아이패드 ⓜ (1,085,094) ☆ | ⓘ 설정 연관 글쓰기", 인물갤은 '연관' 대신 '인맥') — 앱 상단바에 갤러리 이름이 있으므로 숨김
    var rows = document.querySelectorAll('div, section, header');
    var row = null;
    for (var j = 0; j < rows.length; j++) {
      var rt = txt(rows[j]);
      if (rt.length < 80 && /연관|인맥/.test(rt) && /설정/.test(rt) && /글쓰기/.test(rt)) row = rows[j];   // 가장 안쪽 것으로 갱신
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
  // 만두 모양 아이콘(디시 모바일은 span.sp-icon.dori-icon)으로만 구분 → 그 댓글 칸(li)을 숨김
  // (닉네임만 '댓글돌이'인 사람은 숨기지 않음)
  function doryItems() {
    var out = [];
    function add(el) {
      var li = el && el.closest ? el.closest('li') : null;
      if (li && out.indexOf(li) < 0) out.push(li);
    }
    document.querySelectorAll('.dori-icon, [class*="dory"], img[src*="dory"]').forEach(add);
    return out;
  }
  function hideDory() {
    var on = cfg.hideDory !== false;
    document.querySelectorAll('.dcapp-dory').forEach(function (el) { if (!on) el.classList.remove('dcapp-dory'); });
    if (on) doryItems().forEach(function (li) { li.classList.add('dcapp-dory'); });
  }

  // ---------- 대댓글 입력칸을 일반 댓글칸과 같은 높이로 ----------
  var mainCommentH = 0;
  function sizeReplyBoxes() {
    if (/\/write/.test(location.pathname)) return;
    var main = document.getElementById('comment_memo') || document.querySelector('textarea.comment-caption');
    var h = main ? main.getBoundingClientRect().height : 0;
    if (h >= 60) mainCommentH = h;                        // 보이는 동안 재 둔 높이를 기억 (붙여 둔 동안 등 0일 때 대비)
    var target = Math.round(mainCommentH || 100);
    document.querySelectorAll('textarea').forEach(function (t) {
      if (t === main || !isCommentField(t)) return;
      if (t.getAttribute('data-dcapp-tall') === String(target)) return;
      t.setAttribute('data-dcapp-tall', String(target));
      t.style.setProperty('min-height', target + 'px', 'important');
    });
  }

  /// 페이지에 보이는 로그인/로그아웃 링크로 지금 로그인 상태 추정 ('in' / 'out' / 'unknown')
  function loginState() {
    var links = Array.prototype.slice.call(document.querySelectorAll('a, button'));
    function has(re) { return links.some(function (a) { return re.test(txt(a)); }); }
    if (has(/^로그아웃$/)) return 'in';
    if (links.some(function (a) { return /^로그인$/.test(txt(a)) && /msign\.dcinside\.com|login/i.test(a.getAttribute('href') || a.getAttribute('onclick') || ''); })) return 'out';
    return 'unknown';
  }

  /// 내 댓글이 아닌 보통 댓글 칸의 배경색 (없으면 페이지 배경색, 그것도 투명이면 흰색)
  function normalCommentBg() {
    var others = document.querySelectorAll('li.comment:not(.on):not(.dcapp-mine)');
    for (var i = 0; i < others.length; i++) {
      var c = getComputedStyle(others[i]).backgroundColor;
      if (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') return c;
    }
    var b = getComputedStyle(document.body).backgroundColor;
    return (b && b !== 'rgba(0, 0, 0, 0)' && b !== 'transparent') ? b : '#fff';
  }

  // ---------- 테마: 웹페이지 속 디시 파란색 계열을 앱 테마 색으로 ----------
  // 파란색 계열(색상각 200~262°, 채도 있는 색)만 골라 색상각을 테마 색으로 돌림. 밝기는 그대로라 연한 배경은 연하게 유지
  // 글 본문(사용자가 쓴 내용)은 건드리지 않음
  var tintKey = '', tintN = 0, tintTimer = null;
  function parseRGB(c) {
    var m = /rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/.exec(c || '');
    if (!m) return null;
    var a = m[4] === undefined ? 1 : +m[4];
    return a === 0 ? null : [+m[1], +m[2], +m[3], a];
  }
  function rgb2hsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b), h = 0, s = 0, l = (mx + mn) / 2;
    if (mx !== mn) {
      var d = mx - mn;
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h *= 60;
    }
    return [h, s, l];
  }
  function hsl2rgb(h, s, l) {
    if (s === 0) return [l * 255, l * 255, l * 255];
    h /= 360;
    function f(p, q, t) {
      if (t < 0) t += 1; if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    return [f(p, q, h + 1 / 3) * 255, f(p, q, h) * 255, f(p, q, h - 1 / 3) * 255];
  }
  function tintColor(c, t) {
    var v = parseRGB(c);
    if (!v) return null;
    var hsl = rgb2hsl(v[0], v[1], v[2]);
    if (hsl[0] < 200 || hsl[0] > 262 || hsl[1] < 0.12) return null;
    var o = hsl2rgb(t.h, Math.min(1, hsl[1] * t.s), hsl[2]);
    return 'rgba(' + Math.round(o[0]) + ',' + Math.round(o[1]) + ',' + Math.round(o[2]) + ',' + v[3] + ')';
  }
  var TINT_PROPS = [['color', 'color'], ['backgroundColor', 'background-color'],
    ['borderTopColor', 'border-top-color'], ['borderBottomColor', 'border-bottom-color'],
    ['borderLeftColor', 'border-left-color'], ['borderRightColor', 'border-right-color']];
  function untintAll() {
    document.querySelectorAll('[data-dcapp-tint]').forEach(function (el) {
      el.getAttribute('data-dcapp-tint').split(',').forEach(function (p) { if (p) el.style.removeProperty(p); });
      el.removeAttribute('data-dcapp-tint');
    });
    document.querySelectorAll('[data-dcapp-pc]').forEach(function (el) { el.removeAttribute('data-dcapp-pc'); });
    var st = document.getElementById('dcapp-tint-pseudo');
    if (st) st.textContent = '';
  }
  function tintPage() {
    var t = cfg.tint;
    var key = t ? t.h + '/' + t.s : '';
    if (key !== tintKey) { untintAll(); tintKey = key; }
    if (!t || !document.body) return;
    var st = document.getElementById('dcapp-tint-pseudo');
    if (!st) {
      st = document.createElement('style');
      st.id = 'dcapp-tint-pseudo';
      (document.head || document.documentElement).appendChild(st);
    }
    var body = articleBody(), rules = [];
    var all = document.body.getElementsByTagName('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (body && body.contains(el)) continue;                     // 글 본문은 그대로
      if (el.closest('.dcapp-mine-name')) continue;                // 내 닉네임 표시 색은 테마와 상관없이 유지
      if (/^(IMG|VIDEO|SVG|PATH|SCRIPT|STYLE|IFRAME)$/i.test(el.tagName)) continue;
      var cs = getComputedStyle(el), done = el.getAttribute('data-dcapp-tint') || '';
      TINT_PROPS.forEach(function (p) {
        var nc = tintColor(cs[p[0]], t);
        if (!nc) return;
        el.style.setProperty(p[1], nc, 'important');
        if (done.indexOf(p[1]) < 0) done += (done ? ',' : '') + p[1];
      });
      if (done) el.setAttribute('data-dcapp-tint', done);
      // ::before / ::after (선택된 탭 밑줄 등)
      if (el.hasAttribute('data-dcapp-pc')) continue;
      ['before', 'after'].forEach(function (ps) {
        var pcs = getComputedStyle(el, '::' + ps);
        if (!pcs || pcs.content === 'none' || pcs.content === 'normal') return;
        var decl = '';
        TINT_PROPS.forEach(function (p) {
          var nc = tintColor(pcs[p[0]], t);
          if (nc) decl += p[1] + ':' + nc + '!important;';
        });
        if (!decl) return;
        if (!el.hasAttribute('data-dcapp-pc')) el.setAttribute('data-dcapp-pc', String(++tintN));
        rules.push('[data-dcapp-pc="' + el.getAttribute('data-dcapp-pc') + '"]::' + ps + '{' + decl + '}');
      });
    }
    if (rules.length) st.textContent += rules.join('\n') + '\n';
  }
  function scheduleTint() {
    if (tintTimer) return;
    tintTimer = setTimeout(function () { tintTimer = null; try { tintPage(); } catch (e) {} }, 250);
  }

  /// 유저 메모를 닉네임 바로 뒤에 표시 (아이디 > IP > 닉네임 순으로 찾음).
  /// 닉네임 칸 '안'이 아니라 '뒤'에 붙여서, 작성자 판별(닉네임 글자 읽기)에 섞이지 않게 함
  function showMemo(u, nk) {
    if (u.kind === 'article' && !nk.parentNode) return;
    var gid = currentGalleryId(), idn = identity(u), m = null;
    // 같은 대상에 메모가 여러 개면 ' · '로 이어서 (이 갤러리 전용 메모 먼저)
    var memos = (cfg.memos || []).filter(function (x) { return !x.g || x.g === gid; })
      .sort(function (a, b) { return (b.g ? 1 : 0) - (a.g ? 1 : 0); });
    // 아이디·IP·닉네임 메모를 전부 모음 (한 종류만 보면 다른 종류로 단 메모가 가려짐 — 유동은 IP·닉네임이 섞여 있음)
    // 닉네임은 공백·(IP) 꼬리표를 떼고 비교 (글 화면과 목록에서 닉네임 칸 글자가 조금씩 달라도 같은 사람으로)
    var texts = [], seenText = {};
    var normNick = function (v) { return String(v || '').replace(/\([^)]*\)/g, '').replace(/\s+/g, ''); };
    // 목록은 긴 닉네임을 '가나다..'처럼 줄여 씀 → 줄인 닉네임은 앞부분이 같으면 같은 사람으로
    var nickSame = function (memoNick, rowNick) {
      var a = normNick(memoNick), b = normNick(rowNick);
      if (/\.\.$/.test(b)) { b = b.replace(/\.+$/, ''); return b.length >= 2 && a.indexOf(b) === 0; }
      return a === b;
    };
    [['id', idn.id], ['ip', idn.ip], ['nick', idn.nick]].forEach(function (p) {
      if (!p[1]) return;
      memos.forEach(function (x) {
        var same = p[0] === 'nick' ? (x.k === 'nick' && nickSame(x.v, p[1])) : (x.k === p[0] && x.v === p[1]);
        if (same && !seenText[x.t]) { seenText[x.t] = true; texts.push(x.t); }
      });
    });
    if (texts.length) m = { t: texts.join(' · ') };
    // 자동메모: 글 목록의 로그인 계정(아이디 있음, 유동 아님)에 보이는 메모가 하나도 없으면 아이디로 메모
    if (!texts.length && cfg.autoMemo && u.kind === 'post' && idn.id && !idn.ip) {
      if (cfg.autoMemo === 'all' || gid) queueAutoMemo(idn.id, cfg.autoMemo === 'all' ? '' : gid);
    }
    var next = nk.nextElementSibling;
    var tag = next && next.classList.contains('dcapp-memo') ? next : null;
    if (m) {
      if (!tag) {
        tag = document.createElement('span');
        tag.className = 'dcapp-memo';
        nk.parentNode.insertBefore(tag, nk.nextSibling);
      }
      if (tag.textContent !== m.t) tag.textContent = m.t;
    } else if (tag) {
      tag.parentNode.removeChild(tag);
    }
  }

  /// 닉네임 글자(첫 텍스트)만 span으로 감싸 표시 / 해제
  function markMineNick(nk, mine) {
    var sp = null;
    for (var c = nk.firstChild; c; c = c.nextSibling) {
      if (c.nodeType === 1 && c.classList.contains('dcapp-mine-name')) { sp = c; break; }
    }
    if (mine && !sp) {
      for (var n = nk.firstChild; n; n = n.nextSibling) {
        if (n.nodeType === 3 && n.nodeValue.trim()) {
          var name = n.nodeValue.trim();
          sp = document.createElement('span');
          sp.className = 'dcapp-mine-name';
          sp.textContent = name;
          nk.replaceChild(sp, n);
          break;
        }
      }
    } else if (!mine && sp) {
      nk.replaceChild(document.createTextNode(sp.textContent), sp);
    }
  }

  // ---------- 유동 닉네임/비밀번호 기억 (로그인했다 풀면 사이트가 지워버려서 앱이 기억했다가 채움) ----------
  function anonFields() {
    if (isLoginPage()) return [];
    var out = [];
    document.querySelectorAll('input').forEach(function (i) {
      if (i.type === 'hidden' || i.id === 'commentDel_pw') return;
      if ((i.disabled || i.readOnly) && i.type === 'password') return; // 닉네임 칸은 잠겨('ㅇㅇ' 고정) 있어도 포함
      if (i.closest && i.closest('#pw_layer, .layer-center-popup')) return;   // 댓글 삭제 비번 등 팝업 칸 제외
      var lab = ((i.name || '') + ' ' + (i.id || '') + ' ' + (i.getAttribute('placeholder') || '')).toLowerCase();
      var kind = null;
      if (i.type === 'password' && /pass|pw|비밀번호/.test(lab)) kind = 'pw';
      else if ((i.type === 'text' || i.type === '') && /nick|name|닉네임/.test(lab) && !/search|subject|title|제목|검색/.test(lab)) kind = 'nick';
      if (kind) out.push({ el: i, kind: kind });
    });
    return out;
  }
  // 디시는 페이지를 그린 뒤 잠깐 있다가 닉네임 칸에 갤러리 기본 닉네임을 넣고 잠금 → 앱이 먼저 채워도 덮어씀.
  // 그래서 한 번 채우고 끝내지 않고, 몇 번(페이지 열린 뒤 0.5/1.5/3초 등) 다시 확인해서 잠겨 있으면 다시 풂.
  // 사람이 직접 입력한 칸은 더 이상 건드리지 않음.
  function fillAnon() {
    var a = cfg.anon || {};
    anonFields().forEach(function (f) {
      if (f.el.getAttribute('data-dcapp-user') === '1') return;     // 직접 입력한 칸
      if (f.el.getAttribute('data-dcapp-unlocking') === '1') return; // 지금 푸는 중
      var tries = +(f.el.getAttribute('data-dcapp-anon-tries') || 0);
      if (tries >= 4) return;
      var saved = f.kind === 'pw' ? a.pw : a.nick;
      if (!saved) return;
      var locked = f.el.disabled || f.el.readOnly;
      var cur = f.el.value;
      if (!locked && cur === saved) return;
      if (!locked && cur && !(f.kind === 'nick' && cur === 'ㅇㅇ')) return;   // 잠기지 않은 칸의 다른 값은 그대로
      f.el.setAttribute('data-dcapp-anon-tries', String(tries + 1));
      if (locked) { unlockAndFill(f.el, saved); return; }
      setVal(f.el, saved);
      anonLog.push(f.kind + ' 빈 칸 채움');
    });
  }
  [500, 1500, 3000, 6000].forEach(function (ms) { setTimeout(function () { try { fillAnon(); } catch (e) {} }, ms); });

  /// 잠긴 유동 닉네임 칸 풀고 채우기: 디시 버튼(닉네임 지우기 → 닉네임 사용)을 차례로 눌러 보고,
  /// 그래도 잠겨 있으면 직접 잠금을 풂. 디시 처리가 늦을 수 있어서 잠깐씩 기다리며 확인
  var anonLog = [];
  function unlockAndFill(el, value) {
    var steps = [
      // 디시는 버튼 안쪽 span에 onclick(gallNicknameSetting(this,'off'))을 달아 둬서, 버튼이 아니라 그 span을 눌러야 함
      function () { var b = document.getElementById('delete_nickname_btn'); if (b) { (b.querySelector('[onclick]') || b).click(); return '갤닉 끄기'; } return null; },
      function () { el.disabled = false; el.readOnly = false; el.removeAttribute('disabled'); el.removeAttribute('readonly'); return '직접 해제'; }
    ];
    var i = 0, waited = 0;
    el.setAttribute('data-dcapp-unlocking', '1');
    function tick() {
      if (!el.disabled && !el.readOnly) {
        el.removeAttribute('data-dcapp-unlocking');
        setVal(el, value);
        anonLog.push('채움(' + (i ? '단계 ' + i : '바로') + ') → 값=' + (el.value === value ? '내 닉' : el.value));
        // 디시가 곧바로 다시 덮어쓰는지 확인
        setTimeout(function () { anonLog.push('0.5초 뒤 값=' + (el.value === value ? '내 닉' : el.value) + (el.disabled ? ' 비활성' : '')); }, 500);
        return;
      }
      if (waited >= 300 || waited === 0) {
        if (i >= steps.length) { el.removeAttribute('data-dcapp-unlocking'); anonLog.push('실패: 계속 잠김'); return; }
        var r = steps[i++]();
        anonLog.push('시도 ' + i + ': ' + (r || '버튼 없음'));
        waited = 0;
      }
      waited += 50;
      setTimeout(tick, 50);
    }
    tick();
  }

  var anonTimer = null;
  function onAnonInput(e) {
    if (!e.isTrusted) return;          // 사람이 직접 입력한 것만 기억 (사이트·앱이 채운 값은 저장 안 함)
    var t = e.target;
    if (!t || t.tagName !== 'INPUT') return;
    var f = anonFields().filter(function (x) { return x.el === t; })[0];
    if (!f) return;
    f.el.setAttribute('data-dcapp-user', '1');
    clearTimeout(anonTimer);
    anonTimer = setTimeout(function () { post('anon', { kind: f.kind, value: t.value }); }, 400);
  }
  document.addEventListener('input', onAnonInput, true);
  document.addEventListener('change', onAnonInput, true);

  // ---------- 갤러리 관리 내역 (사이트 상단을 숨겨서 'ⓘ 갤러리 정보' 창의 링크를 못 누르므로 대신 열기) ----------
  function manageLogLink() {
    return Array.prototype.filter.call(document.querySelectorAll('a, button'), function (x) {
      return /관리\s*내역/.test(txt(x));
    })[0] || null;
  }
  function openManageLog() {
    var a = manageLogLink();
    if (!a) return 'none';
    var h = a.getAttribute('href') || '';
    if (h && !/^\s*(#|javascript:)/i.test(h)) { location.href = a.href; return 'nav'; }
    var inner = a.querySelector('[onclick]');
    (inner || a).click();
    return 'clicked';
  }

  // ---------- 오른쪽 세로 버튼 막대가 댓글 '등록' 버튼을 가리지 않도록 등록 버튼을 왼쪽으로 비켜 둠 ----------
  function avoidFloatBar() {
    var on = false;   // 등록 버튼은 원래 자리(오른쪽)에 두기로 함 — 예전에 비켜 둔 것만 되돌림
    var form = document.getElementById('comment_write') || (document.getElementById('comment_memo') || {}).form;
    if (!form) return;
    Array.prototype.forEach.call(form.querySelectorAll('button, a, input[type="submit"], input[type="button"]'), function (b) {
      var isSubmit = b.type === 'submit' || /^\s*(등록|작성)\s*$/.test(txt(b) || b.value || '');
      if (!isSubmit) return;
      if (on && !b.hasAttribute('data-dcapp-avoid')) {
        b.setAttribute('data-dcapp-avoid', '1');
        b.style.setProperty('margin-right', '64px', 'important');
      } else if (!on && b.hasAttribute('data-dcapp-avoid')) {
        b.removeAttribute('data-dcapp-avoid');
        b.style.removeProperty('margin-right');
      }
    });
  }

  // ---------- 갤닉네임 안내 말풍선 숨기기 ("'해갤러'는 갤러리에서 권장하는 비회원 전용 갤닉네임입니다") ----------
  // 유동 닉네임을 채우려고 갤닉네임을 끌 때 디시가 띄우는 초록 말풍선
  function hideGallNickTip() {
    var RE = /비회원\s*전용\s*갤닉/;
    Array.prototype.forEach.call(document.querySelectorAll('div, p, span, section, aside'), function (el) {
      if (el.classList.contains('dcapp-hide') || !RE.test(txt(el)) || txt(el).length > 160) return;
      if (Array.prototype.some.call(el.children, function (c) { return RE.test(txt(c)); })) return;   // 가장 안쪽 것만
      // 말풍선 상자(닫기 X 포함)까지 넓히되, 입력칸이 든 댓글 폼 전체는 넘지 않게
      var box = el;
      while (box.parentElement && box.parentElement !== document.body &&
             RE.test(txt(box.parentElement)) && txt(box.parentElement).length <= 160 &&
             !box.parentElement.querySelector('input, textarea')) {
        box = box.parentElement;
      }
      box.classList.add('dcapp-hide');
    });
  }

  function clearSelection() {
    try {
      var sel = window.getSelection();
      if (sel && sel.rangeCount) sel.removeAllRanges();
    } catch (e) {}
  }

  // ---------- 광고 자리 숨기기 (광고 서버 요청은 앱이 따로 막음 → 남은 빈 칸·광고 틀을 가림) ----------
  var AD_SELECTORS = [
    'ins.adsbygoogle', '[id^="div-gpt-ad"]', '[id^="google_ads"]', 'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]',
    '[class^="dable"]', '[class*=" dable"]', '[id^="dable"]', '[id^="mobon"]', '[class*="mobon"]', '[id*="adfit"]', '[class*="adfit"]',
    "li:has(> a[href*='ads.dcinside.com'])", "a[href*='addc.dcinside.com']", "a[href*='ads.dcinside.com']",
    '.ad-view', '.adv-area', '.ad_box', '.ad-box', '.adbox', '.banner_m', '.powerlink', '[class*="power-link"]',
    // 디시 모바일에서 확인한 것: 파워링크 광고 줄, 글 목록 맨 위 설문·AD 줄, 하단 '앱 다운로드' 배너, 상단 빈 검색 칸
    '.adv-group', '.pwlink', 'li:not(.notice):has(> .detail-top-lnk)', '#app_down_pop', '.layer-bottom-popup',
    '.outside-search-box',
    // 글 본문 아래 'AD | 더 알아보기' 광고 칸 (회색 띠째로)
    '[class*="adv-group"]', '[id^="rtbx-ad"]', '[id*="rtbx"]', '[class*="rtbx"]'
  ];
  /// 글 목록 맨 위의 'AD' / '설문' 줄 (선택자로 못 잡는 경우 글자로)
  function hideListPromos() {
    if (cfg.adBlock === false) return;
    document.querySelectorAll('ul.gall-detail-lst > li').forEach(function (li) {
      if (/^(AD|설문)\s/.test(txt(li))) li.classList.add('dcapp-pinned-off');
    });
    // 광고 칸을 감싼 회색 띠: 광고 말고 다른 내용이 없을 때만 같이 숨김
    document.querySelectorAll('.adv-groupin, [id^="rtbx-ad"]').forEach(function (ad) {
      var box = ad.parentElement;
      for (var i = 0; i < 3 && box && box !== document.body; i++) {
        // 글 본문 칸·글 영역은 절대 숨기지 않음 (사진만 있는 글은 글자가 없어서 빈 칸처럼 보임)
        if (box.matches('.thum-txt, .thum-txtin, .gall-thum-btm, .gall-thum-btm-inner, section, article') ||
            box.querySelector('.thum-txtin, .thum-txt')) break;
        var other = Array.prototype.some.call(box.children, function (c) {
          return !c.contains(ad) && c.offsetHeight > 0 && (txt(c) !== '' || !!c.querySelector('img, video, iframe') || /^(IMG|VIDEO|IFRAME)$/.test(c.tagName));
        });
        if (other || box.querySelector('textarea, .comment, .gallview-tit-box, .btn-list, .gall-detail-lst')) break;
        box.classList.add('dcapp-hide');
        box = box.parentElement;
      }
    });
  }
  /// 글 목록: 오른쪽 회색 칸의 댓글 수를 없애고 제목 옆에 파란 [댓글수]로
  function listCommentCount() {
    document.querySelectorAll('ul.gall-detail-lst > li').forEach(function (li) {
      var ct = li.querySelector('.ct');
      if (!ct) return;
      var box = ct.closest('a.rt') || ct.closest('.rt') || ct;
      var title = li.querySelector('.subjectin') || li.querySelector('.subject-add') || li.querySelector('.subject');
      if (!title) return;
      var n = (ct.textContent || '').replace(/[^0-9]/g, '');
      var tag = li.querySelector('.dcapp-cmt');
      if (n && n !== '0') {
        if (!tag) {
          tag = document.createElement('span');
          tag.className = 'dcapp-cmt';
          title.parentNode.insertBefore(tag, title.nextSibling);
        }
        if (tag.textContent !== '[' + n + ']') tag.textContent = '[' + n + ']';
      } else if (tag) tag.parentNode.removeChild(tag);
      box.classList.add('dcapp-hide');
    });
  }
  function adBlockCSS() {
    var st = document.getElementById('dcapp-adblock');
    if (cfg.adBlock === false) { if (st) st.parentNode.removeChild(st); return; }
    if (st) return;
    st = document.createElement('style');
    st.id = 'dcapp-adblock';
    st.textContent = AD_SELECTORS.map(function (s) { return s + '{display:none!important}'; }).join('\n');
    (document.head || document.documentElement).appendChild(st);
  }

  // ---------- 글 아래 수정·삭제 버튼 (본인 글 / 유동 글에만 디시가 보여 줌) → 앱이 대신 누르는 버튼으로 ----------
  var lastPostActions = null;
  function postActionButton(kind) {
    return document.querySelector('#view_btn_area button[onclick*="' + (kind === 'delete' ? 'board_delete' : 'board_modify') + '"]');
  }
  function reportPostActions() {
    var has = !!(postActionButton('modify') && postActionButton('delete'));
    if (has === lastPostActions) return;
    lastPostActions = has;
    post('postactions', { edit: has });
  }
  // ---------- 댓글 입력 칸: 줄이 늘면 같이 커지고, 10줄을 넘으면 스크롤 ----------
  function fitCommentBox(el) {
    if (!el || el.id !== 'comment_memo') return;
    var cs = getComputedStyle(el);
    var lh = parseFloat(cs.lineHeight) || 20;
    var pad = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
    var maxH = lh * 10 + pad;
    el.style.height = 'auto';
    var h = Math.max(parseFloat(cs.minHeight) || 0, Math.min(el.scrollHeight, maxH));
    el.style.height = h + 'px';
    el.style.overflowY = el.scrollHeight > maxH + 1 ? 'auto' : 'hidden';
  }
  document.addEventListener('input', function (e) { try { fitCommentBox(e.target); } catch (err) {} }, true);

  // ---------- 댓글 정렬: 등록순 / 최신순 / 답글순을 체크 버튼으로 (기본 등록순, 선택은 파란색) ----------
  var SORT_ITEMS = [['default', '등록순'], ['new', '최신순'], ['reply', '답글순']];
  var SORT_CHECK = '<svg viewBox="0 0 16 16"><path d="M3 8.4l3.2 3.2L13 4.6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  function buildCommentSort() {
    var sel = document.querySelector('.all-comment-tit select.sel');
    var rt = document.querySelector('.all-comment-tit .rt');
    if (!sel || !rt) return;
    var box = rt.querySelector('.dcapp-sort');
    if (!box) {
      box = document.createElement('div');
      box.className = 'dcapp-sort';
      SORT_ITEMS.forEach(function (it) {
        var b = document.createElement('button');
        b.type = 'button';
        b.setAttribute('data-v', it[0]);
        b.innerHTML = '<span class="dcapp-sort-ic"></span>' + it[1];
        b.addEventListener('click', function () {
          sel.value = it[0];
          sel.dispatchEvent(new Event('change', { bubbles: true }));
          buildCommentSort();
        });
        box.appendChild(b);
      });
      rt.appendChild(box);
    }
    box.querySelectorAll('button').forEach(function (b) {
      var on = sel.value === b.getAttribute('data-v');
      b.classList.toggle('on', on);
      var ic = b.querySelector('.dcapp-sort-ic');
      if (ic.getAttribute('data-k') !== SORT_CHECK) { ic.setAttribute('data-k', SORT_CHECK); ic.innerHTML = SORT_CHECK; }
    });
  }

  function postAction(kind) {
    var b = postActionButton(kind);
    if (!b) return false;
    b.click();
    return true;
  }

  // ---------- 자동메모: 글 목록에서 메모가 없는 로그인 계정을 아이디로 메모 요청 (유동은 제외) ----------
  var autoMemoSeen = {}, autoMemoQueue = [], autoMemoTimer = null;
  function queueAutoMemo(id, gid) {
    var key = gid + '|' + id;
    if (autoMemoSeen[key]) return;
    autoMemoSeen[key] = true;
    autoMemoQueue.push({ id: id, g: gid });
    if (autoMemoTimer) return;
    autoMemoTimer = setTimeout(function () {
      autoMemoTimer = null;
      var items = autoMemoQueue; autoMemoQueue = [];
      if (items.length) post('automemo', { items: items });
    }, 300);
  }

  // ---------- 글 제목 블록 · 개념/비추 버튼 개편 (글 화면) ----------
  function icon24(inner) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + inner + '</svg>';
  }
  var ICON_STAR = icon24('<path d="M12 3.6l2.6 5.4 5.9.8-4.3 4.1 1.1 5.9L12 16.9l-5.3 2.8 1.1-5.9-4.3-4.1 5.9-.8z"/>');
  var ICON_X = icon24('<path d="M5 5l14 14M19 5L5 19"/>');
  var ICON_CMT = icon24('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>');
  var ICON_BEST = icon24('<circle cx="12" cy="12" r="9.2"/><path d="M10 7.6h2.7a2 2 0 0 1 0 4H10zM10 11.6h3.2a2.2 2.2 0 0 1 0 4.4H10z"/>');
  var ICON_PUM = icon24('<path d="M17 2l4 4-4 4M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4M21 13v2a3 3 0 0 1-3 3H3"/>');
  var ICON_REPORT = icon24('<path d="M5 21V4M5 4h13l-2.5 4.5L18 13H5"/>');
  function textOf(sel) { var el = document.querySelector(sel); return el ? el.textContent.trim() : ''; }

  function buildArticleHead() {
    var h = articleHead();
    if (!h) return;
    var btm = h.querySelector('.btm'), stat = document.querySelector('.gall-thum-btm-inner > ul.ginfo2');
    if (!btm || !stat) return;
    var ul = btm.querySelector('ul.ginfo2'), rt = btm.querySelector('.rt');
    if (!ul) return;
    if (!rt) { rt = document.createElement('div'); rt.className = 'rt'; btm.appendChild(rt); }
    // 닉네임 아래 한 줄: 조회수 | 추천 | 작성일
    var lis = Array.prototype.filter.call(ul.children, function (c) { return c.tagName === 'LI' && !c.classList.contains('dcapp-meta'); });
    var dateLi = lis[1];
    if (dateLi && !dateLi.classList.contains('dcapp-datehide')) dateLi.classList.add('dcapp-datehide');
    var parts = [];
    for (var i = 0; i < 2; i++) { if (stat.children[i]) parts.push(txt(stat.children[i])); }
    if (dateLi) parts.push(txt(dateLi));
    var key = parts.join('\n');
    var meta = ul.querySelector('.dcapp-meta');
    if (!meta) { meta = document.createElement('li'); meta.className = 'dcapp-meta'; ul.appendChild(meta); }
    if (meta.getAttribute('data-k') !== key) {
      meta.setAttribute('data-k', key);
      meta.textContent = '';
      parts.forEach(function (p, n) {
        if (n) meta.appendChild(document.createElement('i'));
        meta.appendChild(document.createTextNode(p));
      });
    }
    // 오른쪽: 댓글 수 칸 (누르면 댓글창 맨 위로)
    var cnt = textOf('.btn-commentgo .point-red') || '0';
    var cb = rt.querySelector('.dcapp-cmtbox');
    if (!cb) {
      cb = document.createElement('button');
      cb.type = 'button';
      cb.className = 'dcapp-cmtbox';
      cb.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); scrollToComments(); });
      rt.appendChild(cb);
    }
    if (cb.getAttribute('data-k') !== cnt) {
      cb.setAttribute('data-k', cnt);
      cb.innerHTML = ICON_CMT + '<span>' + cnt + '</span>';
    }
    // 모바일/PC 표시 아이콘: 제목 옆 대신 댓글 수 버튼 왼쪽으로 옮김
    h.querySelectorAll('.tit .sp-icon').forEach(function (ic) {
      ic.classList.add('dcapp-titicon');
      if (ic.parentNode !== rt) rt.insertBefore(ic, cb);
    });
  }

  function buildVote() {
    var area = document.querySelector('.reco-area');
    if (!area || !area.parentNode) return;
    var v = document.querySelector('.dcapp-vote');
    if (!v) {
      var hasMem = !!area.querySelector('.go-ct'), hasDown = !!document.getElementById('nonrecommend_join');
      var picks = [['best', '.sp-bestchucon', ICON_BEST], ['pum', '.sp-crosspost', ICON_PUM], ['report', '.sp-report', ICON_REPORT]]
        .filter(function (p) { return area.querySelector(p[1]); });
      v = document.createElement('div');
      v.className = 'dcapp-vote';
      v.innerHTML =
        '<div class="dcapp-vbox up"><button type="button" class="dcapp-vcell" data-a="up">' + ICON_STAR + '</button><span class="dcapp-vnum"></span>' +
        (hasMem ? '<span class="dcapp-vmem"><svg viewBox="0 0 16 16"><rect width="16" height="16" rx="3" fill="#9a9aa0"/><text x="8" y="8" dominant-baseline="central" font-size="11" font-weight="700" text-anchor="middle" fill="#fff" font-family="Arial,sans-serif">g</text></svg><b></b></span>' : '') + '</div>' +
        (hasDown ? '<div class="dcapp-vbox down"><button type="button" class="dcapp-vcell" data-a="down">' + ICON_X + '</button><span class="dcapp-vnum"></span></div>' : '') +
        '<div class="dcapp-vicons">' + picks.map(function (p) { return '<button type="button" data-a="' + p[0] + '">' + p[2] + '</button>'; }).join('') + '</div>';
      area.parentNode.insertBefore(v, area);
      v.addEventListener('click', function (e) {
        var b = e.target.closest ? e.target.closest('button[data-a], .dcapp-vnum') : null;
        if (!b) return;
        // 별·X 버튼뿐 아니라 숫자 칸을 눌러도 같은 동작 (숫자 칸에는 data-a가 없으니 상자 종류로 찾음)
        var key = b.getAttribute('data-a') || (b.closest('.dcapp-vbox').classList.contains('up') ? 'up' : 'down');
        var map = { up: '#recommend_join', down: '#nonrecommend_join', best: '.reco-icon-lst .sp-bestchucon', pum: '.reco-icon-lst .sp-crosspost', report: '.reco-icon-lst .sp-report' };
        var el = document.querySelector(map[key]);
        if (el) el.click();
      });
    }
    function setText(el, t) { if (el && el.textContent !== t) el.textContent = t; }
    setText(v.querySelector('.up .dcapp-vnum'), textOf('#recomm_btn') || '0');
    setText(v.querySelector('.up .dcapp-vmem b'), textOf('#recomm_btn_member') || '0');
    setText(v.querySelector('.down .dcapp-vnum'), textOf('#nonrecomm_btn') || '0');
    var rj = document.getElementById('recommend_join'), cell = v.querySelector('.up .dcapp-vcell');
    if (rj && cell) cell.classList.toggle('on', rj.classList.contains('on'));
  }

  function apply() {
    ensureStyle();
    try { buildArticleHead(); buildVote(); } catch (e) {}
    try { reportPostActions(); } catch (e) {}
    try { fitCommentBox(document.getElementById('comment_memo')); } catch (e) {}
    try { buildCommentSort(); } catch (e) {}
    try { adBlockCSS(); hideListPromos(); } catch (e) {}
    try { listCommentCount(); } catch (e) {}
    try { markReadRows(); } catch (e) {}
    try { listRowLayout(); } catch (e) {}
    try { applyListFilter(); } catch (e) {}
    try { buildPager(); } catch (e) {}
    try { hideBelowPaging(); } catch (e) {}
    try { hideListTypeTabs(); } catch (e) {}
    try { buildHeadBar(); } catch (e) {}
    try { hideGallNickTip(); } catch (e) {}
    try { avoidFloatBar(); } catch (e) {}
    try { fillAnon(); } catch (e) {}
    if (cfg.tint || tintKey) scheduleTint();
    try { sizeReplyBoxes(); } catch (e) {}
    try { hideDory(); } catch (e) {}
    try { skipPwChange(); } catch (e) {}
    var enabled = cfg.enabled !== false;
    var mode = cfg.mode || 'collapse';
    var dset = new Set(cfg.dccons || []);
    findUnits().forEach(function (u) {
      var reason = null;
      if (enabled && u.el.getAttribute('data-dcapp-revealed') !== '1') reason = blockedReason(u, identity(u), dset);
      mark(u.el, reason, mode);
      // 로그인한 내 아이디와 작성자 아이디가 같으면 내 글·댓글
      var mine = !!cfg.myId && u.kind !== 'article' && identity(u).id === cfg.myId;
      u.el.classList.toggle('dcapp-mine', mine);
      // 칸 자체의 배경은 인라인 !important로 (어떤 사이트 규칙보다도 우선)
      if (u.kind === 'comment') {
        if (mine) {
          // 투명하게 하면 뒤의 댓글 영역(연한 파란색)이 비쳐 보임 → 다른 댓글 칸과 같은 색으로 칠함
          u.el.style.setProperty('background', normalCommentBg(), 'important');
          u.el.style.setProperty('box-shadow', 'none', 'important');
          u.el.setAttribute('data-dcapp-mine-bg', '1');
        } else if (u.el.hasAttribute('data-dcapp-mine-bg')) {
          u.el.style.removeProperty('background');
          u.el.style.removeProperty('box-shadow');
          u.el.removeAttribute('data-dcapp-mine-bg');
        }
      }
      var nk = nickElement(u);
      if (nk) { markMineNick(nk, mine); nk.classList.add('dcapp-lp-nick'); }
      if (nk) showMemo(u, nk);
      if (u.kind === 'article') {
        var body = articleBody();
        if (body) body.classList.toggle('dcapp-hide', !!reason);
      }
    });
    // 차단한 디시콘: '차단됨 표시'면 그 자리에 회색 안내 칸, '완전히 숨김'이면 흔적 없이
    document.querySelectorAll('img, video').forEach(function (m) {
      var k = dcconKey(m);
      if (!k) return;
      var off = enabled && dset.has(k);
      m.classList.toggle('dcapp-dccon-off', off);
      var prev = m.previousElementSibling;
      var lab = prev && prev.classList.contains('dcapp-dccon-label') ? prev : null;
      var wantLabel = off && mode !== 'remove';
      if (wantLabel && !lab && m.parentNode) {
        lab = document.createElement('span');
        lab.className = 'dcapp-dccon-label';
        lab.textContent = '차단한 디시콘';
        m.parentNode.insertBefore(lab, m);
      } else if (!wantLabel && lab) {
        lab.parentNode.removeChild(lab);
      }
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
      // 본문 위 작성자 칸은 칸 전체 글자에 날짜·'스크랩 갤로그 가기'까지 섞임 → 글 제목만
      var tit = u.kind === 'article' ? unitEl.querySelector('.tit') : null;
      d.snippet = txt(tit || unitEl).slice(0, 80);
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

  /// 닉네임 옆 IP 등 작성자 칸(.ginfo-area — 닉네임·IP·고닉 아이콘이 함께 있는 칸)을 눌렀는지
  function nickArea(target) {
    var area = target.closest('.ginfo-area');
    if (!area || !area.querySelector('.dcapp-lp-nick')) return null;
    if (target.closest('a[href]') && !/^\s*(#|javascript:)/i.test(target.closest('a[href]').getAttribute('href') || '')) return null;   // 갤로그 링크 등은 그대로
    return area;
  }
  var lp = null;
  var suppressClickUntil = 0;
  function clearLP() { if (lp) { clearTimeout(lp.timer); lp = null; } }

  document.addEventListener('touchstart', function (e) {
    if (pick.on || blockPick || e.touches.length !== 1) return;
    var target = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!target || !target.closest) return;
    if (target.closest('input, textarea, select, [contenteditable="true"], [contenteditable=""]')) return;   // 입력 중인 칸은 그대로
    var unitEl = target.closest('[data-dcapp-unit]');
    var media = target.closest('img, video');
    if (!unitEl && !dcconKey(media)) return;
    if (unitEl && unitEl.classList.contains('dcapp-collapsed')) return;
    // 차단·메모 메뉴는 닉네임(또는 그 옆 메모 칸)을 길게 누를 때만 — 본문·댓글 글자는 평소처럼 길게 눌러 복사
    if (!dcconKey(media)) {
      var nk = unitEl ? nickElement({ el: unitEl, kind: unitEl.getAttribute('data-dcapp-unit') }) : null;
      var onNick = (nk && (nk === target || nk.contains(target))) || !!target.closest('.dcapp-memo') || !!nickArea(target);
      if (!onNick) return;
    }
    var t = e.touches[0];
    clearLP();
    lp = {
      x: t.clientX, y: t.clientY,
      timer: setTimeout(function () {
        lp = null;
        suppressClickUntil = Date.now() + 800;
        post('longpress', describe(unitEl, target));
        // 길게 누르면 iOS가 글자를 선택해 버림 → 메뉴가 뜬 뒤 선택 풀기 (선택은 누르기가 끝날 때 생겨서 몇 번 나눠서)
        [60, 300, 700].forEach(function (ms) { setTimeout(clearSelection, ms); });
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

  // ---------- 닉네임·IP 누르기 → 디시 메뉴(.ginfo-ly) 대신 앱 차단·메모 메뉴 ----------
  window.addEventListener('click', function (e) {
    if (pick.on || blockPick) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!t || !t.closest) return;
    var area = t.closest('.ginfo-area');
    if (!area || t.closest('.ginfo-ly')) return;
    var a = t.closest('a[href]');
    if (a && !/^\s*(#|javascript:)/i.test(a.getAttribute('href') || '')) return;   // 갤로그 등 진짜 링크는 그대로
    var unitEl = area.closest('[data-dcapp-unit]');
    if (!unitEl) return;
    e.preventDefault(); e.stopPropagation();
    if (e.stopImmediatePropagation) e.stopImmediatePropagation();
    if (Date.now() < suppressClickUntil) return;    // 방금 길게 눌러 메뉴를 띄웠음
    post('longpress', describe(unitEl, t));
  }, true);

  // ---------- 글쓰기: 위쪽 갤러리 이름을 눌러도 갤러리로 이동하지 않음 ----------
  window.addEventListener('click', function (e) {
    if (!isWritePage()) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!t || !t.closest || !t.closest('.gall-tit-box a, a.gall-tit-lnk, a.gall-tit-lnkempty')) return;
    e.preventDefault(); e.stopPropagation();
    if (e.stopImmediatePropagation) e.stopImmediatePropagation();
  }, true);

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
    // (닉네임 탭은 디시 원래 동작(답글 등) 그대로 — 앱 차단·메모 메뉴는 길게 누르기로만)
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
  /// 글쓰기 제목 칸에 커서 (칸이 늦게 생기면 잠깐 기다렸다가 다시)
  function focusTitle(tries) {
    tries = tries || 0;
    var f = writeFields();
    if (!f.title) {
      if (tries < 10) setTimeout(function () { focusTitle(tries + 1); }, 300);
      return 'waiting';
    }
    // 이미 포커스가 있으면 다시 focus()해도 키보드를 띄우는 처리가 안 일어나서, 한 번 풀었다가 다시
    if (document.activeElement === f.title) f.title.blur();
    f.title.focus();
    try { f.title.scrollIntoView({ block: 'center' }); } catch (e) {}
    return 'focused';
  }
  /// 글쓰기 < > : 제목 ⇄ 내용 (내용 칸은 글 끝에 커서)
  function moveWriteFocus(forward) {
    var f = writeFields();
    var el = forward ? f.body : f.title;
    if (!el) return 'nofield';
    if (document.activeElement === el || (el.contains && el.contains(document.activeElement))) return 'same';
    el.focus();
    if (f.html && el === f.body) {
      try {
        var r = document.createRange(); r.selectNodeContents(el); r.collapse(false);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
      } catch (e) {}
    } else if (el.setSelectionRange) {
      try { var n = el.value.length; el.setSelectionRange(n, n); } catch (e) {}
    }
    try { el.scrollIntoView({ block: 'center' }); } catch (e) {}
    return 'moved';
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
  // 댓글 칸을 누르면 → 앱이 광고 차단을 끔 (등록 요청이 끝나거나 페이지를 벗어나면 다시 켬)
  var adPauseAt = 0;
  document.addEventListener('focusin', function (e) {
    if (!isCommentField(e.target) || Date.now() - adPauseAt < 3000) return;
    adPauseAt = Date.now();
    post('adpause', {});
  }, true);
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
  // 키보드 위에 붙인 글쓰기 도구줄 높이를 앱에 알림 (앱의 < > 버튼을 그 위로 올리려고)
  var tdockReported = -1;
  function reportTDock(h) {
    h = Math.round(h || 0);
    if (h === tdockReported) return;
    tdockReported = h;
    post('tdock', { h: h });
  }
  function positionTDock() {
    if (!tdock.el) { reportTDock(0); return; }
    var vv = window.visualViewport;
    var h = tdock.el.offsetHeight;
    reportTDock(h);
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
    reportTDock(0);
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
    selAtTouch = hasSelection();
    selChangedInTouch = false;
  }, { capture: true, passive: true });

  // ---------- 글자 선택(드래그) 중에는 스와이프 뒤로가기 안 함 ----------
  var selAtTouch = false, selChangedInTouch = false;
  function hasSelection() {
    var s = window.getSelection && window.getSelection();
    return !!(s && !s.isCollapsed && String(s).trim());
  }
  // 선택 손잡이를 끄는 동안에는 터치 이벤트 대신 선택 변경만 들어옴
  document.addEventListener('selectionchange', function () { if (hasSelection()) selChangedInTouch = true; });
  function textSelecting() { return selAtTouch || selChangedInTouch || hasSelection(); }

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
  // ---------- 댓글 등록이 429로 막히면 → 등록될 때까지 0.1초마다 등록 버튼 다시 누르기 ----------
  var cmtRetry = { form: null, memo: '', tries: 0, on: false, url: '', timer: null, watchdog: null };
  function commentFormOf(el) {
    var f = el && el.closest ? el.closest('form') : null;
    return f && f.querySelector('textarea[name^="comment_memo"]') ? f : null;
  }
  // 사용자가 누른 댓글 등록 버튼의 양식을 기억 (본댓글·답글 어느 쪽인지)
  document.addEventListener('click', function (e) {
    if (cmtRetry.on || !e.isTrusted) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    var b = t && t.closest ? t.closest('button[type="submit"], .btn-comment-write') : null;
    var f = b && commentFormOf(b);
    if (f) cmtRetry.form = f;
  }, true);
  document.addEventListener('submit', function (e) {
    if (!cmtRetry.on && e.isTrusted && commentFormOf(e.target)) cmtRetry.form = e.target;
  }, true);
  function stopCmtRetry() {
    cmtRetry.on = false; cmtRetry.tries = 0;
    clearTimeout(cmtRetry.timer); clearTimeout(cmtRetry.watchdog);
    cmtRetry.timer = cmtRetry.watchdog = null;
  }
  // 다음 누르기 예약 (한 줄로만 — 디시가 연달아 보낸 429가 와도 겹치지 않게)
  function scheduleCmtRetry() {
    if (!cmtRetry.on || cmtRetry.timer) return;
    cmtRetry.timer = setTimeout(function () { cmtRetry.timer = null; retryCommentOnce(); }, 100);
  }
  // 댓글이 등록됐는데 목록에 안 나타나는 경우(가끔 디시가 새로 불러온 목록에 빠져 있음) → 앱이 글을 다시 불러오게
  window.addEventListener('dcapp-cmtwrite', function (ev) {
    var d = ev.detail || {};
    if (d.status !== 200) return;
    var ok = false;
    try { var j = JSON.parse(d.text || '{}'); ok = j.result !== false && j.result !== 0 && j.result !== '0'; } catch (e) { return; }
    if (!ok) return;
    var memo = '', nickIn = '';
    try {
      var q = new URLSearchParams(d.body || '');
      memo = (q.get('comment_memo') || '').replace(/\s+/g, ' ').trim();
      nickIn = q.get('comment_nick') || '';
    } catch (e) {}
    var head = articleHead();
    var title = head ? txt(head.querySelector('.tit') || head).replace(/^\s*\[[^\]]*\]\s*/, '').trim() : '';
    if (!memo) { post('cmtwritten', { memo: '(디시콘)', nick: nickIn, ip: '', id: '', title: title }); return; }   // 디시콘만 단 댓글은 글자로 확인 못 함
    var key = memo.slice(0, 20);
    var page = location.href;
    setTimeout(function () {
      if (location.href !== page) return;
      var mine = null;
      Array.prototype.some.call(document.querySelectorAll('li.comment, li.comment-add'), function (li) {
        if ((li.textContent || '').replace(/\s+/g, ' ').indexOf(key) >= 0) { mine = li; return true; }
        return false;
      });
      // 작성한 댓글 기록: 쓴 신분(닉네임·IP·아이디)은 목록에 나온 내 댓글에서 읽음
      var who = mine ? identity({ el: mine, kind: 'comment' }) : { nick: nickIn, ip: '', id: '' };
      post('cmtwritten', { memo: memo.slice(0, 80), nick: who.nick || nickIn, ip: who.ip || '', id: who.id || '', title: title });
      if (!mine) post('cmtmissing', {});
    }, 2500);
  });
  window.addEventListener('dcapp-cmtwrite', function (ev) {
    var d = ev.detail || {};
    if (d.status === 429) {
      if (!cmtRetry.on) {
        var memo = '';
        try { memo = new URLSearchParams(d.body || '').get('comment_memo') || ''; } catch (e) {}
        if (!memo || !cmtRetry.form || !document.body.contains(cmtRetry.form)) return;   // 디시콘 등 → 안 함
        cmtRetry.on = true; cmtRetry.memo = memo; cmtRetry.tries = 0; cmtRetry.url = location.href;
        post('cmtretry', { state: 'start' });
      }
      clearTimeout(cmtRetry.watchdog);
      scheduleCmtRetry();
      return;
    }
    if (cmtRetry.on) {
      var ok = false;
      try { var j = JSON.parse(d.text || '{}'); ok = d.status === 200 && j.result !== false && j.result !== 0; } catch (e) { ok = d.status === 200; }
      if (ok) post('cmtretry', { state: 'done', tries: cmtRetry.tries });
      stopCmtRetry();      // 429가 아닌 다른 이유로 실패하면 디시 안내를 보여주고 멈춤
    }
  });
  function tsNeedsCheck() {
    try {
      return typeof dcTs !== 'undefined' && dcTs && dcTs.state === 'interactive' &&
        !(typeof turnstile !== 'undefined' && dcTs.id !== null && turnstile.getResponse(dcTs.id));
    } catch (e) { return false; }
  }
  function retryCommentOnce() {
    if (!cmtRetry.on) return;
    var f = cmtRetry.form;
    if (location.href !== cmtRetry.url || !f || !document.body.contains(f)) { stopCmtRetry(); return; }
    var ta = f.querySelector('textarea[name^="comment_memo"]');
    if (ta && !ta.value.trim()) {
      ta.value = cmtRetry.memo;
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    }
    // Cloudflare 체크박스가 뜬 상태 → 사용자가 체크할 때까지 누르지 않고 기다림 (체크되면 바로 이어서 누름)
    if (tsNeedsCheck()) {
      if (!cmtRetry.askedCheck) {
        cmtRetry.askedCheck = true;
        try { dcTs.host.scrollIntoView({ block: 'center' }); } catch (e) {}
        post('cmtretry', { state: 'check' });
      }
      clearTimeout(cmtRetry.watchdog);
      cmtRetry.timer = setTimeout(function () { cmtRetry.timer = null; retryCommentOnce(); }, 100);
      return;
    }
    cmtRetry.askedCheck = false;
    var btn = f.querySelector('button.btn-comment-write, button[type="submit"], input[type="submit"]');
    cmtRetry.tries++;
    if (btn) btn.click();
    else if (f.requestSubmit) f.requestSubmit();
    else { stopCmtRetry(); return; }
    // 디시가 Cloudflare 체크를 기다리다 보내지 않는 등 응답이 안 오면 → 25초 뒤 다시 누름
    clearTimeout(cmtRetry.watchdog);
    cmtRetry.watchdog = setTimeout(scheduleCmtRetry, 25000);
  }

  // ---------- 남의 댓글을 눌러 답글 칸이 열리면 바로 키보드 ----------
  var replyFocusTarget = null;
  // 디시는 댓글·답글을 누르면 #comment_addDiv{ch} 안에 답글 칸을 새로 만듦 (댓글 = li.comment, 답글 = li.comment-add)
  function openedReplyArea(li) {
    var ch = li && li.getAttribute('ch');
    var box = ch ? document.getElementById('comment_addDiv' + ch) : null;
    if (!box) {
      var n = li && li.nextElementSibling;
      if (n && n.classList && n.classList.contains('comment-add') && /^comment_addDiv/.test(n.id || '')) box = n;
    }
    return box ? box.querySelector('textarea[name^="comment_memo"]') : null;
  }
  function focusReply() {
    var ta = replyFocusTarget;
    if (!ta || !document.body.contains(ta)) return false;
    ta.focus();
    // 내용 칸(편집기)이면 체크 전 커서 자리로
    if (ta === tsRefocus.el && tsRefocus.range && ta.isContentEditable) {
      try { var s = window.getSelection(); s.removeAllRanges(); s.addRange(tsRefocus.range); } catch (e) {}
    }
    return document.activeElement === ta;
  }

  // ---------- Cloudflare 체크박스를 눌러 통과하면 → 쓰던 칸에 다시 커서 (키보드 다시 올림) ----------
  var tsRefocus = { el: null, range: null, prev: '' };
  function typingField(el) {
    if (!el || el.nodeType !== 1) return null;
    if (isCommentField(el) || isWriteField(el)) return el;
    var ce = el.closest && el.closest('[contenteditable="true"], [contenteditable=""]');
    return ce && isWriteField(ce) ? ce : null;
  }
  document.addEventListener('focusin', function (e) {
    var f = typingField(e.target);
    if (f) { tsRefocus.el = f; tsRefocus.range = null; }
  }, true);
  document.addEventListener('focusout', function (e) {
    if (e.target !== tsRefocus.el || !tsRefocus.el.isContentEditable) return;
    try { var s = window.getSelection(); if (s.rangeCount) tsRefocus.range = s.getRangeAt(0).cloneRange(); } catch (x) {}
  }, true);
  setInterval(function () {
    if (typeof dcTs === 'undefined' || !dcTs) return;
    var st = dcTs.state || '';
    if (tsRefocus.prev === 'interactive' && st !== 'interactive' && /^ok/.test(st)) {
      var el = tsRefocus.el;
      if (el && document.body.contains(el) && document.activeElement !== el) {
        replyFocusTarget = el;
        focusReply();
        post('wantfocus', {});
      }
    }
    tsRefocus.prev = st;
  }, 300);
  // 디시의 답글 열기(body에 걸린 click)가 끝난 뒤에 실행되도록 document의 버블 단계에서
  document.addEventListener('click', function (e) {
    if (!e.isTrusted) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    var li = t && t.closest ? t.closest('li.comment, li.comment-add') : null;
    if (!li || /^comment_addDiv/.test(li.id || '') || t.closest('form, a, button, input, textarea, .ginfo-area')) return;   // 답글 칸 자체는 제외
    var sel = window.getSelection && window.getSelection();
    if (sel && !sel.isCollapsed && String(sel).trim()) return;          // 꾹 눌러 글자 선택 중이면 제외
    var ta = openedReplyArea(li);
    if (!ta) return;
    replyFocusTarget = ta;
    focusReply();
    post('wantfocus', {});     // 앱에서 한 번 더 (iOS가 스크립트 focus로는 키보드를 안 띄우는 경우 대비)
  }, false);

  // 알림 거르기용: 그 글을 불러와 해당 댓글의 작성자(닉네임·IP·아이디)를 알려줌 (못 찾으면 null)
  function alarmAuthor(gid, no, cno) {
    // 알림의 미니 갤러리는 mi$갤ID, 인물은 pr$갤ID
    var sec = /^mi\$/.test(gid) ? 'mini' : (/^pr\$/.test(gid) ? 'person' : 'board');
    var bare = String(gid).replace(/^(mi|pr)\$/, '');
    return fetch('/' + sec + '/' + encodeURIComponent(bare) + '/' + encodeURIComponent(no), { credentials: 'include' })
      .then(function (r) { return r.ok ? r.text() : ''; })
      .then(function (html) {
        if (!html) return null;
        var d = new DOMParser().parseFromString(html, 'text/html');
        var li = d.querySelector('li[no="' + String(cno).replace(/[^0-9]/g, '') + '"]');
        if (!li) return null;
        var nickEl = li.querySelector('.nick');
        var nick = nickEl ? nickEl.textContent.replace(/\s+/g, ' ').trim() : '';
        var ipEl = li.querySelector('.blockCommentIp, .ip');
        var m = ipEl ? ipEl.textContent.match(/(\d{1,3}\.\d{1,3})/) : null;
        var idEl = li.querySelector('.blockCommentId');
        return { nick: nick, ip: m ? m[1] : '', id: idEl ? (idEl.getAttribute('data-info') || '') : '' };
      })
      .catch(function () { return null; });
  }
  function refreshComments() {
    // 댓글창이 화면 아래에 있으면(아직 댓글에 못 간 상태) 새로고침 대신 댓글창으로 이동
    var cbox = document.getElementById('comment_box');
    if (cbox && cbox.getBoundingClientRect().top > window.innerHeight * 0.5) {
      cbox.scrollIntoView({ block: 'start', behavior: 'smooth' });
      return 'scrolled';
    }
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
      if (r.closest('#dcapp-headbar')) return;   // 앱이 그린 말머리 탭은 제외
      if (r.getBoundingClientRect().height > 120) return;
      rows.push({ el: r, items: Array.prototype.slice.call(it) });
    });
    return rows;
  }
  /// 목록 종류 줄(전체/개념글/공지 + 30개)인지: 칸이 전부 '전체'·목록 종류·'N개'뿐
  var TYPE_ROW_ITEM = /^(전체|개념글|념글|공지|추천|전체글|인기글|베스트|\d+\s*개|)$/;
  function listTypeRows() {
    return tabRows().filter(function (r) {
      return r.items.some(function (a) { return LIST_TABS.test(txt(a)); }) &&
             r.items.every(function (a) { return TYPE_ROW_ITEM.test(txt(a)); });
    });
  }
  /// 갤러리 목록 위의 전체/개념글/공지 줄과 맨 위 고정 공지·개념글 줄을 숨김 (말머리 줄만 남김)
  function hideListTypeTabs() {
    listTypeRows().forEach(function (r) { r.el.classList.add('dcapp-hide'); });
    // 공지 목록 화면에서는 글들이 전부 공지 칸이라 숨기지 않음
    if (/[?&]notice=1/.test(location.search)) return;
    pinnedRows().forEach(function (el) { el.classList.add('dcapp-pinned-off'); });
    // 실베·개념 돌아가는 상자 (#recom_box1 .detail-top-concept 등) — 말머리와 글 목록 사이
    if (document.querySelector('ul.gall-detail-lst')) {
      document.querySelectorAll('.detail-top-concept, .con-child-box').forEach(function (el) { el.classList.add('dcapp-pinned-off'); });
    }   // 차단 표시가 dcapp-hide를 지울 수 있어서 따로
  }
  function headRowEl(el) {
    return tabRows().some(function (r) { return r.el.contains(el); });
  }
  /// 목록 맨 위 고정 줄 ('공지 …' / '개념 …' 한 줄짜리, 글쓴이·시간 줄 없음) — 목록 밖 별도 상자에 있을 수도 있어서 넓게 찾음
  /// 글쓴이·시간 줄(.ginfo)이 있는 진짜 글 칸 안인지 — 제목이 '실베 …', '공지 …'로 시작하는 보통 글은 숨기면 안 됨
  function inPostRow(el) {
    var li = el.closest('.gall-detail-lst li');
    while (li && !li.querySelector('.ginfo')) li = li.parentElement && li.parentElement.closest('.gall-detail-lst li');
    return !!li;
  }
  function pinnedRows() {
    var out = [];
    document.querySelectorAll('li, .detail-top-lnk, [class*="notice"], [class*="best"]').forEach(function (el) {
      if (el.closest('#dcapp-headbar') || el.closest('.comment, #comment_box, .gallview-tit-box')) return;
      if (inPostRow(el)) return;
      if (el.querySelector('.ginfo, li, textarea')) return;
      var t = txt(el);
      if (t.length > 120 || !/^(공지|개념|념글|실베)\s/.test(t)) return;
      // 같은 줄을 감싼 바깥 칸을 숨김 (안쪽 칸만 숨기면 테두리·숫자 칸이 남음)
      var box = el.closest('li');
      if (!box || box.querySelector('.ginfo') || txt(box).length > 140) box = el;
      if (out.indexOf(box) < 0) out.push(box);
    });
    // '개념' 줄은 여러 글이 돌아가며 나오는 상자(▾)라 안에 li가 여러 개 → 딱지('개념'/'공지' 글자)에서 위로 올라가며 한 줄 높이 상자를 찾음
    document.querySelectorAll('span, em, strong, i, b, div, a').forEach(function (badge) {
      if (badge.children.length || !/^(공지|개념|념글|실베)$/.test(txt(badge))) return;
      if (badge.closest('#dcapp-headbar, .comment, #comment_box, .gallview-tit-box, .dcapp-hide')) return;
      if (inPostRow(badge)) return;                   // 제목이 딱 '실베'·'공지'인 보통 글
      if (!badge.getClientRects().length) return;   // 이미 숨겨진 줄(말머리·목록 종류 줄)의 글자는 무시
      if (headRowEl(badge)) return;                   // 디시 말머리 줄의 '공지' 말머리
      var box = null;
      for (var cur = badge.parentElement; cur && cur !== document.body; cur = cur.parentElement) {
        if (cur.querySelector('.ginfo, textarea, #dcapp-headbar')) break;
        var h = cur.getBoundingClientRect().height;
        if (h > 90) break;
        if (cur.matches('ul.gall-detail-lst, .gall-detail-lst')) break;
        box = cur;
      }
      if (box && txt(box).length < 300 && out.indexOf(box) < 0) out.push(box);
    });
    return out;
  }

  // ---------- 앱 말머리 탭 (디시 말머리 줄을 숨기고 새로 그림) ----------
  function headRow() {
    var rows = tabRows().filter(function (r) {
      return r.items.some(function (a) { return !TYPE_ROW_ITEM.test(txt(a)); });
    });
    // 가장 안쪽 줄 (다른 줄을 품지 않은 것) — 말머리 칸 목록
    var inner = rows.filter(function (r) {
      return !rows.some(function (o) { return o !== r && r.el.contains(o.el); });
    })[0] || null;
    if (!inner) return null;
    // 숨기고 그 자리에 앱 탭을 넣을 곳은 그 줄을 감싼 가장 바깥 칸 (안쪽에 넣으면 디시 슬라이더의 여백·높이·밑줄에 걸려 모양이 깨짐)
    var outer = inner.el;
    rows.forEach(function (r) {
      if (r.el.contains(inner.el) && r.el.contains(outer) && !r.el.querySelector('ul.gall-detail-lst, #dcapp-headbar')) outer = r.el;
    });
    return { el: inner.el, items: inner.items, box: outer };
  }
  function headIdOf(url) {
    try { return new URL(url, location.href).searchParams.get('headid') || ''; } catch (e) { return ''; }
  }
  function buildHeadBar() {
    if (!document.querySelector('ul.gall-detail-lst')) return;
    var row = headRow();
    if (!row) return;
    var tabs = [];
    row.items.forEach(function (a) {
      var name = txt(a);
      if (!name || name.length > 12) return;
      var url = name === '전체' ? '' : headHref(a);
      if (name !== '전체' && !url) return;
      if (tabs.some(function (t) { return t.name === name; })) return;
      tabs.push({ name: name, url: url, el: a });
    });
    if (tabs.length < 2) return;
    row.box.classList.add('dcapp-hide');
    var cur = new URLSearchParams(location.search).get('headid') || '';
    var sig = tabs.map(function (t) { return t.name; }).join('|') + '#' + cur;
    var bar = document.getElementById('dcapp-headbar');
    if (bar && bar.getAttribute('data-sig') === sig && bar.nextSibling === row.box) return;
    if (!bar) {
      bar = document.createElement('div');
      bar.id = 'dcapp-headbar';
    }
    bar.setAttribute('data-sig', sig);
    bar.innerHTML = '';
    tabs.forEach(function (t) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = t.name;
      var on = t.name === '전체' ? !cur : (cur && headIdOf(t.url) === cur);
      if (on) b.className = 'on';
      b.addEventListener('click', function () {
        if (on) return;
        if (t.name === '전체') {
          // 디시 '전체' 칸이 있으면 그걸 누르고, 없으면 주소에서 말머리만 뺌
          var h = t.el.getAttribute && (t.el.getAttribute('href') || '');
          if (t.el.getAttribute && (t.el.getAttribute('onclick') || /^\s*javascript:/i.test(h))) { t.el.click(); return; }
          var u = new URL(location.href);
          u.searchParams.delete('headid'); u.searchParams.delete('page');
          location.href = u.href;
          return;
        }
        location.href = t.url;
      });
      bar.appendChild(b);
    });
    row.box.parentNode.insertBefore(bar, row.box);
    var sel = bar.querySelector('button.on');
    if (sel && sel.offsetLeft > bar.clientWidth - 60) bar.scrollLeft = sel.offsetLeft - 16;
  }
  /// 갤러리 공지 목록 열기 (숨긴 '공지' 탭의 주소, 없으면 지금 주소에 notice=1)
  function openNotice() {
    var a = null;
    listTypeRows().some(function (r) {
      a = r.items.filter(function (x) { return txt(x) === '공지'; })[0] || null;
      return !!a;
    });
    var h = a && a.getAttribute && (a.getAttribute('href') || '');
    if (h && !/^\s*(#|javascript:)/i.test(h)) { location.href = a.href; return 'nav'; }
    if (a) { a.click(); return 'clicked'; }
    if (!/\/(board|mini|person)\//.test(location.pathname)) return 'none';
    var u = new URL(location.href);
    u.pathname = u.pathname.replace(/^(\/(board|mini|person)\/[^\/]+).*$/, '$1');
    ['page', 'headid', 'recommend', 'serval', 's_type', 's_pos', 's_keyword'].forEach(function (k) { u.searchParams.delete(k); });
    u.searchParams.set('notice', '1');
    location.href = u.href;
    return 'built';
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

  // ---------- 디시 '외부 링크 이동' 안내 끄기 (앱이 대신 물어보고 기본 브라우저로 엶) ----------
  // 디시 설정의 '외부 링크 경고'와 같은 쿠키(m_dcinside_externalLink=OFF)
  try {
    if (!/(^|;\s*)m_dcinside_externalLink=OFF/.test(document.cookie)) {
      document.cookie = 'm_dcinside_externalLink=OFF; path=/; domain=.dcinside.com; max-age=31536000';
    }
  } catch (e) {}

  // ---------- 앱 글쓰기 화면 ↔ 디시 글쓰기 양식 ----------
  // 앱 화면에 필요한 정보: 유동인지, 저장된 닉네임·비번, 말머리, 코드(캡차), 갤러리 이름
  async function writeInfo() {
    if (!isWritePage()) return null;
    for (var t = 0; t < 20 && !document.getElementById('subject'); t++) await sleep(250);
    var name = document.getElementById('name'), pw = document.getElementById('password');
    var heads = [];
    document.querySelectorAll('#swiper-headtxt li[data-no], .malwrt-lst li[data-no]').forEach(function (li) {
      var a = li.querySelector('a');
      var oc = a && a.getAttribute('onclick') || '';
      if (!/head_select/.test(oc)) return;                       // 관리자 전용 말머리 등은 못 고름
      heads.push({ no: String(li.getAttribute('data-no')), name: txt(a) });
    });
    var ht = document.getElementById('headtext');
    var cap = document.getElementById('dcblock'), capImg = null;
    if (cap) {
      var im = document.querySelector('.code-img img');
      if (im && im.src) {
        try {
          var blob = await (await fetch(im.src, { credentials: 'include' })).blob();
          capImg = await new Promise(function (res) { var r = new FileReader(); r.onload = function () { res(r.result); }; r.readAsDataURL(blob); });
        } catch (e) {}
      }
    }
    var gname = document.querySelector('.gall-tit-lnk, .gall-tit');
    // 글 수정 화면: 원래 내용을 글자 칸 / 그대로 둘 칸(사진·디시콘·동영상 등)으로 나눠 앱에 넘김
    var mode = (document.getElementById('mode') || {}).value || '';
    var blocks = [];
    if (mode === 'modify') {
      var ed = null;
      for (var w = 0; w < 20 && !ed; w++) { ed = document.querySelector('.note-editable'); if (!ed) await sleep(250); }
      if (ed) blocks = editorBlocks(ed);
    }
    var subjEl = document.getElementById('subject');
    return {
      mode: mode, title: subjEl ? subjEl.value : '', blocks: blocks,
      ok: !!document.getElementById('subject'),
      anon: !!(name || pw),
      nick: name ? name.value : '', nickLocked: !!(name && (name.disabled || name.readOnly)),
      pw: pw ? pw.value : '',
      heads: heads, head: ht ? String(ht.value) : '',
      captcha: !!cap, captchaImg: capImg,
      gallery: gname ? txt(gname).trim() : ''
    };
  }
  async function refreshCaptcha() {
    var r = document.getElementById('captcha_reload');
    if (r) r.click();
    await sleep(700);
    var info = await writeInfo();
    return info ? info.captchaImg : null;
  }
  // 디시 편집기 내용 → 글자 칸 / 그대로 둘 칸(사진·디시콘·동영상·유튜브·투표 등)
  function mediaLabel(n) {
    var html = n.outerHTML || '';
    var media = n.matches('img, iframe, video, embed, object') ? n : n.querySelector('img, iframe, video, embed, object');
    var src = media ? (media.getAttribute('src') || media.getAttribute('data-src') || '') : '';
    if (/dccon/i.test(src) || /written_dccon/.test(html)) return { label: '디시콘', src: src };   // 미리보기용 주소
    if (/youtube|youtu\.be|ytimg/i.test(src + html)) {
      // 미리보기: 영상 ID로 유튜브 썸네일 주소 만들기
      var m = (src + ' ' + html).match(/(?:embed\/|watch\?v=|youtu\.be\/|\/vi\/|[?&]v=)([A-Za-z0-9_-]{11})/);
      return { label: '유튜브', src: m ? 'https://i.ytimg.com/vi/' + m[1] + '/hqdefault.jpg' : '' };
    }
    if (/vote|poll/i.test(src + ' ' + (n.className || '') + html.slice(0, 300))) return { label: '투표', src: '' };
    if (/movie|video/i.test(src + html.slice(0, 300)) || (media && media.tagName === 'VIDEO')) {
      // 디시가 만든 동영상 칸에 썸네일 그림이 있으면 그걸로 미리보기
      var th = n.querySelector('img') || (media && media.getAttribute('poster') ? { src: media.getAttribute('poster') } : null);
      return { label: '동영상', src: th && th.src ? th.src : '' };
    }
    if (media && media.tagName === 'IMG') return { label: '사진', src: src };
    return { label: '첨부', src: '' };
  }
  function editorBlocks(ed) {
    var blocks = [], textBuf = [];
    var flush = function () { if (textBuf.length) { blocks.push({ t: 'text', text: textBuf.join('\n') }); textBuf = []; } };
    Array.prototype.forEach.call(ed.childNodes, function (n) {
      if (n.nodeType === 3) { if (n.textContent.trim()) textBuf.push(n.textContent.trim()); return; }
      if (n.nodeType !== 1) return;
      var media = n.matches('img, iframe, video, embed, object') ? n : n.querySelector('img, iframe, video, embed, object');
      var special = media || /vote|poll|movie|block/i.test(n.className || '');
      if (special && (media || !(n.innerText || '').trim() || /vote|poll|movie/i.test(n.className || ''))) {
        flush();
        var m = mediaLabel(n);
        blocks.push({ t: 'raw', html: n.outerHTML, src: m.src, label: m.label });
        return;
      }
      var t = (n.innerText || n.textContent || '').replace(/\u00a0/g, ' ');
      textBuf.push(t.replace(/\n$/, ''));
    });
    flush();
    return blocks;
  }

  // 동영상·디시콘·유튜브·투표: 디시 기능을 그대로 써서 편집기에 넣게 한 뒤, 넣은 것을 앱 글쓰기로 가져옴
  function editorEl() { return document.querySelector('.note-editable') || document.getElementById('textbox'); }
  function clearEditor() {
    var $ = window.jQuery, ed = $ && $('#textbox');
    if (ed && ed.length && ed.summernote) ed.summernote('code', ''); else { var b = editorEl(); if (b) b.innerHTML = ''; }
  }
  function openWebFeature(kind) {
    if (!isWritePage()) return 'notwrite';
    clearEditor();                                  // 앱 글쓰기 내용은 앱이 들고 있음 → 편집기는 비워 두고 새로 넣은 것만 가져감
    try {
      var $ = window.jQuery, ed = $ && $('#textbox');
      if (ed && ed.summernote) { ed.summernote('focus'); ed.summernote('editor.saveRange'); }
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    } catch (e) {}
    try {
      if (kind === 'video') { var b = document.getElementById('upload_mov'); if (!b) return 'nofeature'; b.click(); }
      else if (kind === 'dccon') { if (typeof window.show_dccon !== 'function') return 'nofeature'; window.show_dccon('writeContent'); }
      else if (kind === 'youtube') { if (typeof window.youtube_search_on !== 'function') return 'nofeature'; window.youtube_search_on(); }
      else if (kind === 'vote') { if (typeof window.show_vote !== 'function') return 'nofeature'; window.show_vote(1); }
      else return 'nofeature';
    } catch (e) { return 'error:' + e.message; }
    return 'opened';
  }
  // ---------- 디시콘 바로 넣기 (앱 화면에서 고름) ----------
  // 디시 웹이 쓰는 그대로 목록을 받아(getDccon / getDccon_tab) 앱에 넘기고, 고르면 디시 방식(dccon_chk + insertDccon)으로 칸을 만듦
  function dcconAjax(url, data) {
    return new Promise(function (res) {
      if (!window.jQuery) return res('');
      window.jQuery.ajax({ type: 'POST', url: url, data: data || {}, dataType: 'html' })
        .done(function (h) { res(h || ''); }).fail(function () { res(''); });
    });
  }
  function parseDcconItems(root) {
    var out = [];
    root.querySelectorAll('a[data-dccon-detail][data-dccon-package]').forEach(function (a) {
      var im = a.querySelector('img');
      var src = im ? (im.getAttribute('data-src') || im.getAttribute('data-original') || '') : '';
      if (/dccon_loading/.test(src)) src = '';
      out.push({ pkg: String(a.getAttribute('data-dccon-package')), detail: String(a.getAttribute('data-dccon-detail')),
                 src: src, alt: im ? (im.getAttribute('alt') || '') : '' });
    });
    return out;
  }
  var dcconBoxes = {};
  async function dcconTabs() {
    var html = typeof window.getDccon === 'function'
      ? await new Promise(function (res) { window.getDccon({}).done(function (h) { res(h || ''); }).fail(function () { res(''); }); })
      : await dcconAjax('/dccon/getDccon', {});
    if (!html) return null;
    var d = new DOMParser().parseFromString('<div>' + html + '</div>', 'text/html');
    var tabs = [], current = '';
    d.querySelectorAll('#swiper-dccon-tab li a[onclick*="getDccon_tab"]').forEach(function (a) {
      var m = (a.getAttribute('onclick') || '').match(/getDccon_tab\(this,\s*'([^']*)'(?:,\s*'([^']*)')?/);
      if (!m) return;
      var im = a.querySelector('img');
      var thumb = im ? (im.getAttribute('data-original') || im.getAttribute('src') || '') : '';
      tabs.push({ idx: m[1], folder: m[2] || '', name: im ? (im.getAttribute('alt') || '') : '', thumb: thumb });
      if (a.closest('li').classList.contains('on')) current = m[1];
    });
    dcconBoxes = {};
    d.querySelectorAll('[id^="d_box_"]').forEach(function (box) { dcconBoxes[box.id.replace('d_box_', '')] = parseDcconItems(box); });
    return { tabs: tabs, current: current, items: dcconBoxes[current] || [] };
  }
  async function dcconItems(idx, folder) {
    if (dcconBoxes[idx]) return dcconBoxes[idx];
    var data = { idx: idx };
    if (folder) data.folderName = folder;
    var html = await dcconAjax('/dccon/getDccon_tab', data);
    if (!html) return [];
    var d = new DOMParser().parseFromString('<div>' + html + '</div>', 'text/html');
    dcconBoxes[idx] = parseDcconItems(d);
    return dcconBoxes[idx];
  }
  // 고른 디시콘을 디시 방식 그대로 편집기에 넣어 칸(HTML)을 만들고 가져옴
  function dcconMake(pkg, detail) {
    if (typeof window.chk_dccon_insert !== 'function') return { error: 'nofeature' };
    var chk = window.chk_dccon_insert(pkg, detail);
    if (!chk || chk.result !== 'ok') return { error: 'denied' };
    clearEditor();
    try {
      window.dcconMode = 'writeContent';
      var $ = window.jQuery;
      $('#textbox').summernote('focus');
      $('#textbox').summernote('insertDccon', [chk], 1, '');
      $('.written_dccon:not(.txtdccon)').addClass('dccon-img');
    } catch (e) { return { error: 'insert:' + e.message }; }
    var got = collectWebInserts();
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    return { blocks: got };
  }

  function collectWebInserts() {
    var ed = editorEl();
    if (!ed) return [];
    var out = editorBlocks(ed).filter(function (b) { return b.t === 'raw' || (b.text || '').trim(); });
    clearEditor();
    return out;
  }
  function escHTML(t) { return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  var nativeWait = null;
  // 앱에서 쓴 내용을 디시 양식에 채우고 등록 (사진은 업로드 칸에 넣어 디시가 올리게 한 뒤 글 앞쪽에)
  async function nativeSubmit(p) {
    if (!isWritePage()) return 'notwrite';
    var $ = window.jQuery;
    var name = document.getElementById('name'), pw = document.getElementById('password');
    if (name && p.nick != null && !name.disabled && !name.readOnly) setField(name, p.nick);
    if (pw && p.pw != null) setField(pw, p.pw);
    var cap = document.getElementById('dcblock');
    if (cap && p.captcha != null) setField(cap, p.captcha);
    // 사진 크기: 디시 '이미지 크기 일괄 설정'과 같은 칸 (기본 850px로 줄어드는 것 방지)
    if (p.imgSize) {
      try { localStorage.setItem('imgSizeSetting', p.imgSize); } catch (e) {}
      var isz = document.getElementById('imgSize');
      if (isz) isz.value = p.imgSize;
    }
    var ht = document.getElementById('headtext');
    if (ht && p.head != null && p.head !== '') {
      if (typeof window.head_select === 'function') window.head_select(p.head); else ht.value = p.head;
      document.querySelectorAll('#swiper-headtxt li[data-no]').forEach(function (li) { li.classList.toggle('on', String(li.getAttribute('data-no')) === String(p.head)); });
    }
    var subj = document.getElementById('subject');
    if (!subj) return 'nofield';
    setField(subj, p.title || '');
    var ed = $ && $('#textbox');
    var useSN = !!(ed && ed.length && ed.summernote);
    // 디시는 summernote 편집기를 써서 #textbox는 숨겨지고 실제 내용은 .note-editable에 있음
    var box = document.querySelector('.note-editable') || document.getElementById('textbox');
    if (useSN) ed.summernote('code', ''); else if (box) box.innerHTML = '';
    var blocks = p.blocks || [];
    var imgs = blocks.filter(function (b) { return b.t === 'image'; });
    // 사진: 한꺼번에 업로드 칸에 넣어 디시가 올리게 함 (디시가 편집기에 넣은 사진 칸을 나중에 순서대로 다시 배치)
    if (imgs.length) {
      var input = null;
      for (var t = 0; t < 15 && !input; t++) { input = document.getElementById('upload') || findFileInput(); if (!input) await sleep(300); }
      if (!input) return 'noinput';
      var before = box ? box.querySelectorAll('img').length : 0;
      try {
        var dt = new DataTransfer();
        imgs.forEach(function (im, i) {
          var bin = atob(im.b64), bytes = new Uint8Array(bin.length);
          for (var k = 0; k < bin.length; k++) bytes[k] = bin.charCodeAt(k);
          dt.items.add(new File([bytes], 'image_' + Date.now() + '_' + i + '.' + (im.ext || 'jpg'), { type: im.mime || 'image/jpeg' }));
        });
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      } catch (e) { return 'imgerror:' + e.message; }
      // 디시가 다 올리고 본문에 넣을 때까지 기다림 (최대 60초)
      var okImgs = false;
      for (var w = 0; w < 240; w++) {
        await sleep(250);
        if (box && box.querySelectorAll('img').length >= before + imgs.length) { okImgs = true; break; }
      }
      if (!okImgs) return 'imgtimeout';
    }
    // 디시가 만든 사진 칸(업로드 순서대로)
    var imgHTML = [];
    if (box) box.querySelectorAll('img').forEach(function (im) {
      var blk = im.closest('div.block') || im;
      if (box.contains(blk) && imgHTML.indexOf(blk.outerHTML) < 0) imgHTML.push(blk.outerHTML);
    });
    // 앱에서 정한 순서대로 다시 짜기: 글자 칸은 줄마다 문단, 사진 칸은 디시가 만든 칸 그대로
    var html = '', k = 0;
    blocks.forEach(function (b) {
      if (b.t === 'raw') {
        html += b.html;                                   // 수정: 원래 있던 사진·디시콘 등은 그대로
      } else if (b.t === 'image') {
        if (k < imgHTML.length) html += imgHTML[k++] + '<p><br></p>';
      } else {
        html += b.html ? b.html : String(b.text || '').split('\n').map(function (l) { return l.length ? '<p>' + escHTML(l) + '</p>' : '<p><br></p>'; }).join('');
      }
    });
    while (k < imgHTML.length) html += imgHTML[k++] + '<p><br></p>';   // 혹시 남은 사진
    if (useSN) ed.summernote('code', html);
    else if (box) box.innerHTML = html;
    if (box) box.dispatchEvent(new Event('input', { bubbles: true }));
    // Cloudflare 체크박스가 떠 있으면 → 앱이 디시 화면을 보여주고, 체크되면 여기서 이어서 등록
    if (tsNeedsCheck()) {
      clearInterval(nativeWait);
      try { dcTs.host.scrollIntoView({ block: 'center' }); } catch (e) {}
      nativeWait = setInterval(function () {
        if (tsNeedsCheck()) return;
        clearInterval(nativeWait); nativeWait = null;
        post('nativewrite', { state: 'resumed' });
        if (typeof window.write_submit === 'function') window.write_submit(); else submitWrite();
      }, 200);
      return 'needcheck';
    }
    if (typeof window.write_submit === 'function') window.write_submit(); else submitWrite();
    return 'submitted';
  }

  // ---------- 구조 진단 ----------
  function diagnose() {
    var out = ['script: v135-fontdefaults', 'URL: ' + location.href, 'UA: ' + navigator.userAgent];
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
    out.push('--- 알림 원본 (마지막으로 받은 것) ---');
    var alarmRaw = window.__dcappAlarmRaw;
    if (!alarmRaw) { try { alarmRaw = sessionStorage.getItem('dcappAlarmRaw'); } catch (e) {} }
    out.push(alarmRaw || '(아직 없음 — 알림을 하나 받은 뒤 다시 진단해주세요)');
    out.push('--- 알림·댓글 등록 요청 (최근) ---');
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
    out.push('--- 고정 줄 (공지/개념) ---');
    pinnedRows().slice(0, 4).forEach(function (el) {
      out.push((el.parentElement ? el.parentElement.tagName + '.' + clsOf(el.parentElement) + ' > ' : '') + el.outerHTML.replace(/\s+/g, ' ').slice(0, 400));
    });
    Array.prototype.filter.call(document.querySelectorAll('body *'), function (el) {
      return /^공지\s*아이패드|^공지\s/.test(txt(el)) && txt(el).length < 80 && el.children.length < 6;
    }).slice(0, 4).forEach(function (el) {
      out.push('  후보 ' + el.tagName + '.' + clsOf(el) + ' / 부모 ' + (el.parentElement ? el.parentElement.tagName + '.' + clsOf(el.parentElement) : '') + ' : ' + el.outerHTML.replace(/\s+/g, ' ').slice(0, 300));
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
    out.push('유동 칸: ' + anonFields().map(function (f) {
      return f.kind + '=' + f.el.tagName + '#' + (f.el.id || '') + '[name=' + (f.el.name || '') + '] 값' + (f.el.value ? '있음' : '없음') + (f.el.value === 'ㅇㅇ' ? '(ㅇㅇ)' : '') + (f.el.readOnly ? ' 읽기전용' : '') + (f.el.disabled ? ' 비활성' : '');
    }).join(' / ') + ' | comment_nick: ' + (function () {
      var n = document.getElementById('comment_nick');
      if (!n) return '(없음)';
      return n.outerHTML.slice(0, 200) + ' disabled=' + n.disabled + ' readOnly=' + n.readOnly + ' 팝업안=' + !!(n.closest && n.closest('.layer-center-popup'));
    })() + ' | 버튼: ' + ['delete_nickname_btn', 'use_nickname_btn'].map(function (id) {
      var b = document.getElementById(id);
      return b ? b.outerHTML.replace(/\s+/g, ' ').slice(0, 160) + ' vis=' + visible(b) : id + '(없음)';
    }).join(' , ') + ' | 채우기 기록: ' + (anonLog.join(' → ') || '(없음)') + ' | 앱에 저장: 닉' + ((cfg.anon || {}).nick ? '있음' : '없음') + ' 비번' + ((cfg.anon || {}).pw ? '있음' : '없음'));
    var ml = manageLogLink();
    out.push('관리 내역 링크: ' + (ml ? ml.outerHTML.replace(/\s+/g, ' ').slice(0, 250) : '(없음)'));
    // 광고로 보이는 것 (차단 규칙을 늘릴 때 참고): iframe 주소, id·class에 ad/banner/광고가 든 큰 칸
    out.push('--- 페이지 맨 위 (화면 위쪽 200px 안의 칸) ---');
    Array.prototype.filter.call(document.querySelectorAll('body *'), function (el) {
      var r = el.getBoundingClientRect();
      return r.top < 200 && r.bottom > 0 && r.height > 20 && r.width > 200 && visible(el) && el.children.length < 15;
    }).slice(0, 20).forEach(function (el) {
      var r = el.getBoundingClientRect(), cs = getComputedStyle(el);
      out.push(el.tagName + '#' + (el.id || '') + '.' + clsOf(el).slice(0, 50) + ' y=' + Math.round(r.top) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height) +
               ' bg=' + cs.backgroundColor + ' pad=' + cs.paddingTop + ' 글자=' + txt(el).slice(0, 20));
    });
    var hb = document.getElementById('dcapp-headbar');
    if (hb) {
      out.push('--- 말머리 탭 주변 ---');
      var chain = [];
      for (var c = hb; c && c !== document.body; c = c.parentElement) {
        var cr = c.getBoundingClientRect(), ccs = getComputedStyle(c);
        chain.push(c.tagName + '.' + clsOf(c).slice(0, 40) + ' x=' + Math.round(cr.left) + ' w=' + Math.round(cr.width) + ' pad=' + ccs.padding + ' mar=' + ccs.margin + ' bd=' + ccs.borderTopWidth + '/' + ccs.borderBottomWidth + ' ' + ccs.borderBottomColor);
      }
      out.push('조상: ' + chain.join('  <  '));
      var sib = [];
      for (var n = hb.parentElement ? hb.parentElement.firstElementChild : null; n; n = n.nextElementSibling) {
        sib.push(n.tagName + '#' + (n.id || '') + '.' + clsOf(n).slice(0, 40) + (getComputedStyle(n).display === 'none' ? '(숨김)' : ''));
      }
      out.push('형제: ' + sib.join(' , '));
      var lst = document.querySelector('ul.gall-detail-lst');
      if (lst) {
        var chain2 = [];
        for (var c2 = lst; c2 && c2 !== document.body && chain2.length < 6; c2 = c2.parentElement) {
          var r2 = c2.getBoundingClientRect(), s2 = getComputedStyle(c2);
          chain2.push(c2.tagName + '.' + clsOf(c2).slice(0, 40) + ' x=' + Math.round(r2.left) + ' y=' + Math.round(r2.top) + ' pad=' + s2.padding + ' mar=' + s2.margin + ' bdT=' + s2.borderTopWidth + ' ' + s2.borderTopColor);
        }
        out.push('글 목록: ' + chain2.join('  <  '));
        var prev = [];
        for (var p2 = lst.previousElementSibling; p2 && prev.length < 5; p2 = p2.previousElementSibling) {
          var r3 = p2.getBoundingClientRect(), s3 = getComputedStyle(p2);
          prev.push(p2.tagName + '#' + (p2.id || '') + '.' + clsOf(p2).slice(0, 40) + ' ' + Math.round(r3.width) + 'x' + Math.round(r3.height) + ' disp=' + s3.display + ' bd=' + s3.borderTopWidth + '/' + s3.borderBottomWidth);
        }
        out.push('목록 앞 형제: ' + prev.join(' , '));
        var li0 = lst.querySelector(':scope > li:not(.dcapp-pinned-off):not(.dcapp-hide)');
        if (li0) { var s4 = getComputedStyle(li0); out.push('첫 글 칸: ' + li0.outerHTML.replace(/\s+/g, ' ').slice(0, 150) + ' bdT=' + s4.borderTopWidth + ' ' + s4.borderTopColor + ' mar=' + s4.margin); }
      }
    }
    out.push('--- 광고 후보 ---');
    Array.prototype.forEach.call(document.querySelectorAll('iframe'), function (f) {
      var r = f.getBoundingClientRect();
      out.push('iframe ' + Math.round(r.width) + 'x' + Math.round(r.height) + ' src=' + (f.getAttribute('src') || '').slice(0, 120) + ' #' + (f.id || '') + '.' + clsOf(f));
    });
    Array.prototype.filter.call(document.querySelectorAll('div, section, aside, li, a'), function (el) {
      var k = ((el.id || '') + ' ' + clsOf(el)).toLowerCase();
      if (!/(^|[\s_-])(ad|ads|adv|advert|banner|bnr|sponsor|promotion|powerlink)([\s_-]|\d|$)|광고/.test(k)) return false;
      var r = el.getBoundingClientRect();
      return r.width > 80 && r.height > 30;
    }).slice(0, 25).forEach(function (el) {
      var r = el.getBoundingClientRect();
      out.push(el.tagName + '#' + (el.id || '') + '.' + clsOf(el).slice(0, 60) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height) + ' vis=' + visible(el));
    });
    var mineLi = document.querySelector('li.comment.dcapp-mine');
    if (mineLi) {
      var cs = getComputedStyle(mineLi), ca = getComputedStyle(mineLi, '::before');
      out.push('내 댓글 칸 스타일: bg=' + cs.backgroundColor + ' img=' + cs.backgroundImage.slice(0, 60) + ' shadow=' + cs.boxShadow +
               ' border=' + cs.borderLeft + ' / ' + cs.borderTop + ' before=' + ca.content + ' ' + ca.backgroundColor +
               ' 부모 bg=' + getComputedStyle(mineLi.parentElement).backgroundColor + ' 보통 댓글 bg=' + normalCommentBg() +
               ' | 자식: ' + Array.prototype.map.call(mineLi.children, function (c) { return c.tagName + '.' + clsOf(c) + ' bg=' + getComputedStyle(c).backgroundColor; }).join(', '));
    }
    out.push('textareas: ' + Array.prototype.map.call(document.querySelectorAll('textarea'), function (t) {
      return '#' + (t.id || '') + '.' + clsOf(t) + ' h=' + Math.round(t.getBoundingClientRect().height) + ' cmt=' + isCommentField(t);
    }).join(' / '));
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
    setConfig: function (c) {
      cfg = c || {};
      // 탭해서 펼쳐 본 글도 차단 설정이 바뀌면 다시 접히게 (펼친 뒤 다시 차단했을 때 바로 가려지도록)
      document.querySelectorAll('[data-dcapp-revealed]').forEach(function (el) { el.removeAttribute('data-dcapp-revealed'); });
      clearSelection();
      apply();
      return true;
    },
    clearSelection: function () { clearSelection(); return true; },
    loginState: loginState,
    openManageLog: openManageLog,
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
    textSelecting: textSelecting,
    refreshComments: refreshComments,
    postAction: postAction,
    alarmAuthor: alarmAuthor,
    moveWriteFocus: moveWriteFocus,
    focusReply: focusReply,
    headTabs: headTabs,
    openNotice: openNotice,
    focusTitle: focusTitle,
    submitWrite: submitWrite,
    writeInfo: writeInfo,
    refreshCaptcha: refreshCaptcha,
    nativeSubmit: nativeSubmit,
    setReadPosts: setReadPosts,
    setListFilter: setListFilter,
    articleIdentity: articleIdentity,
    openWebFeature: openWebFeature,
    collectWebInserts: collectWebInserts,
    dcconTabs: dcconTabs,
    dcconItems: dcconItems,
    dcconMake: dcconMake,
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
  var RE = /alarm|noti|push|alim|bell|memo|recv|message|comment-write|ts_state/i;
  // 댓글·글 등록 요청에 실린 Cloudflare 체크 상태만 뽑기 (비밀번호 등 다른 값은 안 뽑음)
  function tsSummary(body) {
    if (!body || body.indexOf('ts_state') < 0) return '';
    try {
      var q = new URLSearchParams(body);
      return '  <TS state=' + (q.get('ts_state') || '') +
        ' token=' + ((q.get('cf-turnstile-response') || '').length ? 'O' : 'X') +
        ' focus_ms=' + (q.get('ts_focus_ms') || '') + ' token_ms=' + (q.get('ts_token_ms') || '') + '>';
    } catch (e) { return ''; }
  }
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
      add('xhr', info.m, info.u + tsSummary(reqBody) + (reqBody ? '  <BODY ' + reqBody.slice(0, 200) + '>' : '') + (info.h ? '  <H' + info.h + '>' : ''), x.status, text);
      // 댓글 등록 결과 → content 스크립트(429 자동 재등록)로
      try {
        if (/\/ajax\/comment-write/.test(String(info.u))) {
          window.dispatchEvent(new CustomEvent('dcapp-cmtwrite', { detail: { status: x.status, body: reqBody, text: text } }));
        }
      } catch (e) {}
      // 댓글 등록 요청이 끝남 → 댓글 쓰는 동안 꺼 둔 광고 차단을 다시 켜도록
      try {
        if (/\/ajax\/comment-write/.test(String(info.u))) {
          setTimeout(function () { window.webkit.messageHandlers.dcapp.postMessage({ type: 'cmtdone', status: x.status }); }, 0);
        }
      } catch (e) {}
      // 댓글 등록이 429(Too Many Attempts)로 막히면 → 앱이 쓰던 내용을 복사
      try {
        if (x.status === 429 && /\/ajax\/comment-write/.test(String(info.u)) && reqBody) {
          var q429 = new URLSearchParams(reqBody);
          window.webkit.messageHandlers.dcapp.postMessage({ type: 'cmt429', memo: q429.get('comment_memo') || '',
                                                             mode: q429.get('mode') || '', reply: q429.get('comment_no') || '' });
        }
      } catch (e) {}
      // 디시 알림(내 글·댓글에 달린 댓글 등) → 앱의 알림 탭으로 전달
      try {
        if (/\/alarm\/notification(\?|$)/.test(String(info.u)) && text) {
          // 진단용: 알림 원본 (다른 페이지로 옮겨도 남게 sessionStorage에도)
          if (/"data"\s*:\s*\[\s*\{/.test(text)) {
            window.__dcappAlarmRaw = new Date().toISOString().slice(11, 19) + ' ' + text.slice(0, 3000);
            try { sessionStorage.setItem('dcappAlarmRaw', window.__dcappAlarmRaw); } catch (e) {}
          }
          var j = JSON.parse(text);
          if (j && j.result && j.data && j.data.length) {
            window.webkit.messageHandlers.dcapp.postMessage({ type: 'alarms', items: j.data });
          }
        }
      } catch (e) {}
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
