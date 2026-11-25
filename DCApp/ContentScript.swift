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

  // ---------- 느린 연결에서 댓글 등록이 끊기지 않게 ----------
  // 디시 댓글 등록(jQuery ajax)은 timeout 5초로 걸려 있는데, 이 제한은 XHR의 timeout 속성이 아니라 jQuery 자체 타이머가 건다
  // → 등록 요청(/ajax/comment-write)만 제한 시간을 20초로 늘림 (디시가 Cloudflare 확인을 기다리는 최대 시간 20초와 맞춤)
  (function () {
    var jq = window.jQuery;
    if (!jq || !jq.ajaxPrefilter || jq.__dcappPre) return;
    jq.__dcappPre = true;
    jq.ajaxPrefilter(function (o) {
      if (o && o.timeout > 0 && o.timeout < 20000 && /\/ajax\/(comment-write|access)/.test(String(o.url || ''))) o.timeout = 20000;
    });
  })();

  var cfg = window.__DCAPP_CONFIG__ || {};
  var voteLast = 'up';   // 마지막으로 누른 추천(up)·비추천(down) — 코드 확인 버튼·Enter가 이것을 다시 누름
  var voteWait = null;   // 누른 뒤 숫자가 바뀌는지 기다리는 추천·비추천 (성공하면 코드 상자를 접음)
  var runtimeImg = {};   // 사진 생김새(해시)가 차단한 사진과 같다고 알아낸 키 (페이지마다 새로, setConfig에서 비움)
  var imgChecked = {};   // 생김새 확인을 이미 앱에 요청한 키
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
      // 디시가 조회 수에 따라 붙이는 '디시앱 설치' 배너(목록 맨 아래·댓글 쪽 li)와 30회째 하단 팝업 — 광고 차단과 무관하게 항상 숨김
      '.app-info-ban{display:none!important}',
      '#app_down_pop{display:none!important}',
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
      '#dcapp-headbar{display:flex;gap:0;overflow:visible;padding:0 6px;margin:0;width:auto;background:#fff;border-bottom:1px solid rgba(0,0,0,.06)}',
      '#dcapp-headbar::-webkit-scrollbar{display:none}',
      '#dcapp-headbar .dcapp-hfix{display:flex;align-items:center;flex:0 0 auto}',
      '#dcapp-headbar .dcapp-hscroll{display:flex;align-items:center;flex:1 1 auto;min-width:0;overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:none}',
      '#dcapp-headbar .dcapp-hscroll::-webkit-scrollbar{display:none}',
      'html.darkmode #dcapp-headbar{background:#272729;border-bottom-color:rgba(255,255,255,.08)}',
      'html.darkmode #dcapp-headbar button{color:#ddd}',
      'html.darkmode #dcapp-headbar button.on{color:#a9b4f0;background:rgba(169,180,240,.16)}',
      // 말머리 탭: 고른 탭은 둥근 알약 배경으로 표시 (밑줄 없음)
      '#dcapp-headbar button{flex:0 0 auto;border:0;margin:6px 2px;padding:6px 13px;border-radius:999px;font-size:14px;line-height:1.2;font-weight:400;color:#222;background:transparent;-webkit-appearance:none}',
      '#dcapp-headbar button.on{color:#3b4890;font-weight:600;background:rgba(59,72,144,.10)}',
      // 글 목록 한 줄: 글자 글 아이콘은 빼고(사진 글만 아이콘), 정보 줄은 닉네임·조회·추천 → 오른쪽 끝에 말머리·시간
      'ul.gall-detail-lst > li.dcapp-filtered{display:none!important}',
      // 글자 글은 아이콘 자리(왼쪽 여백)도 없애고, 맨 끝으로 옮긴 시간 뒤의 구분선은 숨김
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-time::after, ul.gall-detail-lst > li ul.ginfo > li.dcapp-time::before{display:none!important}',
      'ul.gall-detail-lst > li ul.ginfo{display:flex!important;flex-wrap:nowrap!important;align-items:center}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-head{order:-1;margin-left:0}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-time{order:10}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-time:not(.dcapp-after-head){margin-left:auto}',
      'ul.gall-detail-lst > li ul.ginfo > li.dcapp-head-default{display:none!important}',
      // 페이지 구분선(더보기·당기기로 이어 붙인 페이지 앞): "N페이지 ───" 한 줄, 글자 12px 회색, 다크모드·듀오 안전 영역 대응
      'ul.gall-detail-lst > li.dcapp-pg-sep{display:flex!important;align-items:center;gap:8px;list-style:none!important;margin:0!important;padding:8px 12px!important;border:0!important;background-color:transparent!important;color:#8a8f99!important;font-size:12px!important;line-height:1.2!important;box-sizing:border-box!important;min-height:0!important;height:auto!important}',
      'ul.gall-detail-lst > li.dcapp-pg-sep > span{flex:0 0 auto;font-weight:600}',
      'ul.gall-detail-lst > li.dcapp-pg-sep::after{content:"";flex:1 1 auto;height:1px;background:var(--dcapp-hl)}',
      'html.darkmode ul.gall-detail-lst > li.dcapp-pg-sep{color:#9aa0ab!important}',
      // 듀오: 글자(N페이지)는 왼쪽 안전 영역 안쪽, 선은 안전 영역을 지나 오른쪽 16px 여백까지
      'html.dcapp-duocol ul.gall-detail-lst > li.dcapp-pg-sep,html.dcapp-duoflip ul.gall-detail-lst > li.dcapp-pg-sep{padding-left:calc(12px + env(safe-area-inset-left))!important;padding-right:16px!important}',
      // 목록 톤 변수 (다크모드·듀오 안전 영역은 값만 바꿈). 행 구분선은 양끝 16px을 비운 헤어라인
      'html{--dcapp-hl:rgba(0,0,0,.06);--dcapp-hl-l:16px;--dcapp-hl-r:16px}',
      'html.darkmode{--dcapp-hl:rgba(255,255,255,.08)}',
      'ul.gall-detail-lst > li{border-top-color:transparent!important;background-image:linear-gradient(to right,transparent var(--dcapp-hl-l),var(--dcapp-hl) var(--dcapp-hl-l),var(--dcapp-hl) calc(100% - var(--dcapp-hl-r)),transparent calc(100% - var(--dcapp-hl-r)))!important;background-size:100% 1px!important;background-repeat:no-repeat!important;background-position:0 0!important}',
      'ul.gall-detail-lst + ul.gall-detail-lst,.detail-sel-box + .gall-detail-lst{border-top-color:transparent!important}',
      'ul.gall-detail-lst{border-bottom:0!important}',
      // 글 종류 아이콘: 이미지 없는 글은 문서, 사진·영상 글은 단색 사진·영상 (디시 초록 스프라이트 대신). 색은 글자색을 따라감
      'ul.gall-detail-lst > li .sp-lst-txt{--dcapp-ico:url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI+PHBhdGggZD0iTTQgMS43NWg1LjFMMTIuNzUgNS40VjEzLjVhLjc1Ljc1IDAgMCAxLS43NS43NUg0YS43NS43NSAwIDAgMS0uNzUtLjc1VjIuNUEuNzUuNzUgMCAwIDEgNCAxLjc1WiIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjMDAwIiBzdHJva2Utd2lkdGg9IjEuNCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIvPjxwYXRoIGQ9Ik02IDguMjVoNE02IDEwLjc1aDQiIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSIxLjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPjwvc3ZnPg==)}',
      'ul.gall-detail-lst > li .sp-lst-img{--dcapp-ico:url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI+PHJlY3QgeD0iMS43NSIgeT0iMi43NSIgd2lkdGg9IjEyLjUiIGhlaWdodD0iMTAuNSIgcng9IjIiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSIxLjQiLz48Y2lyY2xlIGN4PSI1LjYiIGN5PSI2LjIiIHI9IjEuMjUiIGZpbGw9IiMwMDAiLz48cGF0aCBkPSJNMi42IDEyLjJsMy40LTMuMyAyLjIgMi4xIDEuNi0xLjUgMy42IDIuNyIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjMDAwIiBzdHJva2Utd2lkdGg9IjEuMyIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIvPjwvc3ZnPg==)}',
      'ul.gall-detail-lst > li .sp-lst-play,ul.gall-detail-lst > li .sp-lst-mov{--dcapp-ico:url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI+PHJlY3QgeD0iMS43NSIgeT0iMi43NSIgd2lkdGg9IjEyLjUiIGhlaWdodD0iMTAuNSIgcng9IjIiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSIxLjQiLz48cGF0aCBkPSJNNi42IDUuNnY0LjhsMy45LTIuNHoiIGZpbGw9IiMwMDAiLz48L3N2Zz4=)}',
      'ul.gall-detail-lst > li .sp-lst-txt,ul.gall-detail-lst > li .sp-lst-img,ul.gall-detail-lst > li .sp-lst-play,ul.gall-detail-lst > li .sp-lst-mov{background:none!important;display:block!important;width:14px!important;height:14px!important;font-size:0!important;line-height:0!important;overflow:hidden!important;color:#7a808c!important;top:50%!important;transform:translateY(-50%)!important}',
      'ul.gall-detail-lst > li .sp-lst-txt::before,ul.gall-detail-lst > li .sp-lst-img::before,ul.gall-detail-lst > li .sp-lst-play::before,ul.gall-detail-lst > li .sp-lst-mov::before{content:"";display:block;width:100%;height:100%;background:currentColor;-webkit-mask:var(--dcapp-ico) center/contain no-repeat;mask:var(--dcapp-ico) center/contain no-repeat}',
      'html.darkmode ul.gall-detail-lst > li .sp-lst-txt,html.darkmode ul.gall-detail-lst > li .sp-lst-img,html.darkmode ul.gall-detail-lst > li .sp-lst-play,html.darkmode ul.gall-detail-lst > li .sp-lst-mov{color:#a3a9b6!important}',
      '#dcapp-headbar #dcapp-filterbtn{flex:0 0 auto;border:0;margin:6px 4px 6px 0;padding:0 7px;height:30px;border-radius:999px;background:transparent;color:#5b6170;display:flex;align-items:center;justify-content:center;-webkit-appearance:none}',
      '#dcapp-headbar #dcapp-filterbtn svg{width:19px;height:19px;display:block}',
      '#dcapp-headbar #dcapp-filterbtn.dcapp-on{background:rgba(59,72,144,.12);color:#3b4890}',
      'html.darkmode #dcapp-headbar #dcapp-filterbtn{color:#c9ccd4}',
      'html.darkmode #dcapp-headbar #dcapp-filterbtn.dcapp-on{background:rgba(169,180,240,.16);color:#a9b4f0}',
      // 댓글 수: 행 오른쪽 위 캡슐(말풍선 아이콘 + 숫자), 작성시간: 행 오른쪽 아래. 두 개가 같은 오른쪽 끝선에 맞음. 제목은 캡슐을 피해 줄어듦
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li{position:relative}',
      // 댓글 배지·작성시간은 같은 기준(행 li)에 맞춤: 1페이지 .gall-detail-lnktb도 static (2페이지+ 배지는 li 바로 아래라 기준이 li와 같아야 함)
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li .gall-detail-lnktb{position:static!important}',
      // 제목 줄은 행 전체 폭을 씀 (오른쪽 댓글 배지·작성시간과는 .subject-add 오른쪽 여백 72px로만 떨어뜨림). 디시 기본 .lt 폭 제한을 풂
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.lt{display:block!important;width:100%!important;max-width:none!important;padding-right:0!important;margin-right:0!important;box-sizing:border-box!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li .gall-detail-lnktb,ul.gall-detail-lst:not(.thum):not(.sch-comment) > li .gall-detail-lnk{width:100%!important;max-width:none!important;box-sizing:border-box!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li .subject-add{max-width:100%!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li .subjectin{max-width:100%!important;box-sizing:border-box!important;flex:0 1 auto!important;min-width:0!important}',
      'svg.dcapp-cmt-ico{width:12px!important;height:12px!important;flex:none!important;display:block!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.lt .subject-add{padding-right:72px!important;box-sizing:border-box!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge{position:absolute!important;top:6px!important;right:12px!important;display:block!important;width:auto!important;min-width:0!important;margin:0!important;padding:0!important;background:transparent!important;border:0!important;text-align:right!important;white-space:nowrap!important;line-height:1!important;vertical-align:middle!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.lt ul.ginfo > li.dcapp-time{position:absolute!important;right:12px!important;bottom:5px!important;margin:0!important;line-height:1.2!important;white-space:nowrap!important}',
      // 듀오 외부 화면: 안전 영역(시계·독 쪽) 안쪽으로 같은 오른쪽 끝선 (dcapp-duoflip은 안전 영역이 왼쪽에 있어 left 기준)
      'html.dcapp-duocol ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge{right:calc(12px + env(safe-area-inset-right))!important}',
      'html.dcapp-duocol ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.lt ul.ginfo > li.dcapp-time{right:calc(12px + env(safe-area-inset-right))!important}',
      // 뒤집힌 옆 줄의 오른쪽 여백은 화면 오른쪽 끝에 닿을 때만 (분할 화면의 왼쪽 목록은 닿지 않으니 붙이지 않음 → 오른쪽 요소가 밀리지 않음)
      'html.dcapp-duoflip-r ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge{right:calc(12px + env(safe-area-inset-left))!important}',
      'html.dcapp-duoflip-r ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.lt ul.ginfo > li.dcapp-time{right:calc(12px + env(safe-area-inset-left))!important}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge .ct{display:inline-flex!important;align-items:center;justify-content:center;gap:3px;height:20px;box-sizing:border-box;padding:0 7px 0 6px!important;margin:0!important;border-radius:999px;background:rgba(59,72,144,.09)!important;color:#3b4890!important;font-size:12px!important;font-weight:600!important;line-height:1!important;vertical-align:middle}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge .ct svg{width:12px;height:12px;flex:none;display:block}',
      'ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge.dcapp-cmt-zero .ct{background:rgba(0,0,0,.04)!important;color:#9aa0ab!important;font-weight:400!important}',
      'html.darkmode ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge .ct{background:rgba(169,180,240,.14)!important;color:#a9b4f0!important}',
      'html.darkmode ul.gall-detail-lst:not(.thum):not(.sch-comment) > li a.rt.dcapp-cmtbadge.dcapp-cmt-zero .ct{background:rgba(255,255,255,.06)!important;color:#7d8290!important}',
      // 목록 상단 고정: 말머리 목록(sticky)과 지나온 페이지 표시줄. html·body·.sec-wrap의 overflow(앱 기본 hidden, 디시 hidden)가 sticky를 막아, 목록 페이지에서만 x축을 clip으로 바꾸고 y축은 풀어 둠 (clip은 스크롤 상자가 되지 않음)
      '#dcapp-headbar{position:sticky!important;top:0;z-index:21}',
      'html:has(ul.gall-detail-lst),body:has(ul.gall-detail-lst),.sec-wrap:has(ul.gall-detail-lst),.sec-wrap-sub:has(ul.gall-detail-lst){overflow-x:clip!important;overflow-y:visible!important}',
      '#dcapp-pgwrap{position:sticky;top:0;height:0;z-index:20}',
      '#dcapp-pgbar{display:none;position:absolute;left:0;right:0;top:0;height:30px;box-sizing:border-box;align-items:center;gap:8px;padding:0 12px;background:#fff;color:#3b4890;font-size:12px;font-weight:600;line-height:1;box-shadow:0 1px 0 var(--dcapp-hl)}',
      '#dcapp-pgbar.dcapp-on{display:flex}',
      '#dcapp-pgbar::after{content:"";flex:1 1 auto;height:1px;background:var(--dcapp-hl)}',
      'html.darkmode #dcapp-pgbar{background:#272729;color:#a9b4f0}',
      'html.dcapp-duocol #dcapp-pgbar{padding-left:calc(12px + env(safe-area-inset-left))!important;padding-right:16px!important}',
      'html.dcapp-duoflip #dcapp-pgbar{padding-left:calc(12px + env(safe-area-inset-left))!important;padding-right:16px!important}',
      // 말머리 줄: 투명 테두리로 잘리던 것을 없애고 여백으로. 맨 왼쪽 버튼은 왼쪽 안전 영역 안에서 시작, 끝 스페이서로 마지막 버튼까지 스크롤
      'html.dcapp-duocol #dcapp-headbar,html.dcapp-duoflip #dcapp-headbar{padding-left:calc(6px + env(safe-area-inset-left))!important}',
      '#dcapp-headbar .dcapp-hscroll::after{content:"";flex:0 0 6px}',
      'html.dcapp-duocol #dcapp-headbar .dcapp-hscroll::after{flex:0 0 calc(6px + env(safe-area-inset-right))}',
      'html.dcapp-duoflip-r #dcapp-headbar .dcapp-hscroll::after{flex:0 0 calc(6px + env(safe-area-inset-left))}',
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
      'html.dcapp-cmtretry .loading-box{display:none!important}',
      'html.dcapp-tscheck .loading-box{display:none!important}',
      '.dcapp-blockmode [data-dcapp-unit]{outline:1px dashed rgba(255,59,48,.6)!important;outline-offset:-1px!important}',
      '.dcapp-pick{outline:3px solid #ff3b30!important;outline-offset:-3px!important;background-color:rgba(255,59,48,.15)!important}',
      // 닉네임·디시콘만 길게 누르기 메뉴를 쓰므로 iOS 기본 메뉴(복사 등)를 막고, 나머지 글자는 평소처럼 선택·복사 가능
      '.dcapp-lp-nick,.dcapp-memo,img[src*="dccon"],img[data-original*="dccon"]{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none}',
      '[data-dcapp-unit="post"],[data-dcapp-unit="post"] a{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}',
      '.dcapp-dory{display:none!important}',
      // 메모: 상자 없이 글자만 (닉네임 뒤에 주황 글씨)
      // 글목록: 닉네임 칸의 오른쪽 여백을 빼서 메모와의 간격을 글·댓글과 같게
      // 글목록: 고닉 아이콘 뒤 구분선 | (li.list-nick::after, 오른쪽 6px) 자리를 비워 아이콘과 겹치지 않게 하고, 메모는 구분선 바로 뒤에 붙임
      'ul.ginfo > li.list-nick:has(+ .dcapp-memo){padding-right:10px!important}',
      'ul.gall-detail-lst > li ul.ginfo > .dcapp-memo{margin-left:4px!important}',
      '.dcapp-memo{display:inline;margin:0 8px 0 8px;padding:0;background:none;border-radius:0;font-size:12px;color:#c56a00;font-weight:normal;white-space:nowrap}',
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
      '.gallview-tit-box .tit{font-size:16px!important;line-height:1.4!important;font-weight:400!important}',
      // 듀오 옆 세로 줄(시계·배터리) 아래로 웹이 깔려도 글 제목칸(제목·글쓴이·댓글 버튼)은 줄 밖에 두어 가려지거나 안 눌리는 일이 없게
      '.gallview-tit-box{padding-right:max(12px,env(safe-area-inset-right))!important;padding-left:max(12px,env(safe-area-inset-left))!important}',
      // 듀오 옆 세로 줄(시계·배터리)이 있을 때: 글자는 줄 안쪽으로 (사진·영상은 줄 아래까지 그대로 깔림)
      // 박스(배경)는 화면 끝까지 채우고 글자만 줄 안쪽으로: 투명 테두리를 줄 폭만큼 둠 (배경은 테두리 밑까지 깔리고, 원래 안쪽 여백은 그대로)
      'html.dcapp-duocol .gall-detail-lnktb,html.dcapp-duocol .thum-txtin,html.dcapp-duocol li.comment,html.dcapp-duocol li.comment-add{box-sizing:border-box!important;border-left:env(safe-area-inset-left) solid transparent!important;border-right:env(safe-area-inset-right) solid transparent!important}',
      // 글 목록: 제목이 줄어들어도(…) [댓글수]는 항상 보이게, 시간은 줄 안쪽 끝에 (위의 테두리로 줄 폭만큼 안쪽에서 끝남)
      // 글 목록 줄은 display:table;width:100% 라서 테두리를 더하면 폭이 그만큼 커져 오른쪽으로 밀림 → 테두리를 폭 안에 포함
      'html.dcapp-duocol ul.gall-detail-lst > li .gall-detail-lnktb{box-sizing:border-box!important;width:100%!important}',
      'html.dcapp-duocol ul.gall-detail-lst > li .subject-add .subjectin{min-width:0!important;flex:0 1 auto!important}',
      'html.dcapp-duocol .dcapp-cmt{flex:none!important}',
      // 세로 줄 영역은 웹 화면에서 터치되지 않게 (투명 막이 터치를 받아 아래 페이지로 안 넘김). 네이티브 컨트롤바는 이 위에 따로 떠 있어 그대로 조작됨
      'html.dcapp-duocol::before{content:"";position:fixed;top:0;bottom:0;right:0;width:env(safe-area-inset-right);z-index:2147483646;touch-action:none;pointer-events:auto}',
      'html.dcapp-duocol::after{content:"";position:fixed;top:0;bottom:0;left:0;width:env(safe-area-inset-left);z-index:2147483646;touch-action:none;pointer-events:auto}',
      // 돌려서 줄이 왼쪽에 생긴 상태: 글자 여백은 왼쪽이 아니라 오른쪽으로 (컨트롤바가 오른쪽 여백에 들어가게)
      'html.dcapp-duoflip .gall-detail-lnktb,html.dcapp-duoflip .thum-txtin,html.dcapp-duoflip li.comment,html.dcapp-duoflip li.comment-add{border-left:0!important}',
      'html.dcapp-duoflip-r .gall-detail-lnktb,html.dcapp-duoflip-r .thum-txtin,html.dcapp-duoflip-r li.comment,html.dcapp-duoflip-r li.comment-add{border-right:env(safe-area-inset-left) solid transparent!important}',
      // 글 아래 목록보기·수정·삭제 버튼 줄: 오른쪽 끝(삭제)이 세로 줄 터치 차단막 밑에 깔려 안 눌림 → 다른 글자칸처럼 줄 밖으로
      'html.dcapp-duocol .btn-justify-area{box-sizing:border-box!important;border-left:env(safe-area-inset-left) solid transparent!important;border-right:env(safe-area-inset-right) solid transparent!important}',
      'html.dcapp-duoflip .btn-justify-area{border-left:0!important}',
      'html.dcapp-duoflip-r .btn-justify-area{border-right:env(safe-area-inset-left) solid transparent!important}',
      // 세로 컨트롤바가 페이지 위에 떠 있는 화면(일반 폰·아이패드·분할): 수정·삭제 줄을 바 폭만큼 비움 (앱이 --dcapp-bar-l/r 값을 넣어 줌)
      '.dcapp-btnrow,.view-btn-box,.gallview-btn-box{box-sizing:border-box!important;border-left:var(--dcapp-bar-l,0px) solid transparent!important;border-right:var(--dcapp-bar-r,0px) solid transparent!important}',
      'html.dcapp-duocol .dcapp-btnrow,html.dcapp-duocol .view-btn-box,html.dcapp-duocol .gallview-btn-box{box-sizing:border-box!important;border-left:max(env(safe-area-inset-left),var(--dcapp-bar-l,0px)) solid transparent!important;border-right:max(env(safe-area-inset-right),var(--dcapp-bar-r,0px)) solid transparent!important}',
      'html.dcapp-duoflip .dcapp-btnrow,html.dcapp-duoflip .view-btn-box,html.dcapp-duoflip .gallview-btn-box{border-left:var(--dcapp-bar-l,0px) solid transparent!important}',
      'html.dcapp-duoflip-r .dcapp-btnrow,html.dcapp-duoflip-r .view-btn-box,html.dcapp-duoflip-r .gallview-btn-box{border-right:max(env(safe-area-inset-left),var(--dcapp-bar-r,0px)) solid transparent!important}',
      'html.dcapp-duoflip::before{width:env(safe-area-inset-left)!important}',
      // 화면 전체 폭으로 뜨는 창(디시콘 정보 등)은 세로 줄 밑으로 깔려 오른쪽 끝 버튼(사용·X)이 터치 차단막에 막힘 → 창 안쪽을 줄 밖으로 비움
      'html.dcapp-duocol .layer-center-popup.full{box-sizing:border-box!important;padding-left:env(safe-area-inset-left)!important;padding-right:env(safe-area-inset-right)!important}',
      'html.dcapp-duoflip .layer-center-popup.full{padding-left:0!important}',
      'html.dcapp-duoflip-r .layer-center-popup.full{padding-right:env(safe-area-inset-left)!important}',
      // 디시콘 정보 창(#dcconPop, v353): 다른 띠·정렬바보다 위, 상단바 밑으로 안 잘리게(--dcapp-top), 앱 카드 모양, 설명과 스티커 사이 빈 간격 줄임
      '#dcconPop.layer-center-popup{z-index:2147483647!important;padding-top:calc(var(--dcapp-top,0px) + 16px)!important;padding-bottom:16px!important;box-sizing:border-box!important;background-color:rgba(0,0,0,.4)!important;text-align:center!important}',
      '#dcconPop.layer-center-popup::after{display:none!important}',
      '#dcconPop .layer-popup-inner{display:block!important;vertical-align:top!important;width:calc(100% - 24px)!important;max-width:460px!important;margin:0 auto!important;background:#fff!important;border-radius:18px!important;overflow:hidden!important;box-shadow:0 12px 32px rgba(0,0,0,.2)!important;text-align:left!important;white-space:normal!important;font-size:14px!important}',
      '#dcconPop .pp-box,#dcconPop .dccon-info-wrap{background:#fff!important;height:auto!important;min-height:0!important;padding-bottom:0!important}',
      '#dcconPop .dccon-caption-box > *,#dcconPop .dccon-caption-box div{height:auto!important;min-height:0!important;max-height:none!important;padding-bottom:0!important;margin-bottom:0!important}',
      '#dcconPop .dccon-caption-box br{display:none!important}',
      '#dcconPop .dccon-caption-box + div:empty,#dcconPop .dccon-price-box:empty{display:none!important}',
      '#dcconPop .pp-tit-box{border-bottom:0!important;padding:0!important}',
      '#dcconPop .pp-tit2{padding:14px 56px 10px 18px!important;font-size:17px!important;font-weight:700!important;color:#222!important;letter-spacing:-.3px!important}',
      '#dcconPop .pp-tit-box .rt{position:absolute!important;right:14px!important;top:14px!important;transform:none!important}',
      '#dcconPop .btn-x-close{position:relative!important;display:block!important;width:30px!important;height:30px!important;border-radius:15px!important;background:#eef0f5!important;background-image:none!important;transform:none!important;overflow:hidden!important}',
      '#dcconPop .btn-x-close::before,#dcconPop .btn-x-close::after{content:""!important;position:absolute!important;left:50%!important;top:50%!important;width:14px!important;height:2px!important;margin:-1px 0 0 -7px!important;background:#555!important;border-radius:1px!important;transform:rotate(45deg)!important}',
      '#dcconPop .btn-x-close::after{transform:rotate(-45deg)!important}',
      '#dcconPop .dccon-caption-box{background:#fff!important;padding:0 18px!important;border:0!important;height:auto!important;min-height:0!important;margin:0!important}',
      '#dcconPop .dccon-caption-box .top-info{display:flex!important;align-items:flex-start!important;gap:14px!important;overflow:visible!important;height:auto!important;min-height:0!important;max-height:none!important;padding:0!important;margin:0!important}',
      '#dcconPop .dccon-caption-box .top-info::after{display:none!important}',
      '#dcconPop .dccon-caption-box .top-tit{flex:1 1 auto!important;min-width:0!important;height:auto!important;min-height:0!important;max-height:none!important;padding:0!important;margin:0!important}',
      '#dcconPop .dccon-caption-box .thum-img{float:none!important;flex:0 0 88px!important;width:88px!important;height:88px!important;margin:0!important;border-radius:14px!important;overflow:hidden!important;background:#f2f2f7!important}',
      '#dcconPop .dccon-caption-box .thum-img::after{display:none!important}',
      '#dcconPop .dccon-caption-box .thum-img img{width:100%!important;height:100%!important;object-fit:contain!important}',
      '#dcconPop .dccon-caption-box .top-tit .name{font-size:16px!important;font-weight:700!important;color:#222!important;margin:0!important;padding:0!important}',
      '#dcconPop .dccon-caption-box .make{margin:4px 0 0!important;padding:0!important}',
      '#dcconPop .dccon-caption-box .make span{font-size:12px!important;color:#8e8e93!important}',
      '#dcconPop .dccon-caption-box .make .lnk{color:#3b4890!important;text-decoration:none!important}',
      '#dcconPop .dccon-caption-box .txt{font-size:13px!important;color:#555!important;margin:6px 0 0!important;padding:0!important;height:auto!important;min-height:0!important;max-height:none!important;letter-spacing:-.2px!important}',
      '#dcconPop .dccon-btn-box{position:static!important;margin:12px 0 0!important;padding:0 18px!important;height:auto!important;min-height:0!important;border-bottom:0!important;text-align:left!important;background:#fff!important}',
      '#dcconPop .dccon-btn-box .btn-buy,#dcconPop .dccon-btn-box button{display:block!important;width:100%!important;height:38px!important;border:0!important;border-radius:12px!important;background:#3b4890!important;color:#fff!important;font-size:15px!important;font-weight:700!important;padding:0!important;letter-spacing:0!important}',
      '#dcconPop .dccon-img-slider{padding:14px 10px 16px!important;height:auto!important;background:#fff!important}',
      '#dcconPop #swiper-dccon-detail,#dcconPop .dccon-img-lst-wrap{height:auto!important}',
      '#dcconPop .dccon-img-lst{height:auto!important;line-height:0!important;font-size:0!important;background:none!important}',
      '#dcconPop .dccon-img-lst li{padding:6px!important}',
      '#dcconPop .dccon-img-lst li .sm-img{display:block!important;border-radius:14px!important;overflow:hidden!important;background:#f7f7fa!important}',
      '#dcconPop .dccon-img-lst li .sm-img img{border:0!important;border-radius:14px!important}',
      '#dcconPop .dccon-img-lst li.on .sm-img img{border:2px solid #3b4890!important}',
      'html.darkmode #dcconPop .layer-popup-inner,html.darkmode #dcconPop .pp-box,html.darkmode #dcconPop .dccon-caption-box,html.darkmode #dcconPop .dccon-btn-box,html.darkmode #dcconPop .dccon-img-slider{background:#1c1c1e!important}',
      'html.darkmode #dcconPop .pp-tit2,html.darkmode #dcconPop .dccon-caption-box .top-tit .name{color:#f2f2f7!important}',
      'html.darkmode #dcconPop .dccon-caption-box .txt{color:#aeaeb2!important}',
      'html.darkmode #dcconPop .dccon-caption-box .make span{color:#8e8e93!important}',
      'html.darkmode #dcconPop .dccon-caption-box .make .lnk{color:#9db0ff!important}',
      'html.darkmode #dcconPop .dccon-caption-box .thum-img{background:#2c2c2e!important}',
      'html.darkmode #dcconPop .btn-x-close{background:#3a3a3c!important}',
      'html.darkmode #dcconPop .btn-x-close::before,html.darkmode #dcconPop .btn-x-close::after{background:#e5e5ea!important}',
      'html.darkmode #dcconPop .dccon-img-lst li .sm-img{background:#2c2c2e!important}',
      'html.darkmode #dcconPop .dccon-btn-box .btn-buy,html.darkmode #dcconPop .dccon-btn-box button{background:#5a6ad0!important}',
      'html.dcapp-duoflip::after{width:0!important}',
      '.gallview-tit-box .btm{margin-top:8px!important}',
      // 페이지 전체가 좌우로 넘쳐 밀리지 않게 (말머리 탭 등 개별 요소의 가로 스크롤은 그대로)
      'html,body{overflow-x:hidden!important;max-width:100%!important}',
      '.thum-txtin{font-size:16px!important;line-height:1.7!important;word-break:keep-all}',
      'li.comment .txt,li.comment-add .txt{font-size:14px!important}',
      // 대댓글 앞 표시: 디시 파란 'ㄴ' 스프라이트(contents.css .all-comment-lst .comment-add::before) 대신 작은 직각 └ 헤어라인 (닉네임 줄 높이, 1px 회색)
      'li.comment-add::before{content:""!important;display:block!important;position:absolute!important;left:20px!important;top:9px!important;width:8px!important;height:8px!important;box-sizing:border-box!important;background:none!important;border:0!important;border-left:1px solid rgba(0,0,0,.2)!important;border-bottom:1px solid rgba(0,0,0,.2)!important;border-radius:0!important}',
      'html.darkmode li.comment-add::before{border-left-color:rgba(255,255,255,.26)!important;border-bottom-color:rgba(255,255,255,.26)!important}',
      // 고닉·반고닉·매니저 아이콘 축소 (힛갤로콘 아이콘 제외): transform은 그려지는 모양만 줄이고 스프라이트 background-position은 건드리지 않음.
      // 레이아웃 박스(14px)의 오른쪽 여백을 0으로 두어 축소된 아이콘(10.5px) 뒤에 약 3.5px 간격이 남아 구분선(|)과 겹치지 않게 함
      '.sp-nick:not(.sp_hitnickcon),.gonick:not(.sp_hitnickcon),.nogonick:not(.sp_hitnickcon),.m-gonick:not(.sp_hitnickcon),.m-nogonick:not(.sp_hitnickcon),.sub-gonick:not(.sp_hitnickcon),.sub-nogonick:not(.sp_hitnickcon){transform:scale(.75)!important;transform-origin:left center!important;margin-right:-1.5px!important}',
      // 본문이 짧아도 글목록 5칸 정도(약 300px)는 보이게 (댓글 영역이 위로 붙지 않도록)
      '.thum-txt{min-height:300px!important}',
      '.thum-txtin img{max-width:100%!important;height:auto!important}',
      '.thum-txtin video,.thum-txtin iframe{max-width:100%!important}',
      // 스포일러 글: 경고 칸(#spoiler)을 누르기 전까지 그 아래 본문을 흐리게 (.dcapp-spo-blur = 경고 칸 뒤의 본문을 감싼 칸, spoilerGuard가 만듦)
      '.thum-txtin > .dcapp-spo-blur{display:block!important;padding:0!important;margin:0!important;filter:blur(22px)!important;-webkit-filter:blur(22px)!important;clip-path:inset(0)!important;pointer-events:none!important;-webkit-user-select:none!important;user-select:none!important}',
      '.thum-txtin #spoiler{cursor:pointer}',
      // 본문 사진 길게 누르면 iOS 기본 메뉴(사진 저장 등) 대신 앱 차단 메뉴
      '.thum-txtin img,.thum-txtin video.dc_mv{-webkit-touch-callout:none!important;-webkit-user-select:none!important;user-select:none!important}',
      // 본문 사진 차단: 그 사진만 가림 (.dcapp-imgblk = 사진을 감싼 칸, applyImageBlocks가 만듦). 블러 또는 회색 칸, 짧게 누르면 잠깐 보임
      '.dcapp-imgblk{display:inline-block;position:relative;max-width:100%;line-height:0;vertical-align:top}',
      '.dcapp-imgblk-badge{display:none;position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);white-space:nowrap;font-size:13px;line-height:1.2;font-weight:600;letter-spacing:0;color:#fff;background:rgba(0,0,0,.55);padding:8px 14px;border-radius:16px;pointer-events:none}',
      '.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"]) > .dcapp-imgblk-badge{display:block}',
      '.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"])[data-dcapp-style="blur"] > img,.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"])[data-dcapp-style="blur"] > video{filter:blur(22px) brightness(.82)!important;-webkit-filter:blur(22px) brightness(.82)!important}',
      '.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"]){overflow:hidden;border-radius:8px}',
      '.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"])[data-dcapp-style="gray"]{background:#c7c7cc}',
      '.darkmode .dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"])[data-dcapp-style="gray"]{background:#3a3a3c}',
      '.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"])[data-dcapp-style="gray"] > img,.dcapp-imgblk[data-dcapp-blocked="1"]:not([data-dcapp-img-revealed="1"])[data-dcapp-style="gray"] > video{visibility:hidden!important}',
      // 경고 칸 아래쪽 안내 (디시 사진에는 '스크롤 해주세요'라고만 적혀 있어서, 눌러야 풀린다는 걸 알려 줌)
      // 스포일러 경고 칸: 디시 경고 그림 대신 앱 스타일 카드 (문구 + 탭하여 보기, 다크모드). 누르면 보이는 동작(revealSpoiler)은 그대로
      '.thum-txtin #spoiler{height:auto!important;min-height:0!important;max-height:none!important;padding:0!important;margin:0 0 10px!important;background:none!important;border:0!important;box-sizing:border-box!important}',
      '.thum-txtin #spoiler *{display:none!important;height:auto!important;min-height:0!important;max-height:none!important;background-image:none!important}',
      '.thum-txtin #spoiler > .spoiler-wrap{display:flex!important;position:relative!important;height:auto!important;min-height:0!important;box-sizing:border-box!important;display:flex!important;flex-direction:row!important;align-items:center!important;justify-content:center!important;gap:8px!important;padding:9px 14px!important;margin:0 0 10px!important;border-radius:12px!important;background:#f2f3f8!important;text-align:center!important}',
      '.thum-txtin #spoiler > .spoiler-wrap::before{content:"스포일러 주의";font-size:14px;font-weight:700;line-height:1.2;color:#222;letter-spacing:0;white-space:nowrap}',
      '.thum-txtin #spoiler > .spoiler-wrap::after{content:"탭하여 보기";position:static;transform:none;font-size:12px;font-weight:600;line-height:1.2;color:#3b4890;padding:4px 10px;border-radius:999px;background:rgba(59,72,144,.10);letter-spacing:0;white-space:nowrap}',
      'html.darkmode .thum-txtin #spoiler > .spoiler-wrap{background:#2c2c2e!important}',
      'html.darkmode .thum-txtin #spoiler > .spoiler-wrap::before{color:#e5e5ea}',
      'html.darkmode .thum-txtin #spoiler > .spoiler-wrap::after{color:#9db0ff;background:rgba(157,176,255,.14)}',
      '.gall-thum-btm{padding-top:14px!important}',
      'html.dcapp-pwauto body{visibility:hidden!important}',   // 유동 글 수정 비밀번호 자동 확인 중
      // 댓글 입력 칸: 한 줄에서 시작해 줄이 늘면 같이 커지고, 10줄을 넘으면 스크롤 (높이는 fitCommentBox가 맞춤)
      '#comment_memo.comment-caption{min-height:44px!important;resize:none!important;white-space:pre-wrap!important;padding:12px 8px!important;box-sizing:border-box!important;line-height:20px!important}',
      // 디시가 글·댓글 등록을 막을 때(차단된 IP 등) 띄우는 안내 창은 안 보이게 — 앱이 같은 문구를 따로 띄우고 이전 화면으로 돌아감
      '#ip_not_popup{display:none!important}',
      // 앱 댓글 입력창을 쓰면: 글 아래 댓글창은 한 줄 입력칸 모양으로 (닉네임·비밀번호·코드·디시콘·등록은 앱 입력창에 있음). 글자콘 창은 화면 밖에 두고 앱이 조작
      'html.dcapp-nc .comment-write{border:0!important;background:transparent!important}',
      // 컨트롤바가 세로 막대일 때: 댓글 입력칸을 화면(분할이면 글 화면) 아래에 고정 — 입력칸만 (댓글 수·새로고침·본문·댓글 위로 머리글은 없음)
      // 입력칸은 화면 아래에 고정하되, 원래 자리에는 '글 목록' 띠를 남겨 댓글과 아래 글 목록이 섞여 보이지 않게
      'html.dcapp-nc.dcapp-pin .comment-write-btm:not([id^="img_comment_write_div"]){position:relative!important;display:flex!important;align-items:center!important;box-sizing:border-box!important;height:44px!important;min-height:0!important;padding:0 14px!important;background:#e9ebf2!important;border-top:1px solid #d3d6e0!important;border-bottom:1px solid #d3d6e0!important}',
      'html.dcapp-pin .comment-write-btm:not([id^="img_comment_write_div"])::after{content:"▼ 글 목록";display:inline-flex;align-items:center;box-sizing:border-box;height:28px;padding:0 14px;border:1px solid #d3d6e0;border-radius:14px;background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.06);font-size:13px;line-height:1;font-weight:700;color:#6b6f80}',
      'html.dcapp-pin .comment-write-btm:not([id^="img_comment_write_div"]) .comment-write{position:fixed!important;left:0!important;right:0!important;bottom:0!important;z-index:9000!important;padding:8px 12px 22px!important;background:#f9fafc!important;border-top:1px solid #e1e3ea!important;box-sizing:border-box!important}',
      'html.darkmode.dcapp-nc.dcapp-pin .comment-write-btm:not([id^="img_comment_write_div"]){background:#2a2a2d!important;border-color:#3d3d40!important}',
      'html.darkmode.dcapp-pin .comment-write-btm:not([id^="img_comment_write_div"])::after{color:#9a9ca6;background:#2c2c2e;border-color:#48484c;box-shadow:none}',
      'html.darkmode.dcapp-pin .comment-write-btm:not([id^="img_comment_write_div"]) .comment-write{background:#1c1c1e!important;border-top-color:#2c2c2e!important}',
      'html.dcapp-pin body{padding-bottom:84px!important}',
      'html.dcapp-nc .comment-write-btm:not([id^="img_comment_write_div"]){padding:10px 12px!important}',
      'html.dcapp-nc #comment_write .who,html.dcapp-nc #comment_write .btm-wrt-btns,html.dcapp-nc [id^="comment_addDiv"]:not([data-dcapp-show]){height:0!important;overflow:hidden!important;visibility:hidden!important;margin:0!important;padding:0!important;border:0!important;min-height:0!important}',
      // Cloudflare 체크가 필요해 드러난 답글 칸: 칸은 보이되, 닉네임·입력칸·버튼 줄은 .dcapp-tsx로 숨겨 체크박스만 남김
      'html.dcapp-nc [id^="comment_addDiv"][data-dcapp-show]{height:auto!important;overflow:visible!important;visibility:visible!important;min-height:0!important}',
      '.dcapp-tsx{display:none!important}',
      '#dcapp-tsaux{position:fixed!important;left:50%!important;bottom:calc(env(safe-area-inset-bottom) + 112px)!important;transform:translateX(-50%)!important;width:min(340px,calc(100vw - 32px))!important;box-sizing:border-box!important;padding:14px 14px 12px!important;border-radius:16px!important;background:#fff!important;color:#222!important;box-shadow:0 8px 28px rgba(0,0,0,.25)!important;text-align:center!important;z-index:2147483000!important;font-size:14px!important;line-height:1.4!important;margin:0!important}',
      'html.darkmode #dcapp-tsaux{background:#2c2c2e!important;color:#eee!important}',
      '#dcapp-tsaux .dcapp-tsaux-tit{font-size:15px!important;font-weight:700!important;margin:0 0 2px!important;padding:0!important}',
      '#dcapp-tsaux .dcapp-tsaux-sub{font-size:13px!important;opacity:.75!important;margin:0 0 8px!important;padding:0!important}',
      '#dcapp-tsaux .dcapp-tsaux-slot{min-height:65px!important;display:flex!important;justify-content:center!important;align-items:center!important;margin:0!important;padding:0!important}',
      '#dcapp-tsaux .dcapp-tsaux-x{position:absolute!important;top:4px!important;right:6px!important;width:32px!important;height:32px!important;border:0!important;background:transparent!important;color:inherit!important;font-size:22px!important;line-height:1!important;opacity:.6!important;padding:0!important;margin:0!important}',
      '[data-dcapp-unclip]{overflow:visible!important;height:auto!important;max-height:none!important;min-height:0!important;visibility:visible!important}',
      'html.dcapp-nc #comment_write #comment_memo.comment-caption{height:44px!important;min-height:44px!important;border:1px solid #d6d8e2!important;border-radius:22px!important;background:#f2f3f8!important;padding:11px 18px!important;font-size:15px!important;line-height:20px!important;overflow:hidden!important;box-shadow:none!important}',
      'html.darkmode.dcapp-nc #comment_write #comment_memo.comment-caption{background:#2c2c2e!important;border-color:#3d3d40!important}',
      'html.dcapp-nc #txtconBoxComment,html.dcapp-nc #txtconBoxReple,html.dcapp-nc #dcconBoxComment,html.dcapp-nc #dcconBoxReple{position:fixed!important;left:-3000px!important;top:0!important;width:360px!important}',
      // 댓글 헤더: 새로고침·본문·정렬 드롭다운은 숨기고, 등록순/최신순/답글순 체크 버튼으로 대신함
      '#comment_box .all-comment-tit .sp-reload{display:none!important}',
      '.dcapp-cmtin{margin-left:8px;height:24px;padding:0 9px;border:1px solid #c9c9cf;border-radius:4px;background:none;color:#3b4890;font-size:12px;font-weight:600;flex:none}',
      'html.darkmode .dcapp-cmtin{border-color:#55565c;color:#9db0ff}',
      '#comment_box .all-comment-tit .rt>*:not(.dcapp-sort){display:none!important}',
      // 본문 사진 위 '댓글' 버튼: 디시 원본(검은 각진 그림) 대신 반투명 둥근 캡슐 (다크모드도 같은 모양, 글자 크기는 앱 기준)
      '.btn-imgcomment{box-sizing:border-box!important;height:26px!important;width:auto!important;min-width:0!important;padding:0 11px!important;border:0!important;border-radius:13px!important;background:rgba(20,20,22,.58)!important;-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);color:#fff!important;font-family:inherit!important;font-size:12px!important;font-weight:600!important;line-height:26px!important;letter-spacing:0!important;text-align:center!important;white-space:nowrap!important;-webkit-appearance:none!important;box-shadow:none!important}',
      'html.darkmode .btn-imgcomment{background:rgba(255,255,255,.22)!important;color:#f2f2f7!important}',
      // 본문 사진의 '댓글' 영역(img-comment): 디시 원본 회색 판 대신 앱 댓글창과 같은 카드 모양 (헤더·목록·입력칸·다크모드)
      '.img-comment{margin:10px 0 4px!important;border:1px solid #e3e5ee!important;border-radius:12px!important;background:#fff!important;overflow:hidden!important;box-sizing:border-box!important}',
      '.img-comment .all-comment{background:transparent!important;padding:0!important}',
      '.img-comment .all-comment-tit{display:flex!important;align-items:center!important;height:40px!important;min-height:40px!important;padding:0 12px!important;margin:0!important;background:#f9fafc!important;border-bottom:1px solid #eceef5!important;box-sizing:border-box!important}',
      '.img-comment .all-comment-tit .tit-box{flex:1 1 auto;min-width:0}',
      '.img-comment .all-comment-tit .tit{font-size:14px!important;font-weight:600!important;color:#222!important;line-height:1!important}',
      '.img-comment .all-comment-tit .tit .ct{color:#3b4890!important;font-weight:600!important;margin-left:3px}',
      '.img-comment .all-comment-tit .tit .ct.dcapp-ct{display:inline-flex!important;align-items:center!important;justify-content:center!important;min-width:20px!important;height:18px!important;padding:0 6px!important;margin-left:6px!important;border-radius:9px!important;background:rgba(59,72,144,.12)!important;color:#3b4890!important;font-size:12px!important;font-weight:600!important;line-height:1!important;vertical-align:middle!important;box-sizing:border-box!important}',
      'html.darkmode .img-comment .all-comment-tit .tit .ct.dcapp-ct{background:rgba(157,176,255,.16)!important;color:#9db0ff!important}',
      '.img-comment .all-comment-tit .rt{margin-left:auto;font-size:13px!important}',
      '.img-comment .all-comment-tit .comment-close{color:#8a8a90!important;font-size:13px!important}',
      '.img-comment .all-comment-tit .sp-reload{width:18px!important;height:18px!important;margin-left:4px!important}',
      '.img-comment .all-comment-lst{border:0!important;background:#fff!important}',
      '.img-comment .all-comment-lst > li{border-top:1px solid #eef0f6!important}',
      '.img-comment .all-comment-lst > li:first-child{border-top:0!important}',
      '.img-comment .all-comment-lst .comment{padding:8px 12px!important;background:#fff!important}',
      '.img-comment .all-comment-lst .nick{font-size:13px!important;color:#222!important}',
      '.img-comment .all-comment-lst .txt{font-size:14px!important;line-height:1.5!important;color:#222!important;margin-top:2px!important}',
      '.img-comment .all-comment-lst .ip,.img-comment .all-comment-lst .date{font-size:12px!important;color:#9a9aa3!important}',
      '.img-comment .all-comment-lst .comment-add{padding:6px 12px 6px 36px!important;background:#f9fafc!important}',
      '.img-comment .all-comment-lst .comment-write-btm,.img-comment .comment-write-btm{border:0!important;background:#fff!important;padding:8px 12px 10px!important;margin:0!important}',
      '.img-comment .comment-write{border:1px solid #d6d8e2!important;border-radius:10px!important;background:#f2f3f8!important;padding:6px 8px!important;box-sizing:border-box!important}',
      '.img-comment textarea,.img-comment input[type=text],.img-comment input[type=password]{font-size:14px!important;border:0!important;background:transparent!important;color:#222!important;box-shadow:none!important}',
      '.img-comment .btn-comment-write,.img-comment .comment-write button[type=submit]{height:32px!important;min-width:56px!important;padding:0 12px!important;margin:0!important;border:0!important;border-radius:8px!important;background:#3b4890!important;color:#fff!important;font-size:13px!important;font-weight:600!important;line-height:32px!important;vertical-align:middle!important}',
      'html.darkmode .img-comment{background:#1c1c1e!important;border-color:#2c2c2e!important}',
      'html.darkmode .img-comment .all-comment-tit{background:#1c1c1e!important;border-bottom-color:#2c2c2e!important}',
      'html.darkmode .img-comment .all-comment-tit .tit{color:#e5e5ea!important}',
      'html.darkmode .img-comment .all-comment-tit .tit .ct{color:#9db0ff!important}',
      'html.darkmode .img-comment .all-comment-tit .comment-close{color:#8e8e93!important}',
      'html.darkmode .img-comment .all-comment-lst,html.darkmode .img-comment .all-comment-lst .comment,html.darkmode .img-comment .comment-write-btm{background:#1c1c1e!important}',
      'html.darkmode .img-comment .all-comment-lst > li{border-top-color:#2c2c2e!important}',
      'html.darkmode .img-comment .all-comment-lst .nick,html.darkmode .img-comment .all-comment-lst .txt{color:#e5e5ea!important}',
      'html.darkmode .img-comment .all-comment-lst .ip,html.darkmode .img-comment .all-comment-lst .date{color:#8e8e93!important}',
      'html.darkmode .img-comment .all-comment-lst .comment-add{background:#1c1c1e!important}',
      'html.darkmode .img-comment .comment-write{background:#2c2c2e!important;border-color:#3d3d40!important}',
      'html.darkmode .img-comment textarea,html.darkmode .img-comment input[type=text],html.darkmode .img-comment input[type=password]{color:#e5e5ea!important}',
      '.dcapp-sort{display:flex;align-items:center;gap:15px}',
      // 듀오 안전 영역의 터치 차단막(z 2147483646)이 정렬 줄(답글순)을 덮을 때만 정렬 줄을 위로 (다른 상태의 디시 팝업은 그대로)
      'html.dcapp-duocol .dcapp-sort,html.dcapp-duoflip .dcapp-sort{position:relative;z-index:10}',
      '.dcapp-sort button{display:inline-flex;align-items:center;gap:3px;border:0;background:none;padding:6px 0;font-size:16px;color:#8a8a90}',
      '.dcapp-sort button.on{color:#222;font-weight:600}',
      '.dcapp-sort svg{width:24px;height:24px;flex:none;color:#b5b5bb}',
      '.dcapp-sort button.on svg{color:#3b4890}',
      'html.darkmode .dcapp-sort button{color:#a5a5ab}',
      'html.darkmode .dcapp-sort button.on{color:#eee}',
      'html.darkmode .dcapp-sort button.on svg{color:#9db0ff}',
      // 글 아래 목록: 이전글 1개만 보이고 나머지는 '글목록 더보기'로 접음 / 다음글 1개(없으면 '다음 글 없음')
      // 글 아래 디시 검색창과 '더보기'(⌄) 표시는 숨김
      // 관리 내역(탭 줄 .tab-twoline이 있는 섹션)은 섹션째 숨기지 않음 — 삭제 내역 탭에는 검색 상자가 섹션 안에 있어서 빈 화면이 됐음
      'section.grid:has(.con-search-box):not(:has(.tab-twoline)),.con-search-box,#viewlistMore{display:none!important}',
      // 관리 내역 '삭제 내역' 탭의 게시물·댓글 검색 상자는 보이게 (위 규칙보다 구체적이라 우선)
      '#deleteList .con-search-box{display:block!important}',
      'ul#view_next:not(.dcapp-more-open) > li.dcapp-fold{display:none!important}',
      'ul#view_next > li.dcapp-more-li{display:block!important;width:100%!important;box-sizing:border-box!important;padding:10px 16px!important;margin:0!important;border:0!important;background:none!important}',
      '.dcapp-more-btn{display:block;width:100%;box-sizing:border-box;height:40px;padding:0 12px;margin:0;text-align:center;border:1px solid #c9c9cf;border-radius:8px;background:none;color:#3b4890;font-size:14px;font-weight:600;line-height:1}',
      '#dcapp-nextrow{display:flex;align-items:center;gap:10px;padding:12px 16px;font-size:15px;color:#222;border-bottom:1px solid #eee;min-width:0}',
      '#dcapp-nextrow .dcapp-nlabel{flex:none;color:#8a8a90;font-size:13px}',
      '#dcapp-nextrow a{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#222}',
      '#dcapp-nextrow .dcapp-none{color:#8a8a90}',
      'html.darkmode #dcapp-nextrow{color:#eee;border-color:#3d3d41}',
      'html.darkmode #dcapp-nextrow a{color:#eee}',
      'html.darkmode .dcapp-more-btn{border-color:#55565c;color:#9db0ff}',
      // 홈 순위 외형: 앱 테마 색·글씨에 맞춤
      '#rank_tap,#rank_gall_type{background:#fff!important;border-bottom:1px solid #e6e6ea!important}',
      '#rank_tap .tab-lst li a,#rank_gall_type .tab-lst li a{color:#8a8a90;font-weight:600}',
      '#rank_tap .tab-lst li.on a,#rank_gall_type .tab-lst li.on a{color:#3b4890}',
      '#swiper-rank .tab-child-lst li{border-bottom:1px solid #f0f0f3}',
      '#swiper-rank .tab-child-lst li a{padding:10px 16px!important;font-size:15px!important;color:#222!important}',
      '#swiper-rank .tab-child-lst .num{color:#3b4890;font-weight:700;margin-right:6px}',
      'html.darkmode #rank_tap,html.darkmode #rank_gall_type{background:#2d2d30!important;border-color:#3d3d41!important}',
      'html.darkmode #swiper-rank .tab-child-lst li{border-color:#3d3d41}',
      'html.darkmode #swiper-rank .tab-child-lst li a{color:#eee!important}',
      // 홈 순위 영역은 좌우 넘김만 되고, 위아래 스크롤은 막음 (touch-action: pan-x)
      '#swiper-rank,#swiper-hot{touch-action:pan-x!important}',
      // 넓은 화면(아이패드 가로)에서 좌우에 보이던 회색 여백을 흰색으로
      'html:not(.darkmode),html:not(.darkmode) body{background-color:#fff!important}',
      // 아주 넓은 화면(아이패드 가로 1400px 이상)에서 디시가 목록·글 칸 양옆에 두는 64px 여백을 없애 끝까지 쓰게
      '.brick-wid{margin-left:0!important;margin-right:0!important;max-width:none!important;width:auto!important;min-width:0!important}',
      // 홈 순위 아래 좌우 화살표는 필요 없어서 숨김
      '#gallrank_btprev,#gallrank_btnext,#gallhot_btprev,#gallhot_btnext,#livebest_btprev_rank,#livebest_btnext_rank,#livebest_btprev2_rank,#livebest_btnext2_rank{display:none!important}',
      // 추천·비추천 버튼은 앱의 추천 줄(.dcapp-vote)이 대신함. 디시 추천 영역(코드 칸 포함)은 평소엔 숨기고,
      // 추천·비추천을 눌러 코드가 필요할 때만 앱이 .dcapp-codeopen을 붙여 펼침 (디시 버튼·숫자는 계속 숨김)
      '.reco-area{display:none!important}',
      '.reco-area.dcapp-codeopen{display:block!important;margin:0!important;padding:0 12px!important;text-align:left!important}',
      '.reco-area.dcapp-codeopen > :not(.capcha-code-box):not(.dcapp-vcode-ok){display:none!important}',
      '.reco-area.dcapp-codeopen > .capcha-code-box{margin:0 0 8px!important}',
      '.reco-area.dcapp-codeopen .dcapp-vcode-ok{display:block;width:100%;height:40px;margin:0 0 8px;border:0;border-radius:8px;background:#3b4890;color:#fff;font-size:15px;font-weight:700}',
      '.darkmode .reco-area .capcha-code-lst .ipt::placeholder{color:#8e8e93!important}',
      '.dcapp-vote{display:flex;align-items:center;justify-content:center;flex-wrap:nowrap;gap:5px;margin:10px 0 6px}',
      '.dcapp-vbox{display:flex;align-items:stretch;height:30px;border:1px solid #c9c9cf;border-radius:5px;overflow:hidden;flex:none}',
      '.dcapp-vcell{width:28px;flex:none;border:0;border-right:1px solid #c9c9cf;background:#ececf0;color:#3b4890;display:flex;align-items:center;justify-content:center;padding:0}',
      '.dcapp-vbox.down .dcapp-vcell{color:#8a8a90}',
      '.dcapp-vcell svg{width:16px;height:16px}',
      '.dcapp-vcell.on{background:#3b4890;color:#ffd54a}',
      '.dcapp-vcell.on svg path{fill:#ffd54a}',
      '.dcapp-vnum{display:flex;align-items:center;justify-content:center;text-align:center;white-space:nowrap;min-width:0;padding:0 8px;font-size:16px;line-height:1;color:#3b4890}',
      '.dcapp-vbox.down .dcapp-vnum{color:#8a8a90}',
      '.dcapp-vmem{display:flex;align-items:center;justify-content:center;white-space:nowrap;gap:3px;padding:0 6px 0 0;font-size:16px;line-height:1;color:#3b4890}',
      '.dcapp-vmem::before{content:"";width:1px;height:12px;background:#d8d8dd;margin-right:6px}',
      '.dcapp-vmem svg{width:14px;height:14px;flex:none}',
      '.dcapp-vmem b{font-weight:normal}',
      '.dcapp-vicons{display:flex;gap:0;margin-left:0;flex:none}',
      '.dcapp-vicons button{width:39px;height:32px;border:0;background:none;display:flex;align-items:center;justify-content:center;color:#7d7d84;padding:0}',
      '.dcapp-vicons svg{width:18px;height:18px}',
      '.dcapp-vmain{display:flex;align-items:center;gap:5px;flex:none;justify-self:center;grid-row:1;grid-column:2}',
      // 개추/비추는 가운데, 실베추·펌은 오른쪽, 수정·삭제는 그 아래 줄 가운데
      '.dcapp-vote{display:grid!important;grid-template-columns:minmax(0,1fr) auto minmax(0,1fr);align-items:center;padding:0 12px!important}',
      '.dcapp-vicons{display:flex;gap:0;margin:0!important;flex:none}',
      '.dcapp-vote{padding:0 12px}',
      '.dcapp-postact{display:flex;gap:4px;grid-row:2;grid-column:1 / -1;justify-self:stretch;justify-content:space-between;margin:16px 0 0!important;padding:0!important;flex:none}',
      '.dcapp-postact .grp{display:flex;gap:4px;margin-left:auto}',
      '.dcapp-postact button{width:69px;height:26px;padding:0;border:1px solid #c9c9cf;border-radius:5px;background:none;color:#3b4890;font-size:13px;font-weight:600}',
      '.dcapp-postact button.del{color:#e53935;border-color:#e8b4b1}',
      'html.darkmode .dcapp-postact button{border-color:#55565c;color:#9db0ff}',
      'html.darkmode .dcapp-postact button.del{color:#ff7b72;border-color:#6b4a48}',
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
    // 댓글: 고닉 아이콘·IP 뒤의 메모(식별코드)를 아이콘에 바짝 붙임 (기본 8px 여백이 벌어져 보였음). 글목록 메모는 그대로
    rules.push(
      'li.comment .ginfo-area .dcapp-memo,li.comment-add .ginfo-area .dcapp-memo{margin:0 0 0 4px!important}',
      // 고닉·반고닉 아이콘 스프라이트 상자(14px)는 오른쪽에 빈 여백이 있어서, 뒤따르는 메모와의 사이를 2px 당겨 바짝 붙임
      'li.comment .ginfo-area > .sp-nick:has(+ .dcapp-memo),li.comment-add .ginfo-area > .sp-nick:has(+ .dcapp-memo){margin-right:-2px!important}',
      // 댓글 고닉·반고닉 아이콘 수직 높이를 닉네임 글자 중앙에 맞춤
      'li.comment .ginfo-area > .sp-nick:not(.sp_hitnickcon),li.comment-add .ginfo-area > .sp-nick:not(.sp_hitnickcon),li.comment .ginfo-area .gonick:not(.sp_hitnickcon),li.comment-add .ginfo-area .gonick:not(.sp_hitnickcon),li.comment .ginfo-area .nogonick:not(.sp_hitnickcon),li.comment-add .ginfo-area .nogonick:not(.sp_hitnickcon){vertical-align:middle!important;position:relative!important;top:1.5px!important}'
    );
    // 홈 순위 카드 (v350): 실북갤·흥한갤 한 블록 + 갤러리·마이너갤·미니갤·인물갤 4칸 (좁은 화면은 세로, 700px 이상은 2×2)
    rules.push(
      '.dcapp-hc-raw{position:absolute!important;left:-9999px!important;top:0!important;width:1px!important;height:1px!important;overflow:hidden!important;opacity:0!important;pointer-events:none!important}',
      '.main-wrapping section.rank-group.dcapp-hc-host{background:transparent!important;box-shadow:none!important;border:0!important;padding:0!important;margin:0!important;position:relative}',
      '.dcapp-hc{display:flex;flex-direction:column;gap:12px;padding:12px 12px 16px;box-sizing:border-box}',
      '.dcapp-hc-card{background:#fff;border-radius:16px;padding:14px 14px 8px;box-shadow:0 1px 3px rgba(0,0,0,.05);box-sizing:border-box;margin:0;min-width:0;overflow:hidden}',
      '.dcapp-hc-top{padding:10px}',
      '.dcapp-hc-seg{display:flex;background:#f0f0f4;border-radius:12px;padding:3px}',
      '.dcapp-hc-seg button{flex:1;border:0;background:transparent;height:34px;border-radius:10px;font-size:15px;font-weight:600;color:#6b6b72}',
      '.dcapp-hc-seg button.on{background:#fff;color:#222;box-shadow:0 1px 2px rgba(0,0,0,.08)}',
      '.dcapp-hc-grid{display:flex;flex-direction:column;gap:12px}',
      '.dcapp-hc-title{margin:0 0 6px;font-size:16px;font-weight:700;color:#222;letter-spacing:-.3px}',
      '.dcapp-hc-list{list-style:none;margin:0;padding:0}',
      '.dcapp-hc-list li{border-bottom:1px solid #f0f0f4}',
      '.dcapp-hc-list li:last-child{border-bottom:0}',
      '.dcapp-hc-link{display:flex;align-items:center;gap:8px;padding:10px 2px;font-size:15px;color:#222;text-decoration:none;min-width:0}',
      '.dcapp-hc-no{flex:0 0 auto;min-width:20px;color:#8a8a90;font-weight:600;text-align:right}',
      '.dcapp-hc-tt{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
      '.dcapp-hc-ch{flex:0 0 auto;min-width:44px;font-size:12px;font-weight:700;text-align:right}',
      '.dcapp-hc-up{color:#e5484d}',
      '.dcapp-hc-down{color:#3b82f6}',
      '.dcapp-hc-new{color:#16a34a}',
      '.dcapp-hc-same{color:#9aa0a6}',
      'html.darkmode .dcapp-hc-up{color:#ff7b72}',
      'html.darkmode .dcapp-hc-down{color:#6ea8ff}',
      'html.darkmode .dcapp-hc-new{color:#4ade80}',
      'html.darkmode .dcapp-hc-same{color:#7d8290}',
      '.main-wrapping .sec-wrap .brick-lf{float:none!important;width:100%!important;max-width:none!important}',
      '.main-wrapping .sec-wrap .brick-rt{display:none!important}',
      '.main-wrapping,.main-wrapping .container,.main-wrapping .sec-wrap{max-width:none!important;width:100%!important}',
      '.dcapp-hc-empty{padding:12px 2px;color:#8a8a90;font-size:14px}',
      '.dcapp-hc-track{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;-webkit-overflow-scrolling:touch;touch-action:pan-x pan-y;margin:0 -14px}',
      '.dcapp-hc-track::-webkit-scrollbar{display:none}',
      '.dcapp-hc-page{flex:0 0 100%;min-width:100%;box-sizing:border-box;scroll-snap-align:start;padding:0 14px;margin:0;list-style:none}',
      '.dcapp-hc-dots{display:flex;justify-content:center;gap:6px;margin:6px 0 2px}',
      '.dcapp-hc-dot{width:6px;height:6px;border-radius:3px;background:#d1d1d6}',
      '.dcapp-hc-dot.on{background:#8e8e93;width:14px}',
      'html.darkmode .dcapp-hc-dot{background:#48484a}',
      'html.darkmode .dcapp-hc-dot.on{background:#aeaeb2}',
      '@media (min-width:700px){.dcapp-hc-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}}',
      'html.darkmode .dcapp-hc-card{background:#2c2c2e;box-shadow:none}',
      'html.darkmode .dcapp-hc-seg{background:#1c1c1e}',
      'html.darkmode .dcapp-hc-seg button{color:#9a9ca6}',
      'html.darkmode .dcapp-hc-seg button.on{background:#3a3a3c;color:#f2f2f7}',
      'html.darkmode .dcapp-hc-title{color:#f2f2f7}',
      'html.darkmode .dcapp-hc-link{color:#e5e5ea}',
      'html.darkmode .dcapp-hc-list li{border-bottom-color:rgba(255,255,255,.08)}'
    );
    // 디시 모바일 홈(m.dcinside.com/): 실북갤·흥한갤 등 칸을 앱 카드 모양으로 (회색 바탕 위 흰 카드, 둥근 모서리, 얇은 구분선). 다크모드도 같은 톤
    // .main-wrapping은 홈에만 있어서 다른 화면에는 나가지 않음
    rules.push(
      '.main-wrapping{background:#f2f2f7!important}',
      'html.darkmode .main-wrapping{background:#1c1c1e!important}',
      '.main-wrapping .sec-wrap .grid{margin:10px 12px!important;padding:14px 14px 8px!important;border:0!important;border-radius:16px!important;background:#fff!important;box-shadow:0 1px 3px rgba(0,0,0,.05)!important;box-sizing:border-box!important}',
      'html.darkmode .main-wrapping .sec-wrap .grid{background:#2c2c2e!important;box-shadow:none!important}',
      '.main-wrapping .rank-tit-box{padding:0 0 10px!important;margin:0 0 6px!important;border-bottom:1px solid #f0f0f4}',
      'html.darkmode .main-wrapping .rank-tit-box{border-bottom-color:rgba(255,255,255,.08)}',
      '.main-wrapping .rank-tit{font-size:16px!important;font-weight:700!important;color:#222!important;letter-spacing:-.3px}',
      'html.darkmode .main-wrapping .rank-tit{color:#f2f2f7!important}',
      '.main-wrapping .tab-basic{background:transparent!important;border:0!important}',
      '.main-wrapping .tab-basic .tab-lst{border-bottom:1px solid #f0f0f4}',
      'html.darkmode .main-wrapping .tab-basic .tab-lst{border-bottom-color:rgba(255,255,255,.08)}',
      '.main-wrapping .tab-child-lst > li{border-bottom:1px solid #f0f0f4}',
      '.main-wrapping .tab-child-lst > li:last-child{border-bottom:0}',
      'html.darkmode .main-wrapping .tab-child-lst > li{border-bottom-color:rgba(255,255,255,.08)}',
      '.main-wrapping .child-lnk .num{color:#8a8a90;font-weight:600}',
      'html.darkmode .main-wrapping .child-lnk .num{color:#9a9ca6}',
      'html.darkmode .main-wrapping .child-lnk{color:#e5e5ea}'
    );
    // 로그인 페이지(msign): 디시 헤더·광고·푸터는 숨기고 입력 카드를 앱 스타일로 다듬음.
    // 입력 칸(#code·#password)·로그인 버튼(#loginAction)·폼은 그대로 둬서 디시 로그인 스크립트와 자동 로그인이 그대로 동작함
    rules.push(
      'body:has(.login-group){background:#f2f2f7!important}',
      'html.darkmode body:has(.login-group){background:#1c1c1e!important}',
      '.login-group{min-height:100vh;min-height:100dvh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px 16px!important;box-sizing:border-box;background:none!important}',
      '.login-group .login-group-inner{width:100%;max-width:380px;box-sizing:border-box;padding:26px 22px 18px!important;border-radius:18px;background:#fff;box-shadow:0 6px 24px rgba(0,0,0,.08)}',
      'html.darkmode .login-group-inner{background:#2c2c2e;box-shadow:none}',
      '.login-group .dclogo{display:none!important}',
      '.login-group-inner::before{content:"디시인사이드 로그인";display:block;margin:0 0 22px;text-align:center;font-size:20px;font-weight:700;color:#3b4890}',
      'html.darkmode .login-group-inner::before{color:#a9b4f0}',
      '.login-brick-wid{width:100%!important;max-width:none!important;margin:0!important}',
      '.login-form3{border:0;margin:0;padding:0;min-width:0}',
      '.login-ipt-box{position:relative;margin:0 0 10px}',
      '.login-group .ipt{display:block;width:100%;height:48px;box-sizing:border-box;padding:0 14px;border:1px solid #d6d6dc;border-radius:12px;background:#fff;color:#222;font-size:16px;outline:0;-webkit-appearance:none}',
      '.login-group .ipt:focus{border-color:#3b4890;box-shadow:0 0 0 3px rgba(59,72,144,.16)}',
      '.login-group .ipt::placeholder{color:#9a9aa2}',
      'html.darkmode .login-group .ipt{background:#1c1c1e;border-color:#48484c;color:#eee}',
      '.login-group .btn-ico-del{display:none!important}',
      '.login-group .btn-login{display:block;width:100%;height:48px;margin:12px 0 0;border:0;border-radius:12px;background:#3b4890;color:#fff;font-size:16px;font-weight:700}',
      '.login-group .btn-login:active{opacity:.85}',
      '.login-check-box{margin:14px 0 0;text-align:center}',
      '.check-login{display:inline-flex;align-items:center;gap:6px}',
      '.chklbl{font-size:14px;color:#6e6e76}',
      'html.darkmode .chklbl{color:#b5b5bb}',
      '.login-search{display:flex;justify-content:center;flex-wrap:wrap;gap:6px 14px;margin:20px 0 0}',
      '.login-search a{font-size:13px;color:#8a8a90;text-decoration:none}',
      'html.darkmode .login-search a{color:#a5a5ab}',
      '.grid.adv-group,.kakao_ad_area,.footer,.menu_privacy{display:none!important}'
    );
    // 댓글 ⋯ 메뉴(수정·삭제)와 댓글 수정 칸: 디시 기능은 그대로 두고 모양만 앱 카드(둥근 모서리·여백·강조색·다크모드)로
    rules.push(
      '.comment-option{top:30px!important;right:0!important;width:124px!important;margin:0!important;padding:4px 0!important;border:0!important;border-radius:12px!important;background:#fff!important;box-shadow:0 6px 20px rgba(0,0,0,.14)!important;box-sizing:border-box!important;overflow:hidden!important;z-index:50!important}',
      '.comment-option li+li{border-top:1px solid #f0f0f4!important}',
      '.comment-option button{display:flex!important;align-items:center!important;gap:8px!important;width:100%!important;height:auto!important;margin:0!important;padding:10px 14px!important;border:0!important;background:none!important;font-size:14px!important;line-height:18px!important;font-weight:500!important;color:#222!important;text-align:left!important;box-sizing:border-box!important}',
      '.comment-option button:has(.opt-del),.comment-option button.opt-del{color:#e53935!important}',
      'html.darkmode .comment-option{background:#2c2c2e!important;box-shadow:0 6px 20px rgba(0,0,0,.45)!important}',
      'html.darkmode .comment-option li+li{border-color:#3d3d41!important}',
      'html.darkmode .comment-option button{color:#eee!important}',
      'html.darkmode .comment-option button:has(.opt-del),html.darkmode .comment-option button.opt-del{color:#ff7b72!important}',
      '.all-comment-lst li.edit{background:#f2f6ff!important}',
      'html.darkmode .all-comment-lst li.edit{background:#1f2433!important}',
      '.comment-edit{margin:8px 0 4px!important;border:1px solid #d6d8e2!important;border-radius:12px!important;background:#fff!important;overflow:hidden!important;box-sizing:border-box!important}',
      '.comment-edit-caption{display:block!important;width:100%!important;height:76px!important;margin:0!important;padding:10px 12px!important;border:0!important;outline:0!important;border-radius:0!important;background:transparent!important;font-size:15px!important;line-height:21px!important;color:#222!important;resize:none!important;box-sizing:border-box!important}',
      '.comment-edit .btm-wrt-btns{display:flex!important;align-items:center!important;justify-content:space-between!important;height:auto!important;padding:8px 10px!important;border-top:1px solid #eef0f6!important;background:#fafafc!important;box-sizing:border-box!important}',
      '.comment-edit .btm-wrt-btns .rt{position:static!important;display:flex!important;align-items:center!important;gap:8px!important;margin-left:auto!important}',
      '.comment-timer{font-size:13px!important;line-height:32px!important;color:#6e6e76!important;font-variant-numeric:tabular-nums}',
      '.comment-timer.red{color:#e53935!important}',
      '.btn-comment-cancel,.comment-edit .btn-comment-write{height:32px!important;min-width:56px!important;margin:0!important;padding:0 14px!important;border-radius:16px!important;font-size:14px!important;font-weight:700!important;line-height:30px!important;box-sizing:border-box!important}',
      '.btn-comment-cancel{border:1px solid #d6d8e2!important;background:#fff!important;color:#555!important}',
      '.comment-edit .btn-comment-write{border:0!important;background:#3b4890!important;color:#fff!important}',
      'html.darkmode .comment-edit{background:#1c1c1e!important;border-color:#48484c!important}',
      'html.darkmode .comment-edit-caption{color:#eee!important}',
      'html.darkmode .comment-edit .btm-wrt-btns{background:#252528!important;border-color:#3d3d41!important}',
      'html.darkmode .btn-comment-cancel{background:#2c2c2e!important;border-color:#48484c!important;color:#ddd!important}',
      'html.darkmode .comment-edit .btn-comment-write{background:#5a6bc4!important}',
      'html.darkmode .comment-timer{color:#a5a5ab!important}',
      'html.darkmode .comment-timer.red{color:#ff7b72!important}'
    );
    // 갤로그(고닉을 눌러 들어가는 개인 페이지, /gallog/…: 홈·게시물·댓글·스크랩·방명록 탭): 디시 머리글 줄·광고·푸터는 숨기고,
    // 탭과 카드·방명록 쓰기 칸·댓글을 앱 스타일로 (탭 구조·링크·입력 칸 id는 그대로라 디시 기능은 그대로 동작)
    rules.push(
      'body:has(.gallog-wrapping) .footer,.gallog-wrapping .footer,.gallog-wrapping .flex-header .lnk-lf,.gallog-wrapping .gotop,.gallog-wrapping .tip_box2,.gallog-wrapping .sns-box,.gallog-wrapping .adv-group,.gallog-wrapping .kakao_ad_area{display:none!important}',
      '.gallog-wrapping{background:#f2f2f7!important;min-height:100vh}',
      'html.darkmode .gallog-wrapping{background:#1c1c1e!important}',
      '.gallog-wrapping .flex-header{display:flex!important;align-items:center!important;justify-content:space-between!important;height:48px!important;padding:0 12px!important;background:#fff!important;border-bottom:1px solid #e6e6ea!important;box-sizing:border-box!important}',
      'html.darkmode .gallog-wrapping .flex-header{background:#1c1c1e!important;border-color:#2c2c2e!important}',
      '.gallog-wrapping .flex-header .ct{flex:1 1 auto!important;min-width:0!important;margin:0!important;padding:0 8px!important;text-align:center!important}',
      '.gallog-wrapping .flex-header .tit{display:block!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;font-size:16px!important;font-weight:700!important;color:#222!important}',
      'html.darkmode .gallog-wrapping .flex-header .tit{color:#eee!important}',
      '.gallog-wrapping .flex-header .rt{flex:none!important}',
      '.gallog-wrapping .set-setting{width:32px!important;height:32px!important;padding:0!important;border:0!important;background:none!important}',
      '.gallog-wrapping .profile-img img{width:28px!important;height:28px!important;border-radius:50%!important;object-fit:cover!important}',
      '.gallog-wrapping .nav{height:auto!important;line-height:normal!important;background:#fff!important;border-bottom:1px solid #e6e6ea!important}',
      'html.darkmode .gallog-wrapping .nav{background:#1c1c1e!important;border-color:#2c2c2e!important}',
      '.gallog-wrapping .menu-box ul{display:flex!important;overflow-x:auto!important;margin:0!important;padding:0 4px!important;list-style:none!important;-webkit-overflow-scrolling:touch}',
      '.gallog-wrapping .menu-box li{flex:1 0 auto!important;margin:0!important;padding:0!important;border:0!important}',
      '.gallog-wrapping .menu-box a{display:block!important;padding:12px 10px!important;font-size:14px!important;font-weight:600!important;color:#8a8a90!important;text-align:center!important;white-space:nowrap!important;text-decoration:none!important}',
      '.gallog-wrapping .menu-box li.on a{color:#3b4890!important;box-shadow:inset 0 -2px 0 #3b4890!important}',
      'html.darkmode .gallog-wrapping .menu-box a{color:#8e8e93!important}',
      'html.darkmode .gallog-wrapping .menu-box li.on a{color:#a9b4f0!important;box-shadow:inset 0 -2px 0 #a9b4f0!important}',
      '.gallog-wrapping .sec-wrap-sub{margin:0!important;padding:10px 12px 28px!important;background:none!important}',
      '.gallog-wrapping .brick-wid{width:100%!important;max-width:none!important;margin:0!important;padding:0!important;min-width:0!important}',
      '.gallog-wrapping .brick-wid > section.grid{display:block!important;float:none!important;width:auto!important;margin:0 0 12px!important;padding:14px 16px!important;box-sizing:border-box!important;border:0!important;border-radius:14px!important;background:#fff!important;box-shadow:0 1px 4px rgba(0,0,0,.06)!important}',
      'html.darkmode .gallog-wrapping .brick-wid > section.grid{background:#2c2c2e!important;box-shadow:none!important}',
      '.gallog-wrapping .gall-tit-box{display:flex!important;align-items:center!important;justify-content:space-between!important;padding:0 44px 2px 0!important}',
      '.gallog-wrapping .gall-tit{font-size:16px!important;font-weight:700!important;color:#222!important}',
      '.gallog-wrapping .gall-tit .count2,.gallog-wrapping .md-tit .ct2{color:#3b4890!important;font-weight:600!important;margin-left:4px!important;font-size:14px!important}',
      'html.darkmode .gallog-wrapping .gall-tit{color:#eee!important}',
      'html.darkmode .gallog-wrapping .gall-tit .count2,html.darkmode .gallog-wrapping .md-tit .ct2{color:#a9b4f0!important}',
      '.gallog-wrapping .today-visit{font-size:12px!important;color:#8a8a90!important}',
      '.gallog-wrapping .today-visit .ct{color:#3b4890!important;font-weight:700!important}',
      'html.darkmode .gallog-wrapping .today-visit .ct{color:#a9b4f0!important}',
      '.gallog-wrapping .md-tit-box{display:block!important;padding:0 0 10px!important;margin:0!important;border:0!important;background:none!important}',
      '.gallog-wrapping .md-tit-box .md-lnk{display:block!important;width:100%!important}',
      '.gallog-wrapping .gall-tit-box,.gallog-wrapping .gall-detail-lst,.gallog-wrapping .gall-detail-lst > li,.gallog-wrapping .no-mgall,.gallog-wrapping .today-visit{background:none!important}',
      '.gallog-wrapping .md-tit{display:block!important;margin:0!important;font-size:16px!important;font-weight:700!important;color:#222!important;line-height:22px!important}',
      '.gallog-wrapping .md-tit a{display:inline!important;font-size:16px!important;font-weight:700!important;color:#222!important;text-decoration:none!important}',
      '.gallog-wrapping .md-tit .ct2{vertical-align:middle!important}',
      'html.darkmode .gallog-wrapping .md-tit a{color:#eee!important}',
      '.gallog-wrapping .btn-mline{display:inline-block!important;margin:0 0 0 auto!important;padding:2px 8px!important;border:1px solid #d6d6dc!important;border-radius:10px!important;background:none!important;font-size:12px!important;font-weight:500!important;color:#8a8a90!important}',
      'html.darkmode .gallog-wrapping .btn-mline{border-color:#48484c!important;color:#a5a5ab!important}',
      '.gallog-wrapping .no-mgall{padding:22px 0 8px!important;text-align:center!important}',
      '.gallog-wrapping .no-mgall .txt{font-size:14px!important;color:#8a8a90!important}',
      '.gallog-wrapping ul.gall-detail-lst{margin:0!important;padding:0!important;list-style:none!important}',
      '.gallog-wrapping ul.gall-detail-lst > li{margin:0!important;padding:12px 0!important;background-image:none!important;border-top:1px solid #f0f0f4!important;list-style:none!important}',
      '.gallog-wrapping ul.gall-detail-lst > li:first-child{border-top:0!important}',
      'html.darkmode .gallog-wrapping ul.gall-detail-lst > li{border-color:#3d3d41!important}',
      '.gallog-wrapping .gall-detail-lnktb,.gallog-wrapping .gall-detail-lnktb .lt{display:block!important;position:static!important;width:auto!important;max-width:none!important;table-layout:auto!important;white-space:normal!important;overflow:visible!important;text-overflow:clip!important;padding:0!important}',
      '.gallog-wrapping .gall-detail-lnktb .txt{display:block!important;font-size:15px!important;line-height:21px!important;color:#222!important;word-break:break-all!important;overflow-wrap:anywhere!important;white-space:normal!important}',
      'html.darkmode .gallog-wrapping .gall-detail-lnktb .txt{color:#eee!important}',
      '.gallog-wrapping .gall-detail-lnktb ul.ginfo{display:flex!important;flex-wrap:wrap!important;gap:8px!important;margin:4px 0 0!important;padding:0!important;font-size:12px!important;color:#8a8a90!important}',
      '.gallog-wrapping .gall-detail-lnktb ul.ginfo li{font-size:12px!important;color:#8a8a90!important}',
      '.gallog-wrapping #guest_write{margin:0!important}',
      '.gallog-wrapping .comment-write-btm.nomg:not(:has(textarea)){display:none!important}',
      '.gallog-wrapping .comment-write-btm.nomg{padding:0!important;border:0!important;background:none!important}',
      '.gallog-wrapping #guest_write .comment-write{border:0!important;border-radius:0!important;background:none!important;padding:0!important;box-sizing:border-box!important}',
      '.gallog-wrapping #guest_write .who-lst{display:flex!important;gap:8px!important;margin:0 0 8px!important;padding:0!important;list-style:none!important}',
      '.gallog-wrapping #guest_write .who-lst li{flex:1 1 0!important;min-width:0!important;margin:0!important}',
      '.gallog-wrapping #guest_write .ipt{display:block!important;width:100%!important;height:38px!important;box-sizing:border-box!important;padding:0 10px!important;border:1px solid #d6d6dc!important;border-radius:10px!important;background:#fff!important;color:#222!important;font-size:15px!important;outline:0!important}',
      'html.darkmode .gallog-wrapping #guest_write .ipt{background:#2c2c2e!important;border-color:#48484c!important;color:#eee!important}',
      '.gallog-wrapping #guest_write .comment-caption{display:block!important;width:100%!important;min-height:64px!important;margin:0!important;padding:10px!important;border:1px solid #d6d6dc!important;border-radius:10px!important;background:#fff!important;color:#222!important;font-size:15px!important;line-height:21px!important;box-sizing:border-box!important;resize:none!important;outline:0!important}',
      'html.darkmode .gallog-wrapping #guest_write .comment-caption{background:#2c2c2e!important;border-color:#48484c!important;color:#eee!important}',
      '.gallog-wrapping #guest_write .btm-wrt-btns{display:flex!important;justify-content:flex-end!important;height:auto!important;margin:8px 0 0!important;padding:0!important;border:0!important}',
      '.gallog-wrapping #guest_write .btm-wrt-btns .rt{position:static!important}',
      'html.darkmode .gallog-wrapping #guest_write .btm-wrt-btns,html.darkmode .gallog-wrapping .comment-write-btm{background:transparent!important}',
      '.gallog-wrapping .sel-box,.gallog-wrapping .sel-wrap,.gallog-wrapping .gallog-sel,.gallog-wrapping .btm-sel-box,.gallog-wrapping .list-sel-box,.gallog-wrapping .sort-box,.gallog-wrapping .sub-menu,.gallog-wrapping .gallog-menu-box,.gallog-wrapping div:has(> .sel-box),.gallog-wrapping div:has(> select.sel),.gallog-wrapping div:has(> .btn-mline),.gallog-wrapping section:has(> .sel-box){border:0!important;border-top:0!important;border-bottom:0!important;background:none!important;background-color:transparent!important;box-shadow:none!important;outline:0!important}',
      'html.darkmode .gallog-wrapping .sel-box,html.darkmode .gallog-wrapping .sel-wrap,html.darkmode .gallog-wrapping .gallog-sel,html.darkmode .gallog-wrapping .btm-sel-box,html.darkmode .gallog-wrapping .list-sel-box,html.darkmode .gallog-wrapping .sort-box,html.darkmode .gallog-wrapping .sub-menu,html.darkmode .gallog-wrapping .gallog-menu-box,html.darkmode .gallog-wrapping div:has(> .sel-box),html.darkmode .gallog-wrapping div:has(> select.sel),html.darkmode .gallog-wrapping div:has(> .btn-mline),html.darkmode .gallog-wrapping section:has(> .sel-box){border:0!important;border-top:0!important;border-bottom:0!important;background:none!important;background-color:transparent!important;box-shadow:none!important}',
      '.gallog-wrapping select.sel{border:0!important;background:none!important;background-color:transparent!important;box-shadow:none!important;outline:0!important;margin-right:44px!important}',
      'html.darkmode .gallog-wrapping select.sel{color:#eee!important;border:0!important;background:none!important;background-color:transparent!important}',
      '.dcapp-gallog-hide{display:none!important}',
      // 갤러리 관리 내역(/managehistory/...): 앱 카드 스타일 + 다크모드 대응
      'html.dcapp-managehistory body{background:#f2f2f7!important}',
      'html.darkmode.dcapp-managehistory body{background:#000!important}',
      'html.dcapp-managehistory header,html.dcapp-managehistory .header,html.dcapp-managehistory footer,html.dcapp-managehistory .footer,html.dcapp-managehistory .all-tit-box{display:none!important}',
      'html.dcapp-managehistory .tab-twoline{background:transparent!important;border:0!important;padding:10px 12px 8px!important}',
      'html.dcapp-managehistory .tab-twoline ul.tab-lst{display:flex!important;gap:4px!important;padding:4px!important;border-radius:12px!important;background:rgba(120,120,128,.12)!important;border:0!important}',
      'html.darkmode.dcapp-managehistory .tab-twoline ul.tab-lst{background:rgba(120,120,128,.24)!important}',
      'html.dcapp-managehistory .tab-twoline ul.tab-lst > li{flex:1 1 0!important;border:0!important;background:transparent!important;border-radius:9px!important;overflow:hidden!important}',
      'html.dcapp-managehistory .tab-twoline ul.tab-lst > li > a,html.dcapp-managehistory .tab-twoline ul.tab-lst > li > button{display:flex!important;align-items:center!important;justify-content:center!important;width:100%!important;height:34px!important;border:0!important;border-radius:9px!important;font-size:13px!important;font-weight:600!important;background:transparent!important;color:#636366!important}',
      'html.darkmode.dcapp-managehistory .tab-twoline ul.tab-lst > li > a,html.darkmode.dcapp-managehistory .tab-twoline ul.tab-lst > li > button{color:#aeaeb2!important}',
      'html.dcapp-managehistory .tab-twoline ul.tab-lst > li.on > a,html.dcapp-managehistory .tab-twoline ul.tab-lst > li.on > button,html.dcapp-managehistory .tab-twoline ul.tab-lst > li > a.on{background:#fff!important;color:#1c1c1e!important;box-shadow:0 1px 3px rgba(0,0,0,.12)!important}',
      'html.darkmode.dcapp-managehistory .tab-twoline ul.tab-lst > li.on > a,html.darkmode.dcapp-managehistory .tab-twoline ul.tab-lst > li.on > button,html.darkmode.dcapp-managehistory .tab-twoline ul.tab-lst > li > a.on{background:#2c2c2e!important;color:#f5f5f7!important}',
      'html.dcapp-managehistory .ct-info-box{margin:4px 12px 10px!important;padding:12px 14px!important;border-radius:12px!important;border:0!important;background:rgba(120,120,128,.08)!important;font-size:13px!important;line-height:1.45!important}',
      'html.darkmode.dcapp-managehistory .ct-info-box{background:#1c1c1e!important;color:#aeaeb2!important}',
      'html.dcapp-managehistory .adm-detail-lst{background:#fff!important;border-radius:14px!important;margin:0 12px 10px!important;padding:10px 14px!important;border:1px solid rgba(0,0,0,.05)!important;box-shadow:0 1px 2px rgba(0,0,0,.04)!important}',
      'html.darkmode.dcapp-managehistory .adm-detail-lst{background:#1c1c1e!important;border-color:rgba(255,255,255,.08)!important;box-shadow:none!important}',
      'html.dcapp-managehistory ul.adm-detail-inr{display:flex!important;flex-direction:column!important;gap:0!important;background:transparent!important;border:0!important;padding:0!important;margin:0!important}',
      'html.dcapp-managehistory ul.adm-detail-inr > li{background:transparent!important;border:0!important;border-bottom:1px solid rgba(120,120,128,.12)!important;border-radius:0!important;padding:6px 0!important;margin:0!important;box-shadow:none!important}',
      'html.dcapp-managehistory ul.adm-detail-inr > li:last-child{border-bottom:0!important}',
      'html.dcapp-managehistory .con-search-box{margin:0 12px 10px!important;padding:0!important;background:transparent!important;border:0!important}',
      'html.dcapp-managehistory .con-search-box > div,html.dcapp-managehistory .con-search-box .search-box,html.dcapp-managehistory .con-search-box .sch-box{display:flex!important;align-items:center!important;border-radius:12px!important;border:1px solid rgba(120,120,128,.22)!important;background:#fff!important;overflow:hidden!important;padding:0 10px!important;height:40px!important;box-sizing:border-box!important}',
      'html.darkmode.dcapp-managehistory .con-search-box > div,html.darkmode.dcapp-managehistory .con-search-box .search-box,html.darkmode.dcapp-managehistory .con-search-box .sch-box{background:#1c1c1e!important;border-color:rgba(255,255,255,.14)!important}',
      'html.dcapp-managehistory .con-search-box input[type="text"],html.dcapp-managehistory .con-search-box input[type="search"],html.dcapp-managehistory #search{border:0!important;outline:0!important;background:transparent!important;font-size:14px!important;height:38px!important;flex:1 1 auto!important}',
      'html.darkmode.dcapp-managehistory .con-search-box input[type="text"],html.darkmode.dcapp-managehistory .con-search-box input[type="search"],html.darkmode.dcapp-managehistory #search{color:#f5f5f7!important}',
      // 마이너/메이저 갤러리 정보 팝업: 앱 둥근 카드 스타일 + 다크모드
      '#minor_info_pop .layer-popup-inner,#major_info_pop .layer-popup-inner,#minor_info_pop .popup-inner,#major_info_pop .popup-inner,.layer-center-popup[id*="info_pop"] .layer-popup-inner{border-radius:18px!important;overflow:hidden!important;box-shadow:0 14px 40px rgba(0,0,0,.32)!important;border:1px solid rgba(0,0,0,.06)!important;background:#fff!important}',
      'html.darkmode #minor_info_pop .layer-popup-inner,html.darkmode #major_info_pop .layer-popup-inner,html.darkmode #minor_info_pop .popup-inner,html.darkmode #major_info_pop .popup-inner,html.darkmode .layer-center-popup[id*="info_pop"] .layer-popup-inner{background:#1c1c1e!important;border-color:rgba(255,255,255,.12)!important}',
      '#minor_info_pop .pp-box,#major_info_pop .pp-box,.layer-center-popup[id*="info_pop"] .pp-box{background:#fff!important;border-radius:18px!important;padding-bottom:16px!important;border:0!important}',
      'html.darkmode #minor_info_pop .pp-box,html.darkmode #major_info_pop .pp-box,html.darkmode .layer-center-popup[id*="info_pop"] .pp-box{background:#1c1c1e!important;color:#f5f5f7!important}',
      '#minor_info_pop .pp-tit-box,#major_info_pop .pp-tit-box,.layer-center-popup[id*="info_pop"] .pp-tit-box{background:transparent!important;border-bottom:1px solid rgba(120,120,128,.16)!important;padding:14px 16px!important;display:flex!important;align-items:center!important;justify-content:space-between!important}',
      '#minor_info_pop .pp-tit2,#major_info_pop .pp-tit2,.layer-center-popup[id*="info_pop"] .pp-tit2{font-size:16px!important;font-weight:700!important;letter-spacing:-.01em!important}',
      '#minor_info_pop .btn-x-close,#major_info_pop .btn-x-close,.layer-center-popup[id*="info_pop"] .btn-x-close{border-radius:999px!important;background-color:rgba(120,120,128,.14)!important}',
      'html.darkmode #minor_info_pop .btn-x-close,html.darkmode #major_info_pop .btn-x-close,html.darkmode .layer-center-popup[id*="info_pop"] .btn-x-close{background-color:rgba(255,255,255,.14)!important}',
      '#minor_info_pop .gall_history_btn,#major_info_pop .gall_history_btn,.layer-center-popup[id*="info_pop"] button[onclick*="managehistory"]{border-radius:12px!important;font-weight:600!important;height:40px!important}',
      'div.container > div.sec-wrap-sub > div.brick-wid > section.grid.clkhigh > div{display:none!important}',
      '.gallog-wrapping #guest_write .btn-comment-write{height:34px!important;min-width:64px!important;padding:0 16px!important;border:0!important;border-radius:17px!important;background:#3b4890!important;color:#fff!important;font-size:14px!important;font-weight:700!important}',
      'html.darkmode .gallog-wrapping #guest_write .btn-comment-write{background:#5a6bc4!important}',
      '.gallog-wrapping .all-comment-lst li.comment{position:relative!important;padding:12px 0!important;background:none!important;border-top:1px solid #f0f0f4!important}',
      '.gallog-wrapping .all-comment-lst li.comment:first-child{border-top:0!important}',
      'html.darkmode .gallog-wrapping .all-comment-lst li.comment{border-color:#3d3d41!important}',
      '.gallog-wrapping .all-comment-lst .nick{font-size:14px!important;font-weight:600!important;color:#222!important;text-decoration:none!important}',
      'html.darkmode .gallog-wrapping .all-comment-lst .nick{color:#eee!important}',
      '.gallog-wrapping .all-comment-lst .txt{margin:4px 0 0!important;font-size:15px!important;line-height:21px!important;color:#222!important;word-break:break-all!important}',
      'html.darkmode .gallog-wrapping .all-comment-lst .txt{color:#eee!important}',
      '.gallog-wrapping .gallog-wrap-lst{background:none!important}',
      '.gallog-wrapping .gallog-wrap-lst .all-comment-lst li .date,.gallog-wrapping .gallog-wrap-lst .all-comment-lst .comment-add .date{position:static!important;left:auto!important;bottom:auto!important;display:inline-block!important;margin-top:6px!important;font-size:12px!important;color:#8a8a90!important}',
      '.gallog-wrapping .gallog-wrap-lst .all-comment-lst li .modify{position:static!important;top:auto!important;right:auto!important;bottom:auto!important;display:inline-flex!important;align-items:center!important;margin:6px 0 0 8px!important}',
      '.gallog-wrapping .all-comment-lst .modify button,.gallog-wrapping .all-comment-lst .modify a{height:24px!important;padding:0 8px!important;border:1px solid #d6d6dc!important;border-radius:12px!important;background:none!important;font-size:12px!important;color:#8a8a90!important}',
      'html.darkmode .gallog-wrapping .all-comment-lst .modify button,html.darkmode .gallog-wrapping .all-comment-lst .modify a{border-color:#48484c!important;color:#a5a5ab!important}'
    );
    // 글 본문의 디시 투표 상자(제목·보기·썸네일·득표 막대·투표하기/공유): 디시 클래스는 그대로 두고 모양만 앱 카드로
    rules.push(
      '.vote-view-scope{margin:14px 0!important;border:0!important;background:transparent!important;box-shadow:none!important;padding:0!important}',
      'iframe[id^="vote_iframe"],.thum-txtin iframe[src*="vote"],.thum-txtin iframe[src*="poll"]{width:100%!important;border:0!important;background:transparent!important;box-shadow:none!important;border-radius:16px!important;overflow:hidden!important}',
      '.vote-view-inner{border:1px solid rgba(0,0,0,0.12)!important;border-radius:16px!important;background:#fff!important;box-shadow:none!important;overflow:hidden!important;padding:0!important;box-sizing:border-box!important}',
      '.vote-view-top{padding:14px 16px!important;border-bottom:1px solid #f0f0f4!important;background:#fff!important}',
      '.vote-view-top .vote-tit-inner{font-size:16px!important;font-weight:700!important;color:#222!important;letter-spacing:-.3px!important}',
      '.vote-date-lst li{font-size:12px!important;color:#8a8a90!important;letter-spacing:0!important}',
      '.vote-date-lst li::before{background:#d6d6dc!important}',
      '.vote-view-result .all-ct{padding:12px 16px!important}',
      '.vote-view-result .vote-join{font-size:13px!important;color:#666!important;letter-spacing:0!important}',
      '.vote-view-result .vote-join .ct{color:#3b4890!important;font-weight:700!important}',
      '.vote-view-result .vote-join:before{background-color:#d6d6dc!important}',
      '.vote-view-result .vote-go-txt{font-size:13px!important;color:#3b4890!important;font-weight:600!important;text-decoration:none!important;letter-spacing:0!important}',
      '.vote-ask-wrap{background:#f7f8fb!important;padding:14px!important;border-radius:12px!important;border:0!important}',
      '.vote-ask-lst li+li{margin-top:8px!important}',
      '.vote-ask-lst li .lnk{box-sizing:border-box!important;min-height:52px!important;height:auto!important;padding:8px 12px!important;border:1px solid #e3e5ee!important;border-radius:12px!important;background:#fff!important}',
      '.vote-ask-lst li.on .lnk,.vote-ask-lst li.pick{border:2px solid #3b4890!important;padding:7px 11px!important}',
      '.vote-ask-lst .vote-thum{width:40px!important;height:40px!important;border:0!important;border-radius:10px!important;overflow:hidden!important;margin-right:10px!important}',
      '.vote-ask-lst .vote-txt{font-size:15px!important;color:#222!important;height:auto!important;min-height:40px!important;line-height:1.3!important;letter-spacing:0!important}',
      '.vote-ask-lst li.on .vote-txt{color:#3b4890!important;font-weight:700!important}',
      '.vote-gp-lst li{margin-top:8px!important;padding:12px 14px!important;border-radius:12px!important;background:#fff!important;box-shadow:0 1px 3px rgba(0,0,0,.05)!important}',
      '.vote-gp-lst li:first-child{margin-top:0!important;padding-top:12px!important}',
      '.vote-gp-lst .vote-txt{font-size:15px!important;color:#222!important;font-weight:600!important;letter-spacing:0!important}',
      '.vote-gp-lst .gp-img{height:10px!important;border-radius:6px!important;background:#ececf1!important}',
      '.vote-gp-lst .gp-percent{height:10px!important;border-radius:6px!important;background:#a9b0c8!important}',
      '.vote-gp-lst li:first-child .gp-percent{background:#3b4890!important}',
      '.vote-gp-lst .percent{font-size:14px!important;color:#3b4890!important;font-weight:700!important}',
      '.vote-gp-lst .vote-ct{font-size:12px!important;color:#8a8a90!important}',
      '.vote-thum-img{width:44px!important;height:44px!important;border:0!important;border-radius:10px!important;margin-right:10px!important}',
      '.vote-btn-box{margin:0!important;padding:14px 16px 16px!important;text-align:center!important}',
      '.btn-vote-go{height:38px!important;padding:0 28px!important;border:0!important;border-radius:19px!important;background:#3b4890!important;color:#fff!important;font-size:15px!important;font-weight:700!important}',
      '.btn-vote-sns,.vote-btn-box .sp-sharesns,.vote-btn-box button[class*="share"],.vote-btn-box a[class*="share"]{display:inline-flex!important;align-items:center!important;justify-content:center!important;width:38px!important;height:38px!important;border:1px solid rgba(0,0,0,0.08)!important;border-radius:50%!important;background:#f2f3f8!important;box-sizing:border-box!important;vertical-align:middle!important}',
      '.vote-btn-box .btn-vote-go + .sp-sharesns{margin-left:8px!important}',
      '.vote-status-info{padding:12px 16px 18px!important;background:#fff!important}',
      '.vote-sns-txt{color:#8a8a90!important}',
      '.vote-day{color:#8a8a90!important}',
      '.vote-orilnk-box{margin:0 0 12px!important;padding:0 16px!important}',
      '.vote-ori-lnk,.vote-ori-lnk2{color:#8a8a90!important}',
      'html.darkmode .vote-view-inner{background:#2c2c2e!important;border-color:rgba(255,255,255,0.16)!important;box-shadow:none!important}',
      'html.darkmode .vote-view-top{background:#2c2c2e!important;border-color:#3d3d41!important}',
      'html.darkmode .vote-view-top .vote-tit-inner{color:#eee!important}',
      'html.darkmode .vote-date-lst li{color:#a5a5ab!important}',
      'html.darkmode .vote-date-lst li::before,html.darkmode .vote-view-result .vote-join:before{background-color:#55565c!important}',
      'html.darkmode .vote-view-result .vote-join{color:#c7c7cc!important}',
      'html.darkmode .vote-view-result .vote-join .ct,html.darkmode .vote-view-result .vote-go-txt{color:#a9b4f0!important}',
      'html.darkmode .vote-ask-wrap{background:#1c1c1e!important}',
      'html.darkmode .vote-ask-lst li .lnk{background:#2c2c2e!important;border-color:#48484c!important}',
      'html.darkmode .vote-ask-lst li.on .lnk,html.darkmode .vote-ask-lst li.pick{border-color:#7d8ee0!important}',
      'html.darkmode .vote-ask-lst .vote-txt{color:#eee!important}',
      'html.darkmode .vote-ask-lst li.on .vote-txt{color:#a9b4f0!important}',
      'html.darkmode .vote-gp-lst li{background:#2c2c2e!important;box-shadow:none!important}',
      'html.darkmode .vote-gp-lst .vote-txt{color:#eee!important}',
      'html.darkmode .vote-gp-lst .gp-img{background:#48484c!important}',
      'html.darkmode .vote-gp-lst .gp-percent{background:#7a7d8c!important}',
      'html.darkmode .vote-gp-lst li:first-child .gp-percent{background:#7d8ee0!important}',
      'html.darkmode .vote-gp-lst .percent{color:#a9b4f0!important}',
      'html.darkmode .vote-gp-lst .vote-ct{color:#a5a5ab!important}',
      'html.darkmode .btn-vote-sns,html.darkmode .vote-btn-box .sp-sharesns,html.darkmode .vote-btn-box button[class*="share"],html.darkmode .vote-btn-box a[class*="share"]{background:#3a3a3c!important;border-color:rgba(255,255,255,0.12)!important}',
      'html.darkmode .vote-status-info{background:#2c2c2e!important}',
      'html.darkmode .vote-sns-txt,html.darkmode .vote-day,html.darkmode .vote-ori-lnk,html.darkmode .vote-ori-lnk2{color:#a5a5ab!important}',
      // 본문 내 인라인 투표([class*="vote"] / [class*="poll"]): 바깥 래퍼 이중 테두리·패딩 제거
      '.thum-txtin > div[class*="vote"],.thum-txtin > div[class*="poll"]{margin:14px 0!important;border:0!important;background:transparent!important;box-shadow:none!important;padding:0!important;box-sizing:border-box!important}',
      '.vote_box,.vote-box,.dc_vote,.vote_wrap,.vote-wrap,.poll_box,.poll-box{margin:14px 0!important;border:1px solid rgba(0,0,0,0.12)!important;border-radius:16px!important;background:#fff!important;box-shadow:none!important;overflow:hidden!important;padding:14px 16px!important;box-sizing:border-box!important}',
      'html.darkmode .vote_box,html.darkmode .vote-box,html.darkmode .dc_vote,html.darkmode .vote_wrap,html.darkmode .vote-wrap,html.darkmode .poll_box,html.darkmode .poll-box{background:#2c2c2e!important;border-color:rgba(255,255,255,0.16)!important;box-shadow:none!important;color:#eee!important}',
      '.thum-txtin [class*="vote"] [class*="tit"],.thum-txtin [class*="poll"] [class*="tit"],.vote_box .vote_tit,.vote-box .vote-tit,.dc_vote .vote_tit{font-size:16px!important;font-weight:700!important;color:#222!important;margin:0 0 10px!important}',
      '.thum-txtin [class*="vote"] li,.thum-txtin [class*="poll"] li,.vote_box .vote_list li,.vote-box .vote-list li,.dc_vote li{margin-top:8px!important;padding:10px 12px!important;border:1px solid #e3e5ee!important;border-radius:12px!important;background:#f7f8fb!important}',
      '.thum-txtin [class*="vote"] [class*="bar"],.thum-txtin [class*="poll"] [class*="bar"],.vote_box .vote_bar,.vote-box .vote-bar{height:10px!important;border-radius:6px!important;background:#ececf1!important;overflow:hidden!important}',
      '.thum-txtin [class*="vote"] [class*="bar"] > span,.thum-txtin [class*="poll"] [class*="bar"] > span,.vote_box .vote_bar > span,.vote-box .vote-bar > span,.vote_box .vote_per,.vote-box .vote-per{border-radius:6px!important;background:#3b4890!important}',
      '.thum-txtin [class*="vote"] button,.thum-txtin [class*="poll"] button,.vote_box .btn_vote,.vote-box .btn-vote{border-radius:18px!important}',
      'html.darkmode .thum-txtin [class*="vote"] [class*="tit"],html.darkmode .thum-txtin [class*="poll"] [class*="tit"],html.darkmode .vote_box .vote_tit,html.darkmode .vote-box .vote-tit,html.darkmode .dc_vote .vote_tit{color:#eee!important}',
      'html.darkmode .thum-txtin [class*="vote"] li,html.darkmode .thum-txtin [class*="poll"] li,html.darkmode .vote_box .vote_list li,html.darkmode .vote-box .vote-list li,html.darkmode .dc_vote li{background:#1c1c1e!important;border-color:#48484c!important;color:#eee!important}',
      'html.darkmode .thum-txtin [class*="vote"] [class*="bar"],html.darkmode .thum-txtin [class*="poll"] [class*="bar"],html.darkmode .vote_box .vote_bar,html.darkmode .vote-box .vote-bar{background:#48484c!important}',
      'html.darkmode .thum-txtin [class*="vote"] [class*="bar"] > span,html.darkmode .thum-txtin [class*="poll"] [class*="bar"] > span,html.darkmode .vote_box .vote_bar > span,html.darkmode .vote-box .vote-bar > span{background:#7d8ee0!important}'
    );
    // 투표 '공유하기' 버튼(투표 완료 줄의 공유 아이콘): 기본 네모 회색 테두리 대신 둥근 원형 버튼 + 앱 색 아이콘 (아이콘은 마스크로 그려 스프라이트에 기대지 않음)
    rules.push(
      '.vote-status-info .sp-sharesns,.vote-btn-box .sp-sharesns,.btn-vote-sns{display:inline-flex!important;align-items:center!important;justify-content:center!important;position:relative!important;box-sizing:border-box!important;width:38px!important;height:38px!important;min-width:38px!important;margin:0 0 0 8px!important;padding:0!important;border:1px solid #e3e5ee!important;border-radius:50%!important;background-color:#fff!important;background-image:none!important;box-shadow:none!important;font-size:0!important;line-height:0!important;text-indent:-9999px!important;overflow:hidden!important;vertical-align:middle!important}',
      '.vote-status-info .sp-sharesns::after,.vote-btn-box .sp-sharesns::after,.btn-vote-sns::after{content:none!important;display:none!important}',
      '.vote-status-info .sp-sharesns::before,.vote-btn-box .sp-sharesns::before,.btn-vote-sns::before{content:""!important;display:block!important;width:18px!important;height:18px!important;background-color:#3b4890!important;background-image:none!important;-webkit-mask-image:url("data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 24 24%27%3E%3Cpath d=%27M12 3v12M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7%27 fill=%27none%27 stroke=%27%23000%27 stroke-width=%272%27 stroke-linecap=%27round%27 stroke-linejoin=%27round%27/%3E%3C/svg%3E")!important;-webkit-mask-repeat:no-repeat!important;-webkit-mask-position:center!important;-webkit-mask-size:contain!important;mask-image:url("data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 24 24%27%3E%3Cpath d=%27M12 3v12M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7%27 fill=%27none%27 stroke=%27%23000%27 stroke-width=%272%27 stroke-linecap=%27round%27 stroke-linejoin=%27round%27/%3E%3C/svg%3E")!important;mask-repeat:no-repeat!important;mask-position:center!important;mask-size:contain!important;text-indent:0!important}',
      'html.darkmode .vote-status-info .sp-sharesns,html.darkmode .vote-btn-box .sp-sharesns,html.darkmode .btn-vote-sns{background-color:#3a3a3c!important;border-color:rgba(255,255,255,0.12)!important}',
      'html.darkmode .vote-status-info .sp-sharesns::before,html.darkmode .vote-btn-box .sp-sharesns::before,html.darkmode .btn-vote-sns::before{background-color:#a9b4f0!important}'
    );
    // 갤로그 '방명록 차단 설정' 팝업: 각진 박스 대신 둥근 카드, 둥근 X, 둥근 입력창, 알약형 저장 버튼 (다크모드 포함)
    rules.push(
      '#guestbook_block_setting .layer-popup-inner{box-sizing:border-box!important;max-width:calc(100% - 32px)!important;width:340px!important;border-radius:18px!important;background:#fff!important;overflow:hidden!important;box-shadow:0 10px 30px rgba(0,0,0,.2)!important;text-align:left!important;white-space:normal!important}',
      'html.darkmode #guestbook_block_setting .layer-popup-inner{background:#2c2c2e!important;box-shadow:none!important}',
      '#guestbook_block_setting .ly-tit-box{border:0!important;background:none!important;padding:16px 56px 0 18px!important;min-height:0!important}',
      '#guestbook_block_setting .ly-tit-box .tit{padding:0!important;font-size:17px!important;font-weight:700!important;color:#222!important;letter-spacing:0!important}',
      'html.darkmode #guestbook_block_setting .ly-tit-box .tit{color:#eee!important}',
      '#guestbook_block_setting .ly-tit-box .rt{top:12px!important;right:12px!important;transform:none!important}',
      '#guestbook_block_setting .btn-x-close{width:28px!important;height:28px!important;border:0!important;border-radius:14px!important;background:#f0f0f4!important;position:relative!important}',
      'html.darkmode #guestbook_block_setting .btn-x-close{background:#3a3a3c!important}',
      '#guestbook_block_setting .gallog-set-ly{padding:12px 18px 18px!important}',
      '#guestbook_block_setting .form-minifx-lst > li{border:0!important;padding:0 0 10px!important}',
      '#guestbook_block_setting .txtlbl{font-size:13px!important;color:#6e6e76!important;margin:0 0 6px!important}',
      'html.darkmode #guestbook_block_setting .txtlbl{color:#a5a5ab!important}',
      '#guestbook_block_setting .txt-box textarea{display:block!important;width:100%!important;min-height:120px!important;box-sizing:border-box!important;padding:12px!important;border:1px solid #d6d6dc!important;border-radius:14px!important;background:#f7f8fb!important;color:#222!important;font-size:15px!important;line-height:1.4!important;resize:none!important;outline:0!important}',
      '#guestbook_block_setting .txt-box textarea:focus{border-color:#3b4890!important;box-shadow:0 0 0 3px rgba(59,72,144,.16)!important}',
      'html.darkmode #guestbook_block_setting .txt-box textarea{background:#1c1c1e!important;border-color:#48484c!important;color:#eee!important}',
      '#guestbook_block_setting .ipt{border:1px solid #d6d6dc!important;border-radius:12px!important;padding:8px 12px!important;font-size:15px!important;box-sizing:border-box!important;background:#fff!important;color:#222!important}',
      'html.darkmode #guestbook_block_setting .ipt{background:#1c1c1e!important;border-color:#48484c!important;color:#eee!important}',
      '#guestbook_block_setting .dashlst li{color:#8a8a90!important;font-size:12px!important}',
      '#guestbook_block_setting .btn-line-blue{height:34px!important;min-width:56px!important;padding:0 14px!important;border:0!important;border-radius:17px!important;background:#3b4890!important;color:#fff!important;font-size:13px!important;font-weight:700!important;width:auto!important}',
      '#guestbook_block_setting .btm-btns-ctr{border:0!important;padding:10px 0 4px!important;text-align:center!important}',
      '#guestbook_block_setting .btn-line-inblue{height:40px!important;min-width:120px!important;padding:0 28px!important;border:0!important;border-radius:20px!important;background:#3b4890!important;color:#fff!important;font-size:15px!important;font-weight:700!important}',
      'html.darkmode #guestbook_block_setting .btn-line-inblue,html.darkmode #guestbook_block_setting .btn-line-blue{background:#5a6bc4!important}'
    );
    // 갤로그 방명록 입력 띠: '▼ 글 목록' 라벨은 앱이 CSS(::after)로 그린 것이라 DOM 버튼이 없음 → 라벨과 띠(44px 자리·배경·테두리)를 없애고 입력칸만 남김
    rules.push(
      'html.dcapp-nc.dcapp-pin .gallog-wrapping .comment-write-btm.nomg::after{content:none!important;display:none!important}',
      // 입력칸이 화면 아래로 고정되면 그 자리를 감싸던 흰 카드(section.grid)가 비어 남음 → 카드 자체를 접음 (입력 폼은 고정되어 그대로 씀. display:none은 폼까지 숨기므로 쓰지 않음)
      'html.dcapp-pin .gallog-wrapping .brick-wid > section.grid:has(> .comment-write-btm.nomg){padding:0!important;margin:0!important;height:0!important;min-height:0!important;border:0!important;border-radius:0!important;background:none!important;box-shadow:none!important;overflow:visible!important}',
      'html.dcapp-nc.dcapp-pin .gallog-wrapping .comment-write-btm.nomg{height:auto!important;min-height:0!important;padding:0!important;border:0!important;background:none!important}',
      'html.darkmode.dcapp-nc.dcapp-pin .gallog-wrapping .comment-write-btm.nomg{background:none!important;border:0!important}',
      'html.dcapp-pin body:has(.gallog-wrapping){padding-bottom:0!important}'
    );
    (cfg.selectors || []).forEach(function (s) {
      if (s && validSel(s)) rules.push(s + '{display:none!important}');
    });
    // 본문 사진 위에 뜨는 디시 기본 이미지 댓글 버튼(button.btn-imgcomment, #img_comment_open_btn<n>) 숨김 (설정 → 세부 설정)
    if (cfg.hideImgComment) rules.push('.btn-imgcomment,.img-comment{display:none!important}');   // 사진 댓글 버튼 + 미리보기·댓글 패널
    else rules.push('.btn-imgcomment{display:inline-block!important}');   // 댓글창을 열어도 사진 위 버튼은 남김 (누르면 열림/닫힘)
    var dcAccent = (cfg.tint && tintColor('rgb(59,72,144)', cfg.tint)) || '#3b4890';
    var dcAccentDark = (cfg.tint && tintColor('rgb(157,176,255)', cfg.tint)) || '#9db0ff';
    var dcDeferBorder = (cfg.tint && tintColor('rgb(198,204,226)', cfg.tint)) || '#d6d8e2';
    var dcDeferBg = (cfg.tint && tintColor('rgb(235,238,248)', cfg.tint)) || '#f2f3f8';
    if (cfg.tint) {
      rules.push(
        '#dcapp-pager a.on,.btn-comment-write,.btn-vote-go,.gallog-wrapping #guest_write .btn-comment-write{background:' + dcAccent + '!important}',
        'html.darkmode #dcapp-pager a.on,html.darkmode .btn-comment-write,html.darkmode .btn-vote-go,html.darkmode .gallog-wrapping #guest_write .btn-comment-write{background:' + dcAccentDark + '!important}',
        '.gallog-wrapping .menu-box li.on a,.vote-view-result .vote-join .ct,.vote-view-result .vote-go-txt{color:' + dcAccent + '!important}',
        'html.darkmode .gallog-wrapping .menu-box li.on a,html.darkmode .vote-view-result .vote-join .ct,html.darkmode .vote-view-result .vote-go-txt{color:' + dcAccentDark + '!important}'
      );
    }
    if (cfg.deferImages) rules.push('.thum-txtin .dcapp-defer-img{display:none!important}', '.imgwrap:has(.dcapp-defer-img) + .btn-imgcomment,.imgwrap:has(.dcapp-defer-img) .btn-imgcomment,.dcapp-defer-img + .btn-imgcomment{display:none!important}', '.dcapp-defer-btn,.dcapp-defer-all{display:flex;align-items:center;justify-content:center;width:100%;box-sizing:border-box;height:44px;margin:8px 0;padding:0 12px;border:1px solid ' + dcDeferBorder + ';border-radius:10px;background:' + dcDeferBg + ';color:' + dcAccent + ';font-size:14px;font-weight:600;font-family:inherit;-webkit-appearance:none}', '.dcapp-defer-btn:disabled,.dcapp-defer-all:disabled{opacity:.6}', 'html.darkmode .dcapp-defer-btn,html.darkmode .dcapp-defer-all{background:#2c2c2e;border-color:#3d3d40;color:' + dcAccentDark + '}');
    // 사용자가 고른 글꼴 (설정 → 글꼴). FontFace ArrayBuffer로 로드해 커스텀 스킴 차단 우회
    var wf = cfg.webFont;
    if (wf && /^[a-z0-9-]+$/.test(String(wf.id || ''))) {
      // 글 목록·글·댓글·입력칸·버튼의 글자 (아이콘 글꼴은 자기 font-family를 따로 쓰므로 그대로 남음)
      rules.push('body,input,textarea,select,button,.gall-detail-lst .subjectin,.gallview-tit-box .tit,.thum-txtin,.cmt-txt{font-family:"DCAppFont","Apple SD Gothic Neo",-apple-system,sans-serif!important}');
    }
    var fs = cfg.fontSizes || {};
    if (fs.title) rules.push('.gallview-tit-box .tit{font-size:' + fs.title + 'px!important}');
    if (fs.body) rules.push('.thum-txtin{font-size:' + fs.body + 'px!important}');
    if (fs.list) rules.push('.gall-detail-lst .subjectin{font-size:' + fs.list + 'px!important}');
    return rules.join('\n');
  }
  var loadedFontKey = '';
  function b64ToBytes(b64) {
    var bin = atob(b64);
    var len = bin.length;
    var bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }
  function removeDCAppFonts() {
    if (!document.fonts) return;
    document.fonts.forEach(function (f) {
      if (f.family === 'DCAppFont' || f.family === '"DCAppFont"') {
        document.fonts.delete(f);
      }
    });
  }
  function loadFontWeight(id, weight, cssWeight, expectKey) {
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dcappFont;
    if (!handler || typeof FontFace === 'undefined') return Promise.resolve();
    return handler.postMessage({ id: id, weight: weight }).then(function (b64) {
      if (!b64 || loadedFontKey !== expectKey) return;
      var face = new FontFace('DCAppFont', b64ToBytes(b64), { weight: cssWeight, style: 'normal', display: 'swap' });
      return face.load().then(function (loaded) {
        if (loadedFontKey === expectKey) document.fonts.add(loaded);
      });
    }).catch(function () {});
  }
  function syncWebFont(wf) {
    if (!wf || !/^[a-z0-9-]+$/.test(String(wf.id || ''))) {
      if (loadedFontKey) {
        loadedFontKey = '';
        removeDCAppFonts();
      }
      return;
    }
    var key = wf.id + ':' + (wf.bold ? '1' : '0');
    if (loadedFontKey === key) return;
    loadedFontKey = key;
    removeDCAppFonts();
    loadFontWeight(wf.id, 'regular', '400', key);
    if (wf.bold) loadFontWeight(wf.id, 'bold', '700', key);
  }
  function ensureStyle() {
    syncWebFont(cfg.webFont);
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
    document.querySelectorAll('ul.gall-detail-lst > li:not(.app-info-ban):not(.dcapp-pg-sep)').forEach(function (li) {
      var a = li.querySelector('a.lt, a[href]');
      var k = a && postKeyOf(a.getAttribute('href'));
      li.classList.toggle('dcapp-read', !!(k && readSet.has(k)));
    });
  }
  /// 글 목록 정보 줄 칸 나누기 (자리는 CSS order로만 옮김 — 칸 순서는 그대로라 차단·메모 판정에 영향 없음)
  /// 글 화면 작성자 닉네임: 디시가 긴 닉네임을 '가나다..'로 줄여 보냄 → 페이지의 숨은 칸(real_name)에 있는 원래 닉네임으로 되돌려 표시
  function expandArticleNick() {
    var rn = document.getElementById('real_name');
    var full = rn ? (rn.value || '').trim() : '';
    if (!full) return;
    var nk = document.querySelector('.gallview-tit-box .ginfo2 .ginfo-area .nick, .ginfo2 .ginfo-area .nick');
    if (nk) {
      var tw = document.createTreeWalker(nk, NodeFilter.SHOW_TEXT, null), n;
      while ((n = tw.nextNode())) {
        var m = n.nodeValue.match(/^(\s*)(.*?)\.\.(\s*)$/);
        if (!m) continue;
        var pre = m[2].trim();
        if (pre && full.length > pre.length && full.indexOf(pre) === 0) n.nodeValue = m[1] + full + m[3];
      }
    }
    var bn = document.getElementById('blockNick');          // 디시 '차단 닉네임'에 쓰이는 값도 원래 이름으로
    var cur = bn ? (bn.getAttribute('data-set') || '') : '';
    if (bn && /\.\.$/.test(cur) && full.indexOf(cur.replace(/\.+$/, '')) === 0) bn.setAttribute('data-set', full);
  }
  /// 글 아래 수정·삭제·목록보기·글쓰기 버튼이 든 '전체 폭 줄'을 찾아 표시 → 세로 줄(시계 자리) 밖으로 비움
  /// (줄의 클래스가 글마다 달라서 이름이 아니라 버튼 글자로 찾음)
  function markViewButtons() {
    var area = document.querySelector('.gall-thum-btm');
    if (!area) return;
    Array.prototype.forEach.call(area.querySelectorAll('button, a'), function (b) {
      if (!/^(수정|삭제|목록보기|글쓰기)$/.test(txt(b))) return;
      var br = b.getBoundingClientRect();
      if (!br.width) return;
      var row = b.parentElement;
      while (row && row !== area && row.getBoundingClientRect().width < innerWidth - 2) row = row.parentElement;
      if (!row || row === area || row.classList.contains('dcapp-btnrow')) return;
      if (row.getBoundingClientRect().height <= 140 && !row.querySelector('.thum-txt, .thum-txtin')) row.classList.add('dcapp-btnrow');
    });
  }
  /// 글 목록의 닉네임: 디시가 긴 닉네임을 '가나다..'로 줄여 보냄 → 같은 행의 숨은 정보(blockInfo)에 있는 원래 닉네임으로 되돌려 표시
  function expandListNicks() {
    document.querySelectorAll('ul.gall-detail-lst > li:not(.app-info-ban):not(.dcapp-pg-sep)').forEach(function (li) {
      var bi = li.querySelector('.blockInfo');
      var full = bi ? (bi.getAttribute('data-name') || '').trim() : '';
      if (!full) return;
      var g = li.querySelector('ul.ginfo');
      if (!g) return;
      var nk = g.querySelector('li.list-nick');
      if (!nk) {
        var lis = Array.prototype.filter.call(g.children, function (c) { return c.tagName === 'LI'; });
        nk = lis.length >= 5 ? lis[1] : lis[0];
      }
      if (!nk) return;
      var tw = document.createTreeWalker(nk, NodeFilter.SHOW_TEXT, null), n;
      while ((n = tw.nextNode())) {
        var m = n.nodeValue.match(/^(\s*)(.*?)\.\.(\([^)]*\))?\s*$/);
        if (!m) continue;
        var pre = m[2].trim();
        if (pre && full.length > pre.length && full.indexOf(pre) === 0) n.nodeValue = m[1] + full + (m[3] || '');
      }
    });
  }
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
  /// 행의 말머리 이름 (메타 줄 맨 앞 칸, 없으면 빈 문자열)
  function headNameOf(li) {
    var h = li.querySelector('ul.ginfo > li.dcapp-head');
    return h ? txt(h) : '';
  }
  function applyListFilter() {
    document.querySelectorAll('ul.gall-detail-lst > li:not(.app-info-ban):not(.dcapp-pg-sep)').forEach(function (li) {
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
        if (f.heads && f.heads.length && f.heads.indexOf(headNameOf(li)) < 0) hide = true;   // 고른 말머리만
      }
      li.classList.toggle('dcapp-filtered', hide);
    });
    var fbtn = document.getElementById('dcapp-filterbtn');
    if (fbtn) fbtn.classList.toggle('dcapp-on', !!listFilter);
  }

  /// 글목록을 '더보기'나 당기기로 이어 붙이면 디시는 페이지마다 <ul id="listthumN">을 새로 만든다(N = 그 페이지 번호).
  /// 각 목록 맨 앞에 "N페이지" 구분선(li.dcapp-pg-sep)을 한 번만 넣는다. 첫 목록(id 없음)은 처음 열린 주소의 page 값을 쓴다.
  /// 주소는 더보기 뒤 pushState로 바뀌므로 첫 페이지 번호는 처음 한 번만 읽는다.
  var pgBase = null;
  function pageSeparators() {
    if (!document.getElementById('pagination_div')) return;
    if (pgBase === null) pgBase = parseInt(new URL(location.href).searchParams.get('page'), 10) || 1;
    document.querySelectorAll('ul.gall-detail-lst:not(#view_next):not(.sch-comment):not(.thum)').forEach(function (ul) {
      if (ul.querySelector(':scope > li.dcapp-pg-sep')) return;
      if (!ul.querySelector(':scope > li:not(.dcapp-pg-sep):not(.app-info-ban)')) return;   // 행이 아직 안 채워졌으면 다음 변화 때
      var m = /^listthum(\d+)$/.exec(ul.id || '');
      var pg = m ? parseInt(m[1], 10) : pgBase;
      var sep = document.createElement('li');
      sep.className = 'dcapp-pg-sep';
      sep.setAttribute('data-page', String(pg));
      var label = document.createElement('span');
      label.textContent = pg + '페이지';
      sep.appendChild(label);
      ul.insertBefore(sep, ul.firstChild);
    });
  }
  // ---------- 글 목록 맨 아래에서 위로 더 당기면 → 디시 '더보기'(v) 눌러 다음 글 이어 붙이기 ----------
  /// 말머리 목록 아래에 지나온 페이지 표시줄(#dcapp-pgwrap > #dcapp-pgbar)을 둠. 목록을 내리다 페이지 구분선을 지나면 그 페이지 번호를 위에 띄우고,
  /// 구분선이 다시 보이면 숨김. 표시줄은 absolute라 보이고 숨겨도 목록이 밀리지 않음
  var pgTick = false;
  function pageStickyBar() {
    var lst = document.querySelector('ul.gall-detail-lst:not(#view_next):not(.sch-comment):not(.thum)');
    var wrap = document.getElementById('dcapp-pgwrap');
    if (!lst || !document.getElementById('pagination_div')) {
      if (wrap) wrap.parentNode.removeChild(wrap);
      return;
    }
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.id = 'dcapp-pgwrap';
      var pb = document.createElement('div');
      pb.id = 'dcapp-pgbar';
      wrap.appendChild(pb);
    }
    if (wrap.nextElementSibling !== lst) lst.parentNode.insertBefore(wrap, lst);
    var head = document.getElementById('dcapp-headbar');
    var t = (head ? head.offsetHeight : 0) + 'px';
    if (wrap.style.top !== t) wrap.style.top = t;
    pageStickyUpdate();
  }
  function pageStickyUpdate() {
    var pb = document.getElementById('dcapp-pgbar');
    if (!pb) return;
    var head = document.getElementById('dcapp-headbar');
    var line = head ? head.offsetHeight : 0;
    var seps = document.querySelectorAll('ul.gall-detail-lst:not(#view_next):not(.sch-comment):not(.thum) > li.dcapp-pg-sep');
    var pick = null;
    for (var i = 0; i < seps.length; i++) {
      if (seps[i].getBoundingClientRect().bottom <= line) pick = seps[i]; else break;
    }
    if (!pick) { pb.classList.remove('dcapp-on'); return; }
    var label = (pick.textContent || '').trim();
    if (pb.textContent !== label) pb.textContent = label;
    pb.classList.add('dcapp-on');
  }
  document.addEventListener('scroll', function () {
    if (pgTick) return;
    pgTick = true;
    requestAnimationFrame(function () { pgTick = false; try { pageStickyUpdate(); } catch (e) {} });
  }, { capture: true, passive: true });

  /// 글목록 자동 이어 불러오기: 맨 아래에서 350px 남은 지점에 닿으면 당기기·손 떼기 없이 다음 페이지를 불러옴.
  /// DC의 list_more는 요청이 실패하거나 멈춰도 스피너를 지우지 않으므로(오류 처리 없음) 앱이 요청을 감시함:
  /// 12초 넘게 끝나지 않으면 요청을 끊고 '더보기'로 되돌림, 스피너만 남은 채 요청이 없으면 4초 뒤 되돌림.
  /// 되돌린 뒤 연속 3번 실패하면 자동 부르기를 멈춤 (더보기 버튼은 그대로 사용 가능). list_more가 알림을 띄우면 그때도 멈춤.
  var autoMoreState = { calling: false, stopped: false };
  (function autoMore() {
    var NEAR = 350, COOL = 4000, STALL = 12000, SPIN_MAX = 4000, MAX_FAILS = 3;
    var lastFire = 0, lastFireCount = -1, tick = false;
    var listReq = null, listReqAt = 0, spinSince = 0, fails = 0, okCount = -1;
    var ORIG = '<span class="sp-arrow arrow-down-lg">더보기</span>';
    if (window.jQuery && window.jQuery.ajaxPrefilter) {
      window.jQuery.ajaxPrefilter(function (options, original, jqXHR) {
        if (options && options.url === '/ajax/response-list') {
          listReq = jqXHR;
          listReqAt = Date.now();
          jqXHR.always(function () { if (listReq === jqXHR) listReq = null; });
        }
      });
    }
    function moreBtn() {
      var b = document.getElementById('listMore');
      return b && b.offsetParent !== null && document.querySelector('ul.gall-detail-lst') ? b : null;
    }
    function spinning(b) { return !!(b && b.querySelector('.dc-spinner')); }
    function listCount() { return document.querySelectorAll('ul.gall-detail-lst').length; }
    function fire(b) {
      lastFire = Date.now();
      lastFireCount = listCount();
      autoMoreState.calling = true;
      try { if (typeof window.list_more === 'function') window.list_more(); else b.click(); }
      finally { autoMoreState.calling = false; }
    }
    function check() {
      tick = false;
      if (autoMoreState.stopped) return;
      var b = moreBtn();
      if (!b || spinning(b)) return;
      var se = document.scrollingElement || document.documentElement;
      if (window.scrollY + window.innerHeight < se.scrollHeight - NEAR) return;
      var now = Date.now();
      if (listCount() <= lastFireCount && now - lastFire < COOL) return;
      fire(b);
    }
    function watch() {
      var b = moreBtn();
      if (!b) { spinSince = 0; return; }
      if (!spinning(b)) {
        spinSince = 0;
        var n = listCount();
        if (okCount >= 0 && n > okCount) fails = 0;   // 목록이 늘었으면 성공
        okCount = n;
        return;
      }
      var now = Date.now();
      if (!spinSince) spinSince = now;
      var stalled = false;
      if (listReq && now - listReqAt > STALL) {
        try { listReq.abort(); } catch (e) {}
        listReq = null;
        stalled = true;
      }
      if (stalled || (!listReq && now - spinSince > SPIN_MAX)) {
        b.innerHTML = ORIG;   // 스피너를 걷어 '더보기'로 되돌림 (직접 누르면 DC가 그대로 다시 부름)
        spinSince = 0;
        fails += 1;
        if (fails >= MAX_FAILS) autoMoreState.stopped = true;
        lastFire = 0;
        lastFireCount = -1;
      }
    }
    document.addEventListener('scroll', function () {
      if (tick) return;
      tick = true;
      requestAnimationFrame(check);
    }, { capture: true, passive: true });
    setInterval(function () { watch(); check(); }, 1000);
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
    // 검색 구간(s_pos): 디시는 검색 결과를 1만 개 단위 구간으로 나누고 주소에 s_pos를 붙여 다님. 구간을 옮기는 링크(다음/이전 검색)는
    // s_pos 값이 지금 주소의 값과 다름. 주소에 s_pos가 이미 있는 구간 페이지에서도 이 기준으로 봐야 함
    var inSearch = /[?&](serval|s_pos)=/.test(location.search);
    function sPosOf(href) {
      try { var sp = new URL(href, location.href).searchParams; return sp.has('s_pos') ? sp.get('s_pos') : null; } catch (e) { return null; }
    }
    var curSPos = sPosOf(location.href) || '';
    function isSearchJump(a) {
      var p = a ? sPosOf(a.getAttribute('href') || '') : null;   // s_pos가 없는 링크는 구간 이동이 아님
      return p !== null && p !== curSPos;
    }
    // 뒤 페이지가 더 있나. 일반 목록: 디시 '다음'이 있으면 있음 (기존 그대로). 검색: 같은 구간에서 page가 지금보다 큰 '다음'일 때만 있음
    var hasMore = false;
    if (next && !isSearchJump(next)) {
      if (!inSearch) hasMore = true;
      else {
        var np = 0;
        try { np = parseInt(new URL(next.getAttribute('href') || '', location.href).searchParams.get('page'), 10); } catch (e) {}
        hasMore = np > cur;
      }
    }
    // 뒤가 더 있으면 끝을 모름(무한). 없으면 보이는 번호 중 가장 큰 번호가 끝 (검색 구간의 마지막 페이지)
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
      if (!(to > 0) || to === cur) return;
      if (!hasMore && to > last) { window.alert('이동할 페이지가 없습니다. 마지막 페이지는 ' + last + '페이지예요.'); return; }
      location.href = pageURL(to);
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
      if (isSearchJump(prev)) sub.appendChild(btn('이전 검색', prev.href));
      if (dateBtn) {
        var d = btn('날짜로 이동', 'javascript:void(0)');
        d.addEventListener('click', function (e) { e.preventDefault(); dateBtn.click(); });
        sub.appendChild(d);
      }
      if (isSearchJump(next)) sub.appendChild(btn('다음 검색', next.href));
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

  // 글 등록 전 금지어 검사(/ajax/w_filter)가 막으면 → 금지어 단어를 앱에 넘김 (앱 글쓰기에서 그 위치를 선택하려고)
  // jQuery의 ajaxComplete는 디시가 띄우는 안내창(alert)을 확인한 뒤에 불리므로, 앱은 안내를 닫은 다음에 위치를 잡음
  (function hookBannedWord() {
    if (!/\/write/.test(location.pathname)) return;
    var tries = 0;
    var t = setInterval(function () {
      if (++tries > 40) { clearInterval(t); return; }
      if (!window.jQuery) return;
      clearInterval(t);
      window.jQuery(document).ajaxComplete(function (e, xhr, opts) {
        if (!opts || !/\/ajax\/w_filter/.test(opts.url || '')) return;
        var j = null;
        try { j = JSON.parse(xhr.responseText); } catch (err) { return; }
        if (!j || j.result !== false || !j.word) return;
        post('banword', { word: String(j.word), cause: String(j.cause || '') });
      });
    }, 250);
  })();

  function articleHead() { return document.querySelector('.gallview-tit-box, [class^="gallview-tit-box"]'); }
  function articleBody() { return document.querySelector('.thum-txtin'); }

  // ---------- 스포일러 글 ----------
  // 디시는 스포일러 글(스포일러 말머리, 또는 제목에 '스포)')의 본문 맨 위에 경고 칸(#spoiler: '스포일러 주의' 사진)을 넣음.
  // 그 칸을 누르면 공식 앱처럼 칸을 치우고, 누르기 전까지는 그 아래 본문을 흐리게 함.
  // 경고 칸은 본문 칸(.thum-txtin) 안에 있어야 디시 다크모드(본문 칸 통째로 색 반전)에서도 제대로 보임 → 그대로 두고, 그 뒤의 본문만 흐림 칸 하나로 감쌈
  // (디시 설정에서 '본문에서 경고'를 끄면 경고 칸이 아예 없음 → 흐리게 하지도 않음. '노스포)'처럼 디시가 스포일러로 안 보는 글도 마찬가지)
  function spoilerBox() {
    var s = document.getElementById('spoiler'), body = articleBody();
    return s && body && body.contains(s) ? s : null;
  }
  function spoilerKey() { return 'dcapp-spo:' + location.pathname; }
  function pageNavType() {
    try { var n = performance.getEntriesByType('navigation')[0]; if (n && n.type) return n.type; } catch (e) {}
    try { var t = performance.navigation.type; return t === 2 ? 'back_forward' : (t === 1 ? 'reload' : 'navigate'); } catch (e2) {}
    return 'navigate';
  }
  function moveNode(parent, node, before) {
    // moveBefore가 있으면 옮겨도 동영상·iframe이 다시 로드되지 않음 (없는 버전은 insertBefore)
    try { if (parent.moveBefore) { parent.moveBefore(node, before); return; } } catch (e) {}
    parent.insertBefore(node, before);
  }
  function spoilerUnblur() {
    var body = articleBody(), w = body ? body.querySelector('.dcapp-spo-blur') : null;
    if (!w || !w.parentNode) return;
    while (w.firstChild) moveNode(w.parentNode, w.firstChild, w);   // 감쌌던 본문을 원래 자리로
    w.parentNode.removeChild(w);
  }
  function revealSpoiler() {
    var s = spoilerBox();
    if (s) s.style.display = 'none';
    try { sessionStorage.setItem(spoilerKey(), '1'); } catch (e) {}
    spoilerUnblur();
  }
  var spoilerChecked = false;
  function spoilerGuard() {
    var s = spoilerBox();
    if (!s || getComputedStyle(s).display === 'none') { spoilerUnblur(); return; }   // 경고 칸이 없거나 닫힘
    // 푼 글로 '뒤로'·새로고침으로 돌아온 경우는 푼 채로 (글을 새로 열면 다시 경고부터)
    var seen = false;
    try {
      if (!spoilerChecked) {
        spoilerChecked = true;
        if (pageNavType() === 'navigate') sessionStorage.removeItem(spoilerKey());
      }
      seen = sessionStorage.getItem(spoilerKey()) === '1';
    } catch (e) {}
    if (seen) { revealSpoiler(); return; }
    if (!s.__dcappSpo) {
      s.__dcappSpo = true;
      s.addEventListener('click', function () {});   // iOS는 '누를 수 있는 요소'가 아니면 click을 안 보냄 → 칸 어디를 눌러도 click이 오게 (처리는 아래 문서 click에서)
    }
    var body = articleBody(), top = s;
    while (top.parentNode && top.parentNode !== body) top = top.parentNode;
    var w = body.querySelector('.dcapp-spo-blur');
    if (!w) {
      if (!top.nextSibling) return;
      w = document.createElement('div');
      w.className = 'dcapp-spo-blur';
      body.insertBefore(w, top.nextSibling);
    }
    while (w.nextSibling) moveNode(w, w.nextSibling, null);   // 경고 칸 뒤의 본문(나중에 붙은 것 포함)을 흐림 칸 안으로
  }

  function findUnits() {
    var list = [];
    var seen = new Set();
    function add(el, kind) {
      if (seen.has(el)) return;
      seen.add(el);
      list.push({ el: el, kind: kind });
      if (el.getAttribute('data-dcapp-unit') !== kind) el.setAttribute('data-dcapp-unit', kind);
    }
    document.querySelectorAll('ul.gall-detail-lst > li:not(.app-info-ban):not(.dcapp-pg-sep)').forEach(function (li) {
      if (/(^|\s)ad/.test(clsOf(li))) return;
      if (!li.querySelector('a')) return;
      add(li, 'post');
    });
    document.querySelectorAll('ul[class*="comment"] > li:not(.app-info-ban), ol[class*="comment"] > li:not(.app-info-ban)').forEach(function (li) {
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
      // 목록은 긴 닉네임을 '가나다..'로 줄여 보냄 → 같은 행의 숨은 정보(blockInfo)에 있는 원래 닉네임으로 (작성글 검색·메모가 줄인 이름으로 안 되게)
      if (/\.\.$/.test(r.nick)) {
        var bi0 = el.querySelector('.blockInfo'), dn0 = bi0 ? (bi0.getAttribute('data-name') || '').trim() : '';
        if (!dn0 && u.kind === 'article') { var rn0 = document.getElementById('real_name'); dn0 = rn0 ? (rn0.value || '').trim() : ''; }   // 글 화면: 작성자 닉네임도 줄어 있음 → 숨은 칸에 원래 이름
        if (dn0 && dn0.indexOf(r.nick.replace(/\.+$/, '')) === 0) r.nick = dn0.slice(0, 40);
      }
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
    // 눌러서 불러온 사진은 src가 data 주소라서, 원래 디시 주소(data-dcapp-deferred-src)를 씀
    var s = x.getAttribute('data-dcapp-deferred-src') || x.getAttribute('data-original') || x.getAttribute('data-src') || x.currentSrc || x.src || '';
    if (!s || /^data:/.test(s)) return '';
    try { return new URL(s, location.href).href; } catch (e) { return ''; }
  }
  /// 글 속 사진·움짤의 원본 주소 (움짤은 자리표시 이미지 대신 data-gif / video의 ori-data)
  function galleryMediaURL(x) {
    var s = '';
    if (x.tagName === 'VIDEO') s = x.getAttribute('data-dcapp-deferred-src') || x.getAttribute('ori-data') || x.getAttribute('data-gif') || x.currentSrc || x.src || '';
    else if (x.classList && x.classList.contains('gif-mp4')) s = x.getAttribute('data-gif') || '';
    if (s) { try { return new URL(s, location.href).href; } catch (e) { return ''; } }
    return imgURL(x);
  }
  function dcconKey(m) {
    if (!m || !m.tagName || !/^(IMG|VIDEO)$/.test(m.tagName)) return null;
    var s = mediaSrc(m);
    if (!/dccon/i.test(s) && !/dccon/i.test(clsOf(m))) return null;
    var q = s.match(/[?&]no=([^&#]+)/);
    return q ? q[1] : (s.split('#')[0] || null);
  }
  // 차단 목록에 있는 디시콘인지: 앱 키(dcconKey)에 더해, 움직이는 디시콘(video)은 ori-data의 그림 번호로도 확인
  // (video의 앱 키는 영상(mp4) 번호라서, 그림 번호로 된 패키지 목록에는 없음)
  function dcconBlockedIn(m, dset) {
    var k = dcconKey(m);
    if (!k) return false;
    if (dset.has(k)) return true;
    if (m.tagName !== 'VIDEO') return false;
    var o = dcconNoOf(m.getAttribute('ori-data'));
    return !!o && dset.has(o);
  }

  // ---------- 본문 사진 차단 (그 사진만 가림) ----------
  // 키: 사진 주소의 no= 값(소문자), 없으면 호스트+경로+쿼리(소문자). 앱은 키를 직접 만들지 않고 페이지가 준 키만 씀
  function imgBlockKey(src) {
    if (!src) return '';
    var no = src.match(/[?&]no=([^&#]+)/i);
    if (no) return 'n:' + no[1].toLowerCase();
    try {
      var u = new URL(src, location.href);
      return ('p:' + u.host + u.pathname + u.search).toLowerCase();
    } catch (e) { return ''; }
  }
  /// 본문 사진·움짤로서 차단 대상이 될 수 있는지 (디시콘, 스포일러 경고 칸 안은 제외). 로딩 중인지·크기는 따지지 않음
  function imgBlockable(m) {
    if (!m || !m.tagName) return false;
    var body = articleBody();
    if (!body || !body.contains(m) || (m.closest && m.closest('#spoiler'))) return false;
    if (m.tagName === 'VIDEO') return m.classList.contains('dc_mv') && !!galleryMediaURL(m);
    return m.tagName === 'IMG' && !dcconKey(m);
  }
  /// 차단할 수 있는 본문 사진·움짤 (디시콘, 스포일러 경고 칸 안, 40px 이하 작은 사진은 제외)
  function imgEligible(m) {
    if (!imgBlockable(m)) return false;
    if (m.tagName === 'VIDEO') return true;
    if (!m.complete) return false;      // 아직 안 받은 사진은 크기를 모름 → 받으면(load) 다시 판단
    return (m.naturalWidth || m.width || 0) > 40;
  }
  /// 터치·클릭한 곳의 사진·움짤 (가린 칸 위를 눌렀으면 그 안의 사진)
  function mediaAt(target) {
    if (!target || !target.closest) return null;
    var m = target.closest('img, video');
    if (m) return m;
    var blk = target.closest('.dcapp-imgblk');
    return blk ? blk.querySelector('img, video') : null;
  }
  /// 차단돼 가려져 있고 아직 안 보여 준 사진인지
  function imgHidden(m) {
    var w = m && m.closest ? m.closest('.dcapp-imgblk') : null;
    return !!w && w.getAttribute('data-dcapp-blocked') === '1' && w.getAttribute('data-dcapp-img-revealed') !== '1';
  }
  /// 글 속 사진·움짤 전체 (PC 원본 첨부와 순서를 맞추는 기준): 디시콘·스포일러 경고 칸 안·40px 이하 작은 사진 제외, 가려진 사진 포함
  /// keep: 사진 보기에서 눌러 연 사진 (작은 사진이라도 보여 주려고 넣음)
  function bodyPhotos(keep) {
    var body = articleBody();
    if (!body) return [];
    return Array.prototype.filter.call(body.querySelectorAll('img, video.dc_mv'), function (x) {
      if (keep && x === keep) return true;
      if (dcconKey(x) || (x.closest && x.closest('#spoiler')) || !galleryMediaURL(x)) return false;
      if (x.tagName === 'VIDEO') return true;
      var w = x.naturalWidth || parseInt(x.getAttribute('width'), 10) || x.width || 0;
      return w === 0 || w > 40;     // 아직 안 받아서 크기를 모르는 사진은 넣음 (PC 원본 목록에는 있을 가능성이 큼)
    });
  }
  function photoFileno(x) { return parseInt(x.getAttribute('data-fileno'), 10) || 0; }
  function wrapImg(m) {
    var w = document.createElement('span');
    w.className = 'dcapp-imgblk';
    var badge = document.createElement('span');
    badge.className = 'dcapp-imgblk-badge';
    badge.textContent = '차단한 이미지 · 탭해서 보기';
    m.parentNode.insertBefore(w, m);
    w.appendChild(m);
    w.appendChild(badge);
    return w;
  }
  function unwrapImg(w) {
    var parent = w.parentNode;
    if (!parent) return;
    Array.prototype.slice.call(w.children).forEach(function (c) {
      if (!c.classList.contains('dcapp-imgblk-badge')) parent.insertBefore(c, w);
    });
    parent.removeChild(w);
  }
  /// 차단한 사진만 감싸서 가림. 차단이 풀리면 원래대로. 키로 안 걸리는 사진은 (차단한 사진의 생김새 해시가 있을 때) 앱에 한 번 확인 요청
  function applyImageBlocks(enabled) {
    var body = articleBody();
    if (!body) return;
    var listed = {};
    (cfg.images || []).forEach(function (k) { listed[k] = true; });
    var hasHashes = !!(cfg.imgHashes && cfg.imgHashes.length);
    var style = cfg.imgStyle === 'gray' ? 'gray' : 'blur';
    Array.prototype.slice.call(body.querySelectorAll('img, video.dc_mv')).forEach(function (m) {
      var wrap = m.parentNode && m.parentNode.classList && m.parentNode.classList.contains('dcapp-imgblk') ? m.parentNode : null;
      if (!enabled || !imgBlockable(m)) { if (wrap) unwrapImg(wrap); return; }
      var url = galleryMediaURL(m);
      var key = imgBlockKey(url);
      if (!key) return;
      if (listed[key] || runtimeImg[key]) {
        // 다 받은 작은 사진(40px 이하)은 가리지 않음 — 아직 안 받은 사진은 크기를 몰라도 바로 가림 (원본이 잠깐 보이는 것 방지)
        if (m.tagName === 'IMG' && m.complete && (m.naturalWidth || m.width || 0) <= 40) { if (wrap) unwrapImg(wrap); return; }
        if (!wrap) wrap = wrapImg(m);
        wrap.setAttribute('data-dcapp-blocked', '1');
        wrap.setAttribute('data-dcapp-style', style);
        return;
      }
      if (wrap) unwrapImg(wrap);
      if (!imgEligible(m)) return;      // 생김새 확인은 크기를 알고 나서(받은 뒤) 함
      if (hasHashes && !imgChecked[key]) { imgChecked[key] = true; post('checkimg', { key: key, url: url }); }
    });
  }

  // ---------- 차단 판정 ----------
  /// 지금 보고 있는 갤러리 아이디 (/board/{id}, /mini/{id}) — 갤러리별 차단·메모용
  function currentGalleryId() {
    var p = location.pathname.split('/');
    return (p[1] === 'board' || p[1] === 'mini' || p[1] === 'person') ? (p[2] || '') : '';
  }

  // ---------- 차단 단어 판정 (쉼표로 나눈 단어 조각은 모두 있어야 함 · 특수문자·공백 끼워넣기 무시 옵션) ----------
  // Swift BlockMatch와 같은 규칙: 소문자화는 항상. symbols면 글자·결합 문자·숫자·공백만 남기고, spaces면 공백을 뺌
  function normText(s, symbols, spaces) {
    var t = String(s || '').toLowerCase();
    if (spaces) t = t.replace(/\s+/gu, '');
    if (symbols) t = t.replace(/[^\p{L}\p{M}\p{N}\s]/gu, '');
    return t;
  }
  /// 특수문자가 하나라도 있는지 (글자·결합 문자·숫자·공백이 아닌 문자) — Swift BlockMatch.hasSymbol과 같은 기준
  function hasSymbol(s) { return /[^\p{L}\p{M}\p{N}\s]/u.test(String(s || '')); }
  /// 단어 조각들이 모두 들어 있는지 (text는 소문자). 조각마다 따로 판단 — 원문에 있으면 통과,
  /// 조각에 특수문자가 있으면 그 조각만은 특수문자를 빼지 않고(공백 무시만) 비교 (c++가 c로 넓게 걸리지 않게),
  /// 그 밖의 조각은 켜진 옵션대로. 정규화하면 빈 조각은 원문 비교만
  /// norm: 정규화한 본문 캐시 {full: 특수문자·공백 기준, space: 공백만 기준} — 필요할 때 한 번씩만 만듦
  function termsMatch(terms, text, symbols, spaces, norm) {
    if (!terms || !terms.length) return false;
    for (var i = 0; i < terms.length; i++) {
      var t = terms[i];
      if (!t || text.indexOf(t) >= 0) continue;
      var sym = symbols && !hasSymbol(t);
      if (!sym && !spaces) return false;
      var nt = normText(t, sym, spaces);
      if (!nt) return false;
      var key = sym ? 'full' : 'space';
      if (norm[key] === null) norm[key] = normText(text, sym, spaces);
      if (norm[key].indexOf(nt) < 0) return false;
    }
    return true;
  }
  /// 닉네임이 같은지: 기준은 차단 값(blocked)이 정함 — 차단 값에 특수문자가 있으면 특수문자는 빼지 않고(공백 무시만),
  /// 없으면 켜진 옵션대로. 작성자 닉네임(actual)도 같은 기준으로 정규화해서 비교. 정규화 결과가 비면 원문 비교
  function nickEq(actual, blocked, symbols, spaces) {
    if (!actual || !blocked) return false;
    if (actual === blocked) return true;
    var sym = symbols && !hasSymbol(blocked);
    if (!sym && !spaces) return false;
    var nb = normText(blocked, sym, spaces);
    return !!nb && nb === normText(actual, sym, spaces);
  }

  function blockedReason(u, idn, dset, dpset) {
    // 디시 자체 차단창으로 막은 사람: 디시는 block-disable 표시만 붙여 흐리게 보여줌 → 앱 차단처럼 가림
    if (u.el.classList.contains('block-disable')) return '디시 차단';
    var symbols = !!cfg.ignoreSymbols, spaces = !!cfg.ignoreSpaces;
    var users = cfg.users || [], gid = currentGalleryId();
    for (var i = 0; i < users.length; i++) {
      var b = users[i];
      if (b.g && (',' + b.g + ',').indexOf(',' + gid + ',') < 0) continue;                  // 다른 갤러리 전용 차단 (b.g는 쉼표로 이은 여러 갤러리)
      if ((b.k === 'id' && idn.id && idn.id === b.v) ||
          (b.k === 'ip' && idn.ip && idn.ip === b.v) ||
          (b.k === 'nick' && nickEq(idn.nick, b.v, symbols, spaces))) return '차단한 유저';
    }
    // 칸의 글자 (글이면 본문까지) — 고급 차단·키워드 차단이 같이 쓰고, 필요할 때 한 번만 만듦
    var bodyLower = null, norm = { full: null, space: null };
    function bodyText() {
      if (bodyLower === null) {
        var t = txt(u.el);
        if (u.kind === 'article') t += ' ' + txt(articleBody());
        bodyLower = t.toLowerCase();
      }
      return bodyLower;
    }
    // 고급 차단: 작성자가 맞고 + 글·댓글에 그 규칙의 단어가 모두 들어 있을 때만
    var adv = cfg.advRules || [];
    for (var ai = 0; ai < adv.length; ai++) {
      var ar = adv[ai];
      if (!ar || !(ar.w && ar.w.length)) continue;
      if (ar.g && (',' + ar.g + ',').indexOf(',' + gid + ',') < 0) continue;
      if (!((ar.k === 'id' && idn.id && idn.id === ar.v) ||
            (ar.k === 'ip' && idn.ip && idn.ip === ar.v) ||
            (ar.k === 'nick' && nickEq(idn.nick, ar.v, symbols, spaces)))) continue;
      if (termsMatch(ar.w, bodyText(), symbols, spaces, norm)) return '고급 차단';
    }
    // 차단 키워드: 쉼표로 나눈 단어가 모두 들어 있을 때만 (다른 갤러리 전용 키워드는 건너뜀)
    var kws = cfg.keywords || [];
    for (var j = 0; j < kws.length; j++) {
      var kj = kws[j];
      if (!kj || !(kj.t && kj.t.length) || (kj.g && (',' + kj.g + ',').indexOf(',' + gid + ',') < 0)) continue;
      if (termsMatch(kj.t, bodyText(), symbols, spaces, norm)) return '차단 키워드';
    }
    if (u.kind === 'comment' && (dset.size || dpset.size)) {
      var media = u.el.querySelectorAll('img, video');
      for (var k = 0; k < media.length; k++) {
        var mp = media[k].getAttribute('data-dccon-package') || media[k].getAttribute('package_idx') || '';
        if (dcconBlockedIn(media[k], dset) || (mp && dpset.has(String(mp)))) return '차단한 디시콘';
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

  // ---------- 홈 순위: 한 페이지에 10칸(5칸 두 줄)이 보이도록 좌우 넘김을 두 칸 단위로 ----------
  function homeRankTwoUp() {
    if (!isHomePage()) return;
    [window.swiper, window.swiper_hot].forEach(function (sw) {
      if (!sw || !sw.params || !sw.el) return;
      // 화면이 넓으면(듀오 펼침) 사이트가 3칸으로 바꾸는 반응형 설정을 없애 항상 2칸(1~10위)만
      var bp = !!sw.params.breakpoints || !!(sw.originalParams && sw.originalParams.breakpoints);
      if (bp) {
        sw.params.breakpoints = undefined;
        if (sw.originalParams) sw.originalParams.breakpoints = undefined;
        sw.currentBreakpoint = undefined;
      }
      if (sw.params.slidesPerView === 2 && sw.params.slidesPerGroup === 2 && !bp) return;
      sw.params.slidesPerView = 2;
      sw.params.slidesPerGroup = 2;
      try { sw.update(); } catch (e) {}
    });
  }
  // 화면 폭이 늦게 바뀌면(듀오 옆 줄 안전 영역 등) 순위 칸 폭을 다시 잼 — 안 그러면 처음 폭 기준으로 3칸이 보임
  var rankResizeBound = false;
  function homeRankRemeasure() {
    if (rankResizeBound || !isHomePage()) return;
    rankResizeBound = true;
    var redo = function () {
      [window.swiper, window.swiper_hot].forEach(function (sw) {
        if (!sw || !sw.el) return;
        try { sw.updateSize(); sw.updateSlides(); sw.update(); } catch (e) {}
      });
    };
    window.addEventListener('resize', redo);
    [300, 1000, 2500].forEach(function (ms) { setTimeout(redo, ms); });
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
    document.querySelectorAll('.dcapp-hc-raw').forEach(function (el) { el.classList.remove('dcapp-hc-raw'); });
    document.querySelectorAll('.dcapp-hc-host').forEach(function (el) { el.classList.remove('dcapp-hc-host'); });
    document.querySelectorAll('section.rank-group > .dcapp-hc').forEach(function (el) { el.parentNode.removeChild(el); });
    homeCardsSig = '';
    document.documentElement.classList.remove('dcapp-home-wait');
  }
  // ---------- 홈 순위 카드: 실북갤·흥한갤 한 블록 + 갤러리·마이너갤·미니갤·인물갤 4칸 (좌우로 밀어 1~50위) ----------
  // 순위는 디시 스크립트가 화면 밖의 원래 칸(rank_title_N·rank_updown_N 등)에 채운 것을 읽어 글자로 다시 그림 (원래 칸은 지우지 않음)
  // 디시는 순위 목록을 슬라이드를 넘길 때만 받아 오므로, 카드가 필요한 목록을 받게 함 (gallery_rank_call / gallery_hot_call)
  // 디시 목록 요청은 같은 콜백 이름을 쓰므로 한 번에 하나씩 차례로 받음 (동시에 부르면 응답이 서로 덮어써서 일부가 안 뜸)
  var HC_CATS = ['갤러리', '마이너갤', '미니갤', '인물갤'];
  var HC_PREFIX = {
    rank: [['rank_link_', 'rank_title_', 'rank_updown_'], ['mrank_link_', 'mrank_title_', 'mrank_updown_'], ['mirank_link_', 'mirank_title_', 'mirank_updown_'], ['prrank_link_', 'prrank_title_', 'prrank_updown_']],
    hot: [['hot_link_', 'hot_title_', 'hot_updown_'], ['mhot_link_', 'mhot_title_', 'mhot_updown_'], ['mihot_link_', 'mihot_title_', 'mihot_updown_'], ['prhot_link_', 'prhot_title_', 'prhot_updown_']]
  };
  var HC_LOAD = { rank: [1, 2, 3, 4], hot: [5, 6, 7, 8] };   // 디시 목록 종류 번호 (갤러리·마이너·미니·인물)
  var HC_TAGS = { rank: ['gall_rank_tag', 'mgall_rank_tag', 'migall_rank_tag', 'prgall_rank_tag'], hot: ['gall_hot_tag', 'mgall_hot_tag', 'migall_hot_tag', 'prgall_hot_tag'] };
  var HC_PAGE = 10, HC_PAGES = 5;   // 10위씩 5쪽 (1~50위)
  var homeCardsSig = '';
  var homeMode = null;
  var homeChainBusy = { rank: false, hot: false };
  var homeChainDone = { rank: false, hot: false };
  function homeHotOn() { return !!document.querySelector('#hot_gall.on'); }
  function homeCurMode() {
    if (homeMode === null) homeMode = homeHotOn() ? 'hot' : 'rank';
    return homeMode;
  }
  // 카드 한 종류(갤러리 등)의 순위 — 제목이 없는 칸(아직 안 받은 칸)은 건너뜀
  function homeCatItems(mode, i) {
    var p = HC_PREFIX[mode][i];
    var items = [];
    for (var n = 1; n <= HC_PAGE * HC_PAGES; n++) {
      var t = document.getElementById(p[1] + n);
      var title = t ? (t.textContent || '').trim() : '';
      if (!title) continue;
      var a = document.getElementById(p[0] + n);
      var ud = document.getElementById(p[2] + n);
      var arrow = ud ? ud.querySelector('.sp-arrow') : null;
      var kind = 'same';
      if (arrow) {
        if (arrow.classList.contains('up')) kind = 'up';
        else if (arrow.classList.contains('down')) kind = 'down';
        else if (arrow.classList.contains('new')) kind = 'new';
      }
      var ch = ud ? ud.querySelector('.ch-txt') : null;
      items.push({ n: n, href: a ? (a.getAttribute('href') || '') : '', title: title, kind: kind, amount: ch ? (ch.textContent || '').trim() : '' });
    }
    return items;
  }
  // 아직 안 받은 종류를 하나씩 차례로 요청 (앞 것이 채워지거나 12초가 지나면 다음)
  var homeFnRetry = { rank: 0, hot: 0 };
  function homeRequestLists(mode) {
    if (homeChainBusy[mode] || homeChainDone[mode]) return;
    var fn = mode === 'hot' ? window.gallery_hot_call : window.gallery_rank_call;
    if (typeof fn !== 'function') {
      if (homeFnRetry[mode] < 15) {
        homeFnRetry[mode]++;
        setTimeout(function () { homeRequestLists(mode); }, 300);
      }
      return;
    }
    var types = HC_LOAD[mode];
    var step = 0;
    homeChainBusy[mode] = true;
    function next() {
      while (step < types.length && homeCatItems(mode, step).length) step++;
      if (step >= types.length) { homeChainBusy[mode] = false; homeChainDone[mode] = true; try { schedule(); } catch (e) {} return; }
      var idx = step, t0 = Date.now();
      // 디시 gallery_rank_call / gallery_hot_call은 해당 tag가 true이면 요청을 건너뛰므로 호출 직전에 false로 풀고 요청
      try { window[HC_TAGS[mode][idx]] = false; } catch (e) {}
      try { fn(types[idx]); } catch (e) {}
      (function wait() {
        if (homeCatItems(mode, idx).length || Date.now() - t0 > 12000) {
          try { schedule(); } catch (e) {}
          step = idx + 1;
          setTimeout(next, 250);
          return;
        }
        setTimeout(wait, 250);
      })();
    }
    next();
  }
  // 실북갤/흥한갤 전환: 보여 줄 종류를 바꾸고 목록을 받아 다음 화면 갱신 때 다시 그림
  function homeCardsMode(m) {
    if (m !== 'hot' && m !== 'rank') return;
    homeMode = m;
    homeCardsSig = '';
    homeChainDone[m] = false;
    homeRequestLists(m);
    setTimeout(schedule, 50);
    setTimeout(schedule, 800);
    setTimeout(schedule, 2000);
  }
  function homeCardsBuild(sec) {
    if (!sec || !isHomePage()) return;
    var mode = homeCurMode();
    sec.classList.add('dcapp-hc-host');
    Array.prototype.forEach.call(sec.children, function (ch) {
      if (!/dcapp-hc/.test(clsOf(ch))) ch.classList.add('dcapp-hc-raw');
    });
    homeRequestLists(mode);
    var cats = HC_CATS.map(function (name, i) { return { name: name, items: homeCatItems(mode, i) }; });
    var sig = mode + '|' + cats.map(function (c) {
      return c.items.map(function (it) { return it.n + '~' + it.kind + '~' + it.amount + '~' + it.title + '~' + it.href; }).join(';');
    }).join('/');
    var root = sec.querySelector(':scope > .dcapp-hc');
    if (root && sig === homeCardsSig) return;
    homeCardsSig = sig;
    // 다시 그릴 때 각 카드의 좌우 위치를 유지 (같은 모드일 때만)
    var keep = [];
    if (!root) {
      root = document.createElement('div');
      root.className = 'dcapp-hc';
      sec.appendChild(root);
    } else if (root.getAttribute('data-mode') === mode) {
      root.querySelectorAll('.dcapp-hc-track').forEach(function (t) { keep.push(t.scrollLeft); });
    }
    root.setAttribute('data-mode', mode);
    if (!root.__dcappBound) {
      root.__dcappBound = true;
      root.addEventListener('click', function (e) {
        var b = e.target && e.target.closest ? e.target.closest('button[data-m]') : null;
        if (!b) return;
        e.preventDefault();
        homeCardsMode(b.getAttribute('data-m'));
      });
    }
    root.innerHTML = '';
    var top = document.createElement('div');
    top.className = 'dcapp-hc-card dcapp-hc-top';
    var seg = document.createElement('div');
    seg.className = 'dcapp-hc-seg';
    [['rank', '실북갤'], ['hot', '흥한갤']].forEach(function (pair) {
      var b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('data-m', pair[0]);
      if (mode === pair[0]) b.className = 'on';
      b.textContent = pair[1];
      seg.appendChild(b);
    });
    top.appendChild(seg);
    root.appendChild(top);
    var grid = document.createElement('div');
    grid.className = 'dcapp-hc-grid';
    cats.forEach(function (c) {
      var card = document.createElement('section');
      card.className = 'dcapp-hc-card';
      var h = document.createElement('h3');
      h.className = 'dcapp-hc-title';
      h.textContent = c.name;
      card.appendChild(h);
      var track = document.createElement('div');
      track.className = 'dcapp-hc-track';
      var dots = document.createElement('div');
      dots.className = 'dcapp-hc-dots';
      var made = 0;
      for (var pg = 0; pg < HC_PAGES; pg++) {
        var pageItems = c.items.filter(function (it) { return Math.floor((it.n - 1) / HC_PAGE) === pg; });
        if (!pageItems.length) continue;
        var ol = document.createElement('ol');
        ol.className = 'dcapp-hc-list dcapp-hc-page';
        pageItems.forEach(function (it) {
          var li = document.createElement('li');
          var a = document.createElement('a');
          a.className = 'dcapp-hc-link';
          if (it.href) a.setAttribute('href', it.href);
          var no = document.createElement('span');
          no.className = 'dcapp-hc-no';
          no.textContent = String(it.n);
          var tt = document.createElement('span');
          tt.className = 'dcapp-hc-tt';
          tt.textContent = it.title;
          var ch = document.createElement('span');
          var amt = it.amount ? ' ' + it.amount : '';
          ch.className = 'dcapp-hc-ch dcapp-hc-' + it.kind;
          ch.textContent = it.kind === 'up' ? '▲' + amt : it.kind === 'down' ? '▼' + amt : it.kind === 'new' ? 'NEW' : '–';
          a.appendChild(no);
          a.appendChild(tt);
          a.appendChild(ch);
          li.appendChild(a);
          ol.appendChild(li);
        });
        track.appendChild(ol);
        made++;
      }
      if (!made) {
        var wait = document.createElement('ol');
        wait.className = 'dcapp-hc-list dcapp-hc-page';
        var waiting = document.createElement('li');
        waiting.className = 'dcapp-hc-empty';
        waiting.textContent = '불러오는 중…';
        wait.appendChild(waiting);
        track.appendChild(wait);
        made = 1;
      }
      for (var k = 0; k < made && made > 1; k++) {
        var dot = document.createElement('span');
        dot.className = 'dcapp-hc-dot' + (k === 0 ? ' on' : '');
        dots.appendChild(dot);
      }
      track.addEventListener('scroll', function () {
        var w = track.clientWidth || 1;
        var cur = Math.round(track.scrollLeft / w);
        Array.prototype.forEach.call(dots.children, function (dt, j) { dt.classList.toggle('on', j === cur); });
      }, { passive: true });
      card.appendChild(track);
      if (made > 1) card.appendChild(dots);
      grid.appendChild(card);
    });
    root.appendChild(grid);
    root.querySelectorAll('.dcapp-hc-track').forEach(function (t, i) { if (keep[i]) t.scrollLeft = keep[i]; });
    // 홈 4블록 중 아직 '불러오는 중…' 상태인 블록이 있으면 자동으로 재요청(필요 시 1회 새로고침)
    if (root.querySelector('.dcapp-hc-empty')) {
      if (!window.__dcappHomeWatch) {
        window.__dcappHomeWatchTries = (window.__dcappHomeWatchTries || 0);
        window.__dcappHomeWatch = setTimeout(function () {
          window.__dcappHomeWatch = null;
          if (!isHomePage()) return;
          if (!document.querySelector('.dcapp-hc-empty')) {
            try { sessionStorage.removeItem('dcapp_home_reloaded'); } catch (e) {}
            return;
          }
          window.__dcappHomeWatchTries = (window.__dcappHomeWatchTries || 0) + 1;
          if (window.__dcappHomeWatchTries <= 2) {
            try { homeRequestLists(homeMode); } catch (e) {}
          } else {
            try {
              if (!sessionStorage.getItem('dcapp_home_reloaded')) {
                sessionStorage.setItem('dcapp_home_reloaded', '1');
                location.reload();
              }
            } catch (e) {}
          }
        }, 2000);
      }
    } else {
      window.__dcappHomeWatchTries = 0;
      try { sessionStorage.removeItem('dcapp_home_reloaded'); } catch (e) {}
    }
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
    try { homeCardsBuild(document.querySelector('section.rank-group') || panel); } catch (e) {}
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
  var tintKey = '', tintN = 0, tintTimer = null, tintFirstDone = false;
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
      if (body && body.contains(el) && !el.classList.contains('dcapp-defer-btn') && !el.classList.contains('dcapp-defer-all')) continue;                     // 글 본문은 그대로 (이미지 숨김 버튼은 테마 색 연동)
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
    tintTimer = setTimeout(function () { tintTimer = null; try { tintPage(); } catch (e) {} }, 40);
  }
  window.addEventListener('load', function () { if (cfg.tint) { try { tintPage(); } catch (e) {} } }, { passive: true });
  // 영상·소리가 시작되면 앱에 알림 → 배경 음악 유지 설정이 켜져 있으면 앱이 오디오 세션을 다시 맞춤 (WebKit이 세션을 바꾸는 것 대응)
  (function () {
    if (window.__dcappMediaPlay) return;
    window.__dcappMediaPlay = true;
    document.addEventListener('play', function (e) {
      var t = e.target;
      if (t && (t.tagName === 'VIDEO' || t.tagName === 'AUDIO')) post('mediaPlay', {});
    }, true);
  })();
  // 투표 iframe의 '공유하기'가 보낸 소스 문자열을 앱으로 전달 → 앱이 클립보드에 복사 (공유 팝업은 띄우지 않음)
  function ensureVoteCopyListener() {
    if (window.__dcappVoteMsg) return;
    window.__dcappVoteMsg = true;
    window.addEventListener('message', function (ev) {
      if (ev.origin !== location.origin || !ev.data) return;
      if (typeof ev.data.__dcappVoteCopy === 'string') { post('voteCopy', { text: ev.data.__dcappVoteCopy }); return; }
      if (typeof ev.data.__dcappVoteImage === 'string') { post('voteImage', { url: ev.data.__dcappVoteImage, ref: ev.data.__dcappVoteRef || '' }); }
    });
    // 투표 iframe의 onclick=parent.showVoteImg("id=...&no=...") 호출을 메인 창에서 직접 가로채 원본 팝업 주소 전달
    if (!window.showVoteImg || !window.showVoteImg.__dcapp) {
      var origShowVoteImg = window.showVoteImg;
      var wrappedShowVoteImg = function (arg) {
        var q = String(arg || '').replace(/&amp;/g, '&').trim();
        if (q) {
          var query = /(^|&)no=/.test(q) ? q : ('no=' + q);
          var photo = 'https://image.dcinside.com/viewimagePop.php?' + query;
          try { post('voteImage', { url: photo, ref: location.href }); return; } catch (e) {}
        }
        if (typeof origShowVoteImg === 'function') return origShowVoteImg.apply(this, arguments);
      };
      wrappedShowVoteImg.__dcapp = true;
      window.showVoteImg = wrappedShowVoteImg;
    }
  }
  function styleVoteIframes() {
    ensureVoteCopyListener();
    var dark = document.documentElement.classList.contains('darkmode');
    document.querySelectorAll('iframe[id^="vote_iframe"], iframe[src*="vote"], iframe[src*="poll"]').forEach(function (fr) {
      function inject() {
        try {
          var doc = fr.contentDocument;
          if (!doc || !doc.head) return;
          doc.documentElement.classList.toggle('darkmode', dark);
          // 공유하기 버튼: 디시 공유 팝업보다 먼저 가로채서 <iframe src="…"></iframe> 소스만 앱으로 보냄 (한 번만 붙임)
          if (!doc.__dcappShare) {
            doc.__dcappShare = true;
            doc.addEventListener('click', function (e) {
              var t = e.target && e.target.nodeType === 1 ? e.target : (e.target && e.target.parentElement);
              var b = t && t.closest ? t.closest('.sp-sharesns, .btn-vote-sns, button[class*="share"], a[class*="share"], button[class*="sns"], a[class*="sns"]') : null;
              if (!b) return;
              e.preventDefault(); e.stopPropagation();
              if (e.stopImmediatePropagation) e.stopImmediatePropagation();
              var src = fr.src || fr.getAttribute('src') || '';
              if (!src) return;
              var code = '<iframe src="' + src.replace(/&/g, '&amp;').replace(/"/g, '&quot;') + '"></iframe>';
              try { window.parent.postMessage({ __dcappVoteCopy: code }, location.origin); } catch (err) {}
            }, true);
          }
          // 투표 보기 썸네일: 디시의 showVoteImg(전체 화면 검은 층)보다 먼저 가로채서 앱의 미리보기 창으로 (사진 번호 → 디시 사진 주소)
          if (!doc.__dcappVoteImg) {
            doc.__dcappVoteImg = true;
            doc.addEventListener('click', function (e) {
              var t = e.target && e.target.nodeType === 1 ? e.target : (e.target && e.target.parentElement);
              if (!t || !t.closest || !t.closest('.vote-ask-lst, .vote-gp-lst, .vote-thum, .vote-thum-img, .vote-view-inner, [class*="vote"]')) return;
              var num = '';
              var oc = t.closest('[onclick*="showVoteImg"]');
              if (!oc) {
                var li = t.closest('li');
                if (li) oc = li.querySelector('[onclick*="showVoteImg"]');
              }
              if (oc) {
                var m1 = /showVoteImg\(\s*['"]?([^'"\s),]+)/.exec(oc.getAttribute('onclick') || '');
                if (m1) num = m1[1];
              }
              if (!num) {
                var im = t.tagName === 'IMG' ? t : (t.querySelector ? t.querySelector('img') : null);
                var src0 = im ? (im.getAttribute('src') || im.getAttribute('data-original') || '') : '';
                var m2 = /viewimage\.php\?([^"'\s]+)/.exec(src0);
                if (m2) num = m2[1];
              }
              if (!num) return;
              e.preventDefault(); e.stopPropagation();
              if (e.stopImmediatePropagation) e.stopImmediatePropagation();
              // 사진 주소: 썸네일 onclick 인자는 "id=…&no=…" 전체. 디시 팝업 주소(viewimagePop.php)를 그대로 넘김 (큰 원본 사진을 여는 주소)
              num = String(num).replace(/&amp;/g, '&');
              var query = /(^|&)no=/.test(num) ? num : ('no=' + num);
              var photo = 'https://image.dcinside.com/viewimagePop.php?' + query;
              // Referer는 글 주소가 아니라 이 투표 iframe의 src (사진 서버가 투표 주소의 Referer만 받음)
              try { window.parent.postMessage({ __dcappVoteImage: photo, __dcappVoteRef: fr.src || '' }, location.origin); } catch (err) {}
            }, true);
          }
          var st = doc.getElementById('dcapp-vote-style');
          if (!st) {
            st = doc.createElement('style');
            st.id = 'dcapp-vote-style';
            doc.head.appendChild(st);
          }
          var mainSt = document.getElementById('dcapp-style');
          // 투표 iframe 안: 배경은 투명(바깥 글 배경이 보이게), .vote-view-inner를 iframe 경계에서 2px 안쪽으로 넣어 둥근 모서리 4곳이 잘리지 않게 함
          var extra = '\nhtml,body{background:transparent!important;margin:0!important}.vote-view-scope{margin:0!important;background:transparent!important}.vote-view-inner{margin:2px!important;width:calc(100% - 4px)!important;box-sizing:border-box!important}';
          if (mainSt && st.textContent !== mainSt.textContent + extra) st.textContent = mainSt.textContent + extra;
          var inner = doc.querySelector('.vote-view-inner');
          var h = inner ? inner.offsetHeight : (doc.documentElement ? doc.documentElement.scrollHeight : 0);
          if (h > 40) fr.style.setProperty('height', (h + 6) + 'px', 'important');
        } catch (e) {}
      }
      inject();
      if (!fr.__dcappVoteHook) { fr.__dcappVoteHook = true; fr.addEventListener('load', inject); }
    });
  }
  function suppressGallInfoPop(ms) {
    try { sessionStorage.setItem('dcapp_suppress_gall_info', String(Date.now() + (ms || 4000))); } catch (e) {}
  }
  function isGallInfoSuppressed() {
    try {
      var until = Number(sessionStorage.getItem('dcapp_suppress_gall_info') || '0');
      if (until > Date.now()) return true;
      if (until) sessionStorage.removeItem('dcapp_suppress_gall_info');
    } catch (e) {}
    return false;
  }
  function closeMinorInfoPopNow() {
    try { if (typeof window.mgall_popClose === 'function') window.mgall_popClose(); } catch (e) {}
    document.querySelectorAll('#minor_info_pop, #major_info_pop, .layer-center-popup[id*="info_pop"]').forEach(function (el) {
      el.style.setProperty('display', 'none', 'important');
    });
  }
  function hideGallogListBtn() {
    if (/^\/managehistory\//.test(location.pathname)) {
      document.documentElement.classList.add('dcapp-managehistory');
      suppressGallInfoPop(5000);
    }
    if (isGallInfoSuppressed()) closeMinorInfoPopNow();
    if (!window.__dcappMinorPopHook) {
      window.__dcappMinorPopHook = true;
      var closeMinorInfoPop = closeMinorInfoPopNow;
      window.addEventListener('pagehide', closeMinorInfoPop);
      window.addEventListener('popstate', function () {
        closeMinorInfoPop();
        setTimeout(closeMinorInfoPop, 0);
        setTimeout(closeMinorInfoPop, 180);
      });
      window.addEventListener('pageshow', function () {
        closeMinorInfoPop();
        setTimeout(closeMinorInfoPop, 0);
        setTimeout(closeMinorInfoPop, 180);
      });
      document.addEventListener('click', function (ev) {
        var t = ev.target && ev.target.closest ? ev.target.closest('.gall_history_btn, [onclick*="managehistory"], a[href*="managehistory"]') : null;
        if (t) {
          suppressGallInfoPop(5000);
          closeMinorInfoPop();
          setTimeout(closeMinorInfoPop, 100);
          setTimeout(closeMinorInfoPop, 500);
        }
      }, true);
    }
    if (!/\/gallog\//.test(location.pathname)) return;
    var root = document.querySelector('.gallog-wrapping') || document.body;
    if (!root) return;
    root.querySelectorAll('button, a, select, div, span, p, li').forEach(function (el) {
      if (el.classList.contains('dcapp-gallog-hide')) return;
      var matched = false;
      if (el.tagName === 'SELECT') {
        var opt = el.options && el.options[el.selectedIndex];
        var ot = (opt ? opt.textContent : el.textContent || '').replace(/\s+/g, ' ').trim();
        if (ot.indexOf('글 목록') >= 0 || ot.indexOf('글목록') >= 0) matched = true;
      } else {
        var direct = '';
        for (var i = 0; i < el.childNodes.length; i++) {
          if (el.childNodes[i].nodeType === 3) direct += el.childNodes[i].nodeValue || '';
        }
        direct = direct.replace(/\s+/g, ' ').trim();
        var full = (el.textContent || '').replace(/\s+/g, ' ').trim();
        if (direct === '글 목록' || direct === '▼ 글 목록' || direct === '▲ 글 목록' || direct === '▾ 글 목록' || direct === '글목록' ||
            (full.length <= 16 && (full.indexOf('글 목록') >= 0 || full.indexOf('글목록') >= 0))) {
          matched = true;
        }
      }
      if (!matched) return;
      var box = el;
      while (box.parentElement && box.parentElement !== root && box.parentElement !== document.body) {
        var p = box.parentElement;
        if (p.querySelector('ul.all-comment-lst, ul.gall-detail-lst, #guest_write, .menu-box')) break;
        var h = p.getBoundingClientRect ? p.getBoundingClientRect().height : 0;
        if (h > 90) break;
        box = p;
      }
      box.classList.add('dcapp-gallog-hide');
    });
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
    // 고닉 식별코드 보기: 메모가 없는 고닉(아이디 있음, 유동 아님)의 메모 자리에 아이디를 '보여주기만' 함 (메모로 저장 안 함, 자동메모와는 같이 못 씀)
    if (!texts.length && cfg.showIdCode === true && !cfg.autoMemo && idn.id && !idn.ip) m = { t: idn.id };
    // 자동메모: 글 목록의 로그인 계정(아이디 있음, 유동 아님)에 보이는 메모가 하나도 없으면 아이디로 메모
    if (!texts.length && cfg.autoMemo && (u.kind === 'post' || u.kind === 'comment') && idn.id && !idn.ip) {
      var okGallery = cfg.autoMemo === 'all' || (cfg.autoMemo === 'gallery' && gid) ||
        (cfg.autoMemo === 'selected' && gid && (cfg.autoMemoGalleries || []).indexOf(gid) >= 0);
      if (okGallery) queueAutoMemo(idn.id, cfg.autoMemo === 'all' ? '' : gid);
    }
    var host = nk.parentNode;
    // 닉네임 칸(ginfo-area) 안에서는 닉네임·IP·갤로그 아이콘 뒤에 메모를 둠
    var kids = Array.prototype.filter.call(host.children, function (c) { return !c.classList.contains('dcapp-memo'); });
    var anchor = host.classList.contains('ginfo-area') && kids.length ? kids[kids.length - 1] : nk;
    var tag = host.querySelector(':scope > .dcapp-memo');
    if (m) {
      if (!tag) {
        tag = document.createElement('span');
        tag.className = 'dcapp-memo';
      }
      if (tag.parentNode !== host || tag.previousElementSibling !== anchor) host.insertBefore(tag, anchor.nextSibling);
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
  function anonGalleryId() {
    var parts = location.pathname.split('/').filter(Boolean);
    if (parts.length < 2) return '';
    var id = parts[1];
    if ((id === 'write' || id === 'modify' || id === 'delete') && parts.length >= 3) id = parts[2];
    return id.replace(/^(mi|pr)\$/, '');
  }
  function fillAnon() {
    if (loginState() === 'in') return;     // 로그인 상태면 유동 닉네임을 채우지 않음 (채우면 로그인 댓글인데도 코드 입력이 뜸)
    var allF = anonFields();
    var a = cfg.anon || {};
    var ag = (cfg.anonG || {})[anonGalleryId()];
    if (ag) a = { nick: ag.nick || a.nick, pw: ag.pw || a.pw };      // 갤러리별 설정이 우선
    allF.forEach(function (f) {
      // 비밀번호 칸이 없는 폼 = 로그인 상태(갤닉 'ㅇㅇ' 포함). 여기에 유동 닉네임을 채우면 갤닉이 꺼져 코드 입력이 뜸
      if (f.kind === 'nick') {
        var scope = f.el.closest('form') || document;
        var hasPw = allF.some(function (g) { return g.kind === 'pw' && scope.contains(g.el); });
        if (!hasPw) return;
      }
      if (f.el.getAttribute('data-dcapp-user') === '1') return;     // 직접 입력한 칸
      if (f.el.getAttribute('data-dcapp-unlocking') === '1') return; // 지금 푸는 중
      var tries = +(f.el.getAttribute('data-dcapp-anon-tries') || 0);
      if (tries >= 4) return;
      var saved = f.kind === 'pw' ? a.pw : a.nick;
      if (!saved) return;
      var locked = f.el.disabled || f.el.readOnly;
      var cur = f.el.value;
      if (!locked && cur === saved) return;
      // 잠기지 않은 칸에 이미 있는 값(디시가 기억해 둔 이전 닉네임·비밀번호)은 앱 설정으로 바꿈. 사람이 직접 친 칸은 위에서 이미 제외
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
  function openGalleryInfo() {
    try { sessionStorage.removeItem('dcapp_suppress_gall_info'); } catch (e) {}
    var btn = document.querySelector('a.sp-mgallinfo, [onclick*="Mgallinfo"], [onclick*="gallinfo"], .btn-gall-info, .sp-info');
    if (btn) { try { btn.click(); return 'ok'; } catch (e) {} }
    if (typeof window.Mgallinfo === 'function') { try { window.Mgallinfo(); return 'ok'; } catch (e) {} }
    if (typeof window.mgall_popOpen === 'function') { try { window.mgall_popOpen(); return 'ok'; } catch (e) {} }
    return 'none';
  }
  function openManageLog() {
    suppressGallInfoPop(5000);
    var a = manageLogLink();
    if (!a) return 'none';
    var closePop = function () {
      try { if (typeof window.mgall_popClose === 'function') window.mgall_popClose(); } catch (e) {}
      document.querySelectorAll('#minor_info_pop, #major_info_pop, .layer-center-popup[id*="info_pop"]').forEach(function (el) {
        el.style.setProperty('display', 'none', 'important');
      });
    };
    closePop();
    setTimeout(closePop, 100);
    setTimeout(closePop, 500);
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
    'li.adv-inner', '.adv-group', '.pwlink', 'li:not(.notice):has(> .detail-top-lnk)', '#app_down_pop', '.layer-bottom-popup',
    '.outside-search-box',
    // 글 본문 아래 'AD | 더 알아보기' 광고 칸 (회색 띠째로)
    '[class*="adv-group"]', '[id^="rtbx-ad"]', '[id*="rtbx"]', '[class*="rtbx"]'
  ];
  /// 글 목록 맨 위의 'AD' / '설문' 줄 (선택자로 못 잡는 경우 글자로)
  function hideListPromos() {
    if (cfg.adBlock === false) return;
    document.querySelectorAll('ul.gall-detail-lst > li:not(.app-info-ban):not(.dcapp-pg-sep)').forEach(function (li) {
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
  /// 댓글 수 아이콘(말풍선, 선 모양). 행 오른쪽 캡슐의 .ct 앞에 한 번만 넣음
  var CMT_ICON = '<svg class="dcapp-cmt-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 4v-4H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>';
  function listCommentCount() {
    document.querySelectorAll('ul.gall-detail-lst > li:not(.app-info-ban):not(.dcapp-pg-sep)').forEach(function (li) {
      var ct = li.querySelector('.ct');
      if (!ct) return;
      var box = ct.closest('a.rt') || ct.closest('.rt') || ct;
      var title = li.querySelector('.subjectin') || li.querySelector('.subject-add') || li.querySelector('.subject');
      if (!title) return;
      var n = (ct.textContent || '').replace(/[^0-9]/g, '');
      // 썸네일 목록·댓글 검색 목록·글 아래 목록은 예전처럼 제목 뒤 [n]으로 표시
      if (li.closest('ul.gall-detail-lst.thum, ul.gall-detail-lst.sch-comment, #view_next')) {
        var tag0 = li.querySelector('.dcapp-cmt');
        if (n && n !== '0') {
          if (!tag0) { tag0 = document.createElement('span'); tag0.className = 'dcapp-cmt'; title.parentNode.insertBefore(tag0, title.nextSibling); }
          if (tag0.textContent !== '[' + n + ']') tag0.textContent = '[' + n + ']';
        } else if (tag0) tag0.parentNode.removeChild(tag0);
        box.classList.add('dcapp-hide');
        return;
      }
      // 일반 글 목록: 행 오른쪽 캡슐(아이콘 + 숫자). 제목 뒤 [n]은 두지 않음
      var oldTag = li.querySelector('.dcapp-cmt');
      if (oldTag) oldTag.parentNode.removeChild(oldTag);
      box.classList.remove('dcapp-hide');
      box.classList.add('dcapp-cmtbadge');
      box.classList.toggle('dcapp-cmt-zero', !n || n === '0');
      if (!ct.querySelector('svg.dcapp-cmt-ico')) ct.insertAdjacentHTML('afterbegin', CMT_ICON);
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
  // 원격 필터(애드가드 디시 필터)의 숨김 규칙: 앱이 골라 보낸 cfg.adFilterCSS (한 줄에 규칙 하나). 광고차단이 꺼지면 뺌
  // 글·목록·댓글·입력 영역을 잡는 규칙은 지금 페이지에서 확인해 빼고 넣음 (새 필터가 와도 글이 가려지지 않게)
  var AD_FILTER_KEEP = 'ul.gall-detail-lst,#comment_box,.thum-txt,.gallview-tit-box,#pagination_div,#textbox,.note-editable,#subject,#view_btn_area,.btm-btns-both,.reco-icon-lst,#dcapp-headbar,#dcapp-pgwrap,#dcapp-pgbar,form,textarea,input,article';
  function adFilterCSS() {
    var css = cfg.adBlock === false ? '' : String(cfg.adFilterCSS || '');
    var st = document.getElementById('dcapp-adfilter');
    if (!css) { if (st) st.parentNode.removeChild(st); return; }
    if (!document.body || (st && st.__dcappSrc === css)) return;
    var keep = [];
    css.split('\n').forEach(function (rule) {
      if (!rule) return;
      var sel = rule.replace(/\{display:none!important\}$/, '');
      try {
        var hit = false;
        document.querySelectorAll(sel).forEach(function (el) {
          if (el.matches(AD_FILTER_KEEP) || el.querySelector(AD_FILTER_KEEP)) hit = true;
        });
        if (!hit) keep.push(rule);
      } catch (e) {}
    });
    if (!st) {
      st = document.createElement('style');
      st.id = 'dcapp-adfilter';
      (document.head || document.documentElement).appendChild(st);
    }
    st.textContent = keep.join('\n');
    st.__dcappSrc = css;
  }

  // ---------- 글 아래 수정·삭제 버튼 (본인 글 / 유동 글에만 디시가 보여 줌) → 개추/비추 줄에 앱 버튼으로 ----------
  function postActionButton(kind) {
    return document.querySelector('#view_btn_area button[onclick*="' + (kind === 'delete' ? 'board_delete' : 'board_modify') + '"]');
  }
  function reportPost() {
    var b = document.querySelector('.reco-icon-lst .sp-report');
    if (!b) return 'none';
    b.click();
    return 'clicked';
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

  // ---------- 댓글 헤더: '댓글 입력' 버튼 (누르면 댓글 입력창으로) ----------
  // 댓글 입력 버튼은 document에서 한 번만 받음 (헤더가 다시 그려져도 계속 동작)
  var cmtInputBound = false;
  function focusCommentInput() {
    var ta = document.getElementById('comment_memo');
    if (!ta) return;
    if (nativeCmtOn()) { composeFor(ta); return; }
    // 댓글창이 아래 고정(dock)돼 있으면 위치 이동 없이 포커스만
    if (!ta.closest('.dcapp-docked')) ta.scrollIntoView({ block: 'center' });
    ta.focus();
    if (document.activeElement !== ta) { ta.blur(); ta.focus(); }
  }
  // 화면에 보이는 댓글 머리글 (디시가 다시 그리면 옛 머리글이 남아 있을 수 있어서 보이는 것을 고름)
  function commentHeader() {
    var hs = document.querySelectorAll('#comment_box .all-comment-tit');
    if (!hs.length) hs = Array.prototype.filter.call(document.querySelectorAll('.all-comment-tit'), function (h) { return !h.closest('[id^="img_comment_div"]'); });
    for (var i = 0; i < hs.length; i++) {
      if (hs[i].querySelector('.tit-box') && hs[i].getBoundingClientRect().height > 0) return hs[i];
    }
    return hs.length ? hs[0] : null;
  }
  function buildCommentInputBtn() {
    if (!cmtInputBound) {
      cmtInputBound = true;
      document.addEventListener('click', function (e) {
        var btn = e.target && e.target.closest ? e.target.closest('.dcapp-cmtin') : null;
        if (!btn) return;
        e.preventDefault();
        e.stopPropagation();
        focusCommentInput();
      }, true);
    }
    var hdr = commentHeader();
    var tb = hdr && hdr.querySelector('.tit-box');
    if (!tb) return;
    document.querySelectorAll('.dcapp-cmtin').forEach(function (x) { if (!hdr.contains(x)) x.parentNode.removeChild(x); });
    if (hdr.querySelector('.dcapp-cmtin')) return;
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'dcapp-cmtin';
    b.textContent = '댓글 입력';
    tb.parentNode.insertBefore(b, tb.nextSibling);
  }

  // ---------- 댓글 정렬: 등록순 / 최신순 / 답글순을 체크 버튼으로 (기본 등록순, 선택은 파란색) ----------
  var SORT_ITEMS = [['default', '등록순'], ['new', '최신순'], ['reply', '답글순']];
  var SORT_CHECK = '<svg viewBox="0 0 16 16"><path d="M3 8.4l3.2 3.2L13 4.6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  function rebuildCommentHeader() {
    try { buildCommentSort(); buildCommentInputBtn(); } catch (e) {}
  }
  // 듀오 안전 영역 막이 정렬 버튼 위에 있으면, 탭이 막(html 요소)에 떨어져 click의 대상이 html이 됨.
  // 그때 좌표가 정렬 버튼 안이면 그 버튼을 눌러 줌. 버튼을 직접 누른 경우(대상이 버튼)에는 아무것도 하지 않아 중복 호출이 없음
  function installSortTapGuard() {
    if (window.__dcappSortGuard) return;
    window.__dcappSortGuard = true;
    document.addEventListener('click', function (e) {
      var de = document.documentElement;
      if (e.target !== de && e.target !== document) return;
      if (!/(^|\s)dcapp-duo(col|flip)(\s|$)/.test(de.className || '')) return;
      var btns = document.querySelectorAll('.dcapp-sort button');
      for (var i = 0; i < btns.length; i++) {
        var r = btns[i].getBoundingClientRect();
        if (e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom) {
          e.preventDefault();
          e.stopPropagation();
          btns[i].click();
          return;
        }
      }
    }, true);
  }
  function buildCommentSort() {
    installSortTapGuard();
    var hdr = commentHeader();
    var sel = hdr && hdr.querySelector('select.sel');
    var rt = hdr && hdr.querySelector('.rt');
    if (!sel || !rt) return;
    document.querySelectorAll('.dcapp-sort').forEach(function (x) { if (!rt.contains(x)) x.parentNode.removeChild(x); });
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
          // 머리글이 다시 그려졌을 수 있으니 누른 순간의 정렬 select를 찾아서 바꿈 (만들 때의 select는 옛것일 수 있음)
          var cur = commentHeader();
          var live = cur && cur.querySelector('select.sel');
          if (!live) return;
          live.value = it[0];
          live.dispatchEvent(new Event('change', { bubbles: true }));
          // 디시가 댓글 머리글을 새로 그린 뒤에도 버튼이 남도록, 조금 뒤에 몇 번 더 다시 만듦
          [0, 300, 1000].forEach(function (ms) { setTimeout(rebuildCommentHeader, ms); });
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

  // ---------- 글 아래 목록: 다음글 1개 · 이전글 1개만 보이고 나머지는 '글목록 더보기'로 접기 ----------
  var POST_RE = /\/(board|mini|person)\/([^\/]+)\/(\d+)/;
  function listCacheKey(gid) { return 'dcapp-list:' + gid; }
  // 글목록 화면을 볼 때 그 갤러리의 글번호·제목을 기억 (다음글 찾기용)
  function cacheListIds() {
    if (POST_RE.test(location.pathname)) return;
    var gid = currentGalleryId();
    if (!gid) return;
    var items = [];
    document.querySelectorAll('ul.gall-detail-lst:not(#view_next) > li a.lt').forEach(function (a) {
      var m = (a.getAttribute('href') || '').match(POST_RE);
      if (m && m[2] === gid) items.push({ no: parseInt(m[3], 10), t: txt(a.querySelector('.subjectin') || a) });
    });
    if (!items.length) return;
    var json = JSON.stringify(items.slice(0, 60));
    try { if (sessionStorage.getItem(listCacheKey(gid)) !== json) sessionStorage.setItem(listCacheKey(gid), json); } catch (e) {}
  }
  function buildNextPrev() {
    var vn = document.getElementById('view_next');
    var m = location.pathname.match(POST_RE);
    if (!vn || !m) return;
    var kind = m[1], gid = m[2], no = parseInt(m[3], 10);
    var lis = vn.querySelectorAll(':scope > li');
    if (lis.length > 1 && !vn.querySelector('.dcapp-more-li')) {
      var more = document.createElement('li');
      more.className = 'dcapp-more-li';
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'dcapp-more-btn';
      btn.textContent = '글목록 더보기';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        var open = vn.classList.toggle('dcapp-more-open');
        btn.textContent = open ? '접기' : '글목록 더보기';
      });
      more.appendChild(btn);
      lis[0].parentNode.insertBefore(more, lis[1] || null);
      Array.prototype.forEach.call(lis, function (li, i) { if (i > 0) li.classList.add('dcapp-fold'); });
    }
    var row = document.getElementById('dcapp-nextrow');
    if (!row) {
      row = document.createElement('div');
      row.id = 'dcapp-nextrow';
      vn.parentNode.insertBefore(row, vn);
    }
    var cached = null;
    try { cached = JSON.parse(sessionStorage.getItem(listCacheKey(gid)) || 'null'); } catch (e) {}
    var newer = null;
    if (cached) cached.forEach(function (x) { if (x.no > no && (!newer || x.no < newer.no)) newer = x; });
    // 내용이 같으면 DOM을 건드리지 않음 — 매번 다시 그리면 변화 감지(MutationObserver)가 apply를 또 불러서 무한 반복되고, 그 사이 댓글 탭이 씹힘
    var key = !cached ? '' : kind + '/' + gid + '/' + (newer ? newer.no + ':' + newer.t : '-');
    if (row.getAttribute('data-k') === key) return;
    row.setAttribute('data-k', key);
    if (!cached) { row.style.display = 'none'; return; }   // 목록을 본 기록이 없으면 숨김
    row.style.display = '';
    row.textContent = '';
    var label = document.createElement('span');
    label.className = 'dcapp-nlabel';
    label.textContent = '다음글';
    row.appendChild(label);
    if (newer) {
      var a = document.createElement('a');
      a.href = 'https://m.dcinside.com/' + kind + '/' + gid + '/' + newer.no;
      a.textContent = newer.t;
      row.appendChild(a);
    } else {
      var none = document.createElement('span');
      none.className = 'dcapp-none';
      none.textContent = '다음 글 없음';
      row.appendChild(none);
    }
  }

  // 디시가 글 아래에 두는 '목록보기' 버튼
  function listButton() {
    var area = document.querySelector('.gall-thum-btm') || document;
    var c = area.querySelectorAll('button, a');
    for (var i = 0; i < c.length; i++) if (txt(c[i]) === '목록보기') return c[i];
    return null;
  }
  function postAction(kind) {
    if (kind === 'list' && cfg.splitDetail) { post('gotolist', {}); return true; }   // 분할 화면 오른쪽: 이 화면이 아니라 왼쪽 목록을 이 갤러리 목록으로
    if (kind === 'list') { var lb = listButton(); if (!lb) return false; lb.click(); return true; }
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

  /// 추천·비추천 누르기 (디시 버튼을 대신 누름). 코드 칸이 있는데 비어 있으면 누르지 않고 코드 상자를 펼쳐 입력칸에 포커스
  /// (빈 코드로 누르면 디시가 코드를 또 요구해 상자가 쌓임). 코드를 넣었거나 코드가 필요 없으면 디시 버튼을 누름
  /// 코드 확인 버튼 문구: 마지막으로 누른 추천·비추천에 맞춤
  function setVoteOkText() {
    var ok = document.querySelector('.dcapp-vcode-ok');
    var t = '입력한 코드로 ' + (voteLast === 'down' ? '비추천' : '추천');
    if (ok && ok.textContent !== t) ok.textContent = t;
  }

  /// 추천·비추천이 '다음에 다시 시도'로 실패하면 알림창 없이 0.2초 뒤 새로고침하고, 로딩 뒤 0.2초 뒤 같은 버튼을 다시 누름 (최대 20회).
  /// 멈추는 경우: 숫자가 바뀌어 성공 · 보안문자 상자가 필요 · 이미 추천 등 다른 안내 · 다른 글로 이동 · 20회 도달
  /// 상태는 세션 저장소에 두어 새로고침을 넘김. 알림은 페이지 안에서 가로채므로 앱 쪽 알림 처리는 바뀌지 않음
  var RECOM_KEY = 'dcapp-recom-retry', RECOM_MAX = 20, RECOM_TTL = 30000;
  var recomKindNow = null, recomRetryScheduled = false;
  var origAlert = window.alert;
  window.alert = function (msg) {
    var m = typeof msg === 'string' ? msg : '';
    if (recomKindNow && m.indexOf('다음에 다시 시도') > -1) { scheduleRecomRetry(recomKindNow); return; }
    if (typeof autoMoreState !== 'undefined' && autoMoreState.calling) autoMoreState.stopped = true;
    return origAlert.apply(window, arguments);
  };
  function recomState() {
    try { return JSON.parse(sessionStorage.getItem(RECOM_KEY) || 'null'); } catch (e) { return null; }
  }
  function recomClear() { try { sessionStorage.removeItem(RECOM_KEY); } catch (e) {} }
  function scheduleRecomRetry(kind) {
    recomRetryScheduled = true;
    var st = recomState();
    var n = st && st.url === location.href ? (st.n || 0) : 0;
    if (n >= RECOM_MAX) {
      recomClear();
      recomRetryScheduled = false;
      origAlert.call(window, '추천이 계속 실패해 자동 재시도를 멈췄어요 (' + RECOM_MAX + '회). 잠시 뒤 다시 눌러 주세요.');
      return;
    }
    try { sessionStorage.setItem(RECOM_KEY, JSON.stringify({ kind: kind, n: n + 1, url: location.href, t: Date.now() })); } catch (e) {}
    setTimeout(function () { location.reload(); }, 200);
  }
  function runRecomRetry() {
    var st = recomState();
    if (!st) return;
    if (st.url !== location.href || Date.now() - (st.t || 0) > RECOM_TTL) { recomClear(); return; }
    var down = st.kind === 'down';
    var btn = document.getElementById(down ? 'nonrecommend_join' : 'recommend_join');
    var cnt = document.getElementById(down ? 'nonrecomm_btn' : 'recomm_btn');
    if (!btn || document.getElementById('recom_join_box') || document.getElementById('captcha_codeF') || document.getElementById('captcha_codeR')) { recomClear(); return; }
    recomRetryScheduled = false;
    recomKindNow = down ? 'down' : 'up';
    btn.click();
    recomKindNow = null;
    setTimeout(function () { if (!recomRetryScheduled) recomClear(); }, 400);
  }
  if (document.readyState === 'complete') setTimeout(runRecomRetry, 200);
  else window.addEventListener('load', function () { setTimeout(runRecomRetry, 200); });

  function voteAction(key) {
    var map = { up: '#recommend_join', down: '#nonrecommend_join', best: '.reco-icon-lst .sp-bestchucon', pum: '.reco-icon-lst .sp-crosspost', report: '.reco-icon-lst .sp-report' };
    var area = document.querySelector('.reco-area');
    if (key === 'up' || key === 'down') {
      voteLast = key;
      setVoteOkText();
      var input = document.getElementById('captcha_codeF') || document.getElementById('captcha_codeR');
      if (input && !input.value.trim()) {
        if (area) area.classList.add('dcapp-codeopen');
        try { input.focus(); input.scrollIntoView({ block: 'center' }); } catch (e) {}
        return 'code';
      }
      voteWait = { key: key, before: textOf(key === 'up' ? '#recomm_btn' : '#nonrecomm_btn') };
      if (input && area) area.classList.add('dcapp-codeopen');     // 제출하는 동안 상자를 보여 줌 (성공하면 접힘)
    }
    var el = map[key] ? document.querySelector(map[key]) : null;
    if (el) { if (key === 'up' || key === 'down') recomKindNow = key; el.click(); recomKindNow = null; }
    if (key === 'up' || key === 'down') syncVoteCode();
    return el ? 'clicked' : 'none';
  }

  /// 디시가 붙인 추천 코드 상자(#recom_join_box)를 추천 영역 안으로 옮기고 펼침. 추천·비추천 숫자가 바뀌면(성공) 접음
  function syncVoteCode() {
    var area = document.querySelector('.reco-area');
    if (!area) return;
    var box = document.getElementById('recom_join_box');
    if (box && !area.contains(box)) area.insertBefore(box, area.firstChild);
    var done = false;
    if (voteWait) {
      var now = textOf(voteWait.key === 'up' ? '#recomm_btn' : '#nonrecomm_btn');
      if (now !== voteWait.before) { voteWait = null; done = true; }
    }
    if (done) {
      area.classList.remove('dcapp-codeopen');
      if (box && box.parentNode) box.parentNode.removeChild(box);
      area.querySelectorAll('.capcha-code-box input[type="text"]').forEach(function (i) { i.value = ''; });
    } else if (box) {
      area.classList.add('dcapp-codeopen');
    }
  }

  /// 코드 칸 이벤트 (추천 영역마다 한 번만): 입력칸에서 Enter → 확인 버튼과 같게 마지막 추천·비추천 누르기,
  /// 새로고침 링크 → 코드 그림을 새로 받고 입력칸 비우기 (디시 추천 상자에는 이 동작이 없어서 앱이 함)
  function attachCodeEvents(area) {
    if (area.getAttribute('data-dcapp-codeev') === '1') return;
    area.setAttribute('data-dcapp-codeev', '1');
    area.addEventListener('keydown', function (e) {
      var t = e.target;
      if ((e.key === 'Enter' || e.keyCode === 13) && t && t.tagName === 'INPUT' && t.closest && t.closest('.capcha-code-box')) {
        e.preventDefault();
        voteAction(voteLast);
      }
    });
    area.addEventListener('click', function (e) {
      var r = e.target && e.target.closest ? e.target.closest('.capcha-code-box .sp-reload') : null;
      if (!r) return;
      e.preventDefault();
      var box = r.closest('.capcha-code-box');
      var img = box ? box.querySelector('img') : null;
      if (img) img.setAttribute('src', (img.getAttribute('src') || '').split('&v=')[0] + '&v=' + Date.now());
      var input = box ? box.querySelector('input[type="text"]') : null;
      if (input) input.value = '';
    });
  }

  function buildVote() {
    // 디시가 코드를 또 요구하면 추천 코드 상자가 앞에 새로 붙음 → 가장 새 것 하나만 남기고 지움 (같은 id가 여럿이면 입력 칸이 엇갈림)
    var codeBoxes = document.querySelectorAll('#recom_join_box');
    for (var ci = 1; ci < codeBoxes.length; ci++) if (codeBoxes[ci].parentNode) codeBoxes[ci].parentNode.removeChild(codeBoxes[ci]);
    var area = document.querySelector('.reco-area');
    if (!area || !area.parentNode) return;
    attachCodeEvents(area);
    syncVoteCode();
    var v = document.querySelector('.dcapp-vote');
    if (!v) {
      var hasMem = !!area.querySelector('.go-ct'), hasDown = !!document.getElementById('nonrecommend_join');
      var picks = [['best', '.sp-bestchucon', ICON_BEST], ['pum', '.sp-crosspost', ICON_PUM]]
        .filter(function (p) { return area.querySelector(p[1]); });
      v = document.createElement('div');
      v.className = 'dcapp-vote';
      v.innerHTML = '<div class="dcapp-vmain">' +
        '<div class="dcapp-vbox up"><button type="button" class="dcapp-vcell" data-a="up">' + ICON_STAR + '</button><span class="dcapp-vnum"></span>' +
        (hasMem ? '<span class="dcapp-vmem"><svg viewBox="0 0 16 16"><rect width="16" height="16" rx="3" fill="#9a9aa0"/><text x="8" y="8" dominant-baseline="central" font-size="11" font-weight="700" text-anchor="middle" fill="#fff" font-family="Arial,sans-serif">g</text></svg><b></b></span>' : '') + '</div>' +
        (hasDown ? '<div class="dcapp-vbox down"><button type="button" class="dcapp-vcell" data-a="down">' + ICON_X + '</button><span class="dcapp-vnum"></span></div>' : '') +
        '<div class="dcapp-vicons">' + picks.map(function (p) { return '<button type="button" data-a="' + p[0] + '">' + p[2] + '</button>'; }).join('') + '</div>' +
        '</div>';
      area.parentNode.insertBefore(v, area);
      v.addEventListener('click', function (e) {
        var pa = e.target.closest ? e.target.closest('[data-p]') : null;
        if (pa) { postAction(pa.getAttribute('data-p')); return; }
        var b = e.target.closest ? e.target.closest('button[data-a], .dcapp-vnum') : null;
        if (!b) return;
        // 별·X 버튼뿐 아니라 숫자 칸을 눌러도 같은 동작 (숫자 칸에는 data-a가 없으니 상자 종류로 찾음)
        var key = b.getAttribute('data-a') || (b.closest('.dcapp-vbox').classList.contains('up') ? 'up' : 'down');
        voteAction(key);
      });
    }
    // 코드 칸(디시 추천 영역) 아래 확인 버튼: 입력한 코드로 마지막에 누른 추천·비추천을 다시 누름
    var okBtn = area.querySelector('.dcapp-vcode-ok');
    if (!okBtn) {
      okBtn = document.createElement('button');
      okBtn.type = 'button';
      okBtn.className = 'dcapp-vcode-ok';
      okBtn.addEventListener('click', function (e) { e.preventDefault(); voteAction(voteLast); });
      area.appendChild(okBtn);
    } else if (okBtn !== area.lastElementChild) {
      area.appendChild(okBtn);
    }
    setVoteOkText();
    // 수정·삭제: 본인 글 / 유동 글에서만 (오른쪽 끝)
    var editable = !!(postActionButton('modify') && postActionButton('delete'));
    var hasList = !!listButton();
    var pa = v.querySelector('.dcapp-postact');
    var want = (editable ? 'e' : '') + (hasList ? 'l' : '');
    if (pa && pa.getAttribute('data-k') !== want) { pa.parentNode.removeChild(pa); pa = null; }
    if (want && !pa) {
      pa = document.createElement('div');
      pa.className = 'dcapp-postact';
      pa.setAttribute('data-k', want);
      pa.innerHTML = (hasList ? '<button type="button" data-p="list">글목록</button>' : '') +
        (editable ? '<span class="grp"><button type="button" data-p="modify">수정</button><button type="button" data-p="delete" class="del">삭제</button></span>' : '');
      v.appendChild(pa);
    }
    function setText(el, t) { if (el && el.textContent !== t) el.textContent = t; }
    setText(v.querySelector('.up .dcapp-vnum'), textOf('#recomm_btn') || '0');
    setText(v.querySelector('.up .dcapp-vmem b'), textOf('#recomm_btn_member') || '0');
    setText(v.querySelector('.down .dcapp-vnum'), textOf('#nonrecomm_btn') || '0');
    var rj = document.getElementById('recommend_join'), cell = v.querySelector('.up .dcapp-vcell');
    if (rj && cell) cell.classList.toggle('on', rj.classList.contains('on'));
  }

  // ---------- 본문 이미지 숨기기 (눌러서 불러오기) — 셀룰러 데이터 절약 ----------
  // 설정이 켜져 있으면 앱이 글 페이지의 디시 사진 요청(dcimg)을 막아 둠 (DeferredImages.swift).
  // 여기서는 막힌 사진의 주소를 옮겨 두고 자리에 '이미지 불러오기' 버튼을 둔다. 누르면 앱이 받아 data 주소로 돌려준다.
  // 디시 사진 서버 주소(dcimg)인 것만 대상이다. 디시 아이콘·경고 그림 등 다른 주소의 그림은 건드리지 않는다.
  // 스포일러 경고 칸(#spoiler) 안의 사진은 버튼 없이 바로 받아 보여 준다 (요청이 막혀 있어서 앱이 받아야 보인다).
  var deferSeq = 0;
  var deferMap = {};      // id -> img 요소
  var deferTimers = {};   // id -> 응답 기다림 시간 제한 (응답이 끝내 안 오면 버튼을 다시 누를 수 있게 푼다)
  var DEFER_WAIT_MS = 60000;
  // 움짤(<video class="dc_mv">)은 mp4를 source에 두므로 그 주소를 본다. 사진은 src·data-original 등을 본다
  function deferCandidate(el) {
    var vals;
    if (el.tagName === 'VIDEO') {
      vals = [el.getAttribute('src') || ''].concat(Array.prototype.map.call(el.querySelectorAll('source'), function (so) {
        return so.getAttribute('src') || '';
      }));
    } else {
      vals = ['src', 'data-original', 'data-src'].map(function (a) { return el.getAttribute(a) || ''; });
    }
    vals = vals.map(function (v) {
      v = v.trim();
      return v.indexOf('//') === 0 ? 'https:' + v : v;
    });
    return vals.filter(function (v) { return /^https?:\/\/dcimg/i.test(v); })[0] || '';
  }
  function deferButton(id, label) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dcapp-defer-btn';
    btn.setAttribute('data-dcapp-defer-id', id);
    btn.textContent = label || '이미지 불러오기';
    return btn;
  }
  function deferReset(b, label) {
    b.disabled = false;
    b.textContent = label || '이미지 불러오기';
  }
  function deferClearTimer(id) {
    if (deferTimers[id]) { clearTimeout(deferTimers[id]); delete deferTimers[id]; }
  }
  // 앱에 사진을 요청하고, 응답이 오지 않으면 시간이 지난 뒤 버튼을 다시 누를 수 있게 푼다
  function deferRequest(id, im) {
    deferClearTimer(id);
    deferTimers[id] = setTimeout(function () {
      delete deferTimers[id];
      deferredImage(id, null);
    }, DEFER_WAIT_MS);
    // 사진을 받을 때 쓰는 값: 글 주소(Referer)와 이 웹뷰의 브라우저 정보(User-Agent)
    post('deferimg', { id: id, src: im.getAttribute('data-dcapp-deferred-src') || '', page: location.href, ua: navigator.userAgent });
  }
  function deferPostImages() {
    if (!cfg.deferImages) return;
    document.querySelectorAll('.thum-txtin img, .thum-txtin video').forEach(function (im) {
      if (im.getAttribute('data-dcapp-defer-id') || !im.parentNode) return;
      if (im.closest && im.closest('#spoiler')) return;   // 스포일러 경고 칸 그림은 앱 카드로 바뀌어 숨김 — 대상 아님
      var s = deferCandidate(im);
      if (!s) return;   // 디시 사진·움짤 서버 주소가 아니면 그대로 둠
      var id = 'd' + (++deferSeq);
      var isVideo = im.tagName === 'VIDEO';
      im.setAttribute('data-dcapp-defer-id', id);
      im.setAttribute('data-dcapp-deferred-src', s);
      im.removeAttribute('src');
      if (isVideo) {
        Array.prototype.forEach.call(im.querySelectorAll('source'), function (so) { so.removeAttribute('src'); });
      } else {
        im.removeAttribute('data-original');
        im.removeAttribute('data-src');
      }
      deferMap[id] = im;
      im.classList.add('dcapp-defer-img');
      im.parentNode.insertBefore(deferButton(id, isVideo ? '움짤 불러오기' : '이미지 불러오기'), im.nextSibling);
    });
    syncDeferAll();
  }
  // 글 본문 맨 위 '한번에 불러오기' 버튼: 아직 숨겨진 사진이 있을 때만, 남은 장수 표시 (다 불러오면 사라짐)
  function syncDeferAll() {
    document.querySelectorAll('.thum-txtin').forEach(function (box) {
      var n = box.querySelectorAll('.dcapp-defer-img').length;
      var all = box.querySelector(':scope > .dcapp-defer-all');
      if (n === 0) {
        if (all) all.parentNode.removeChild(all);
        return;
      }
      if (!all) {
        all = document.createElement('button');
        all.type = 'button';
        all.className = 'dcapp-defer-all';
        box.insertBefore(all, box.firstChild);
      }
      var busy = !!box.querySelector('.dcapp-defer-btn:disabled');
      all.disabled = busy;
      all.textContent = busy ? '불러오는 중…' : '이미지 한번에 불러오기 (' + n + '장)';
    });
  }
  // 버튼 누름: 기본 동작(사진 보기 등)은 막고, 앱에 사진을 요청
  document.addEventListener('click', function (e) {
    var all = e.target && e.target.closest ? e.target.closest('.dcapp-defer-all') : null;
    if (all) {
      e.preventDefault();
      e.stopPropagation();
      all.parentNode.querySelectorAll('.dcapp-defer-btn').forEach(function (x) {
        if (!x.disabled) x.click();
      });
      syncDeferAll();
      return;
    }
    var b = e.target && e.target.closest ? e.target.closest('.dcapp-defer-btn') : null;
    if (!b) return;
    e.preventDefault();
    e.stopPropagation();
    var id = b.getAttribute('data-dcapp-defer-id');
    var im = deferMap[id];
    if (!im || b.disabled) return;
    b.disabled = true;
    b.textContent = '불러오는 중…';
    deferRequest(id, im);
    syncDeferAll();
  }, true);
  // 앱이 받은 결과: url이 있으면 사진을 넣고, 없으면(실패·시간 초과) 버튼을 다시 누를 수 있게 함
  // 불러온 사진에 디시 '댓글' 버튼(button.btn-imgcomment)이 없으면 디시 함수로 다시 만든다
  // (디시는 사진을 처음 볼 때 한 번만 버튼을 만들어서, 그때 숨겨져 있던 사진은 버튼이 빠짐)
  function ensureImgCommentButton(im) {
    var fno = im.getAttribute('data-fileno');
    var flag = im.getAttribute('data-comment');
    var wrap = im.closest ? im.closest('.imgwrap') : null;
    if (!fno || !/^\d+$/.test(fno) || flag !== '1' || !wrap || !wrap.parentNode) return;   // 댓글 기능이 없는 사진
    if (localStorage.getItem('show_img_comment') === 'hide') return;                         // 디시 설정: 사진 댓글 숨김
    if (document.getElementById('img_comment_open_btn' + fno)) return;
    if (document.getElementById('img_comment_div' + fno)) {
      // 패널은 이미 있고 버튼만 빠진 경우: 버튼만 붙이고 디시 함수로 열게 함
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'btn-imgcomment';
      b.id = 'img_comment_open_btn' + fno;
      b.textContent = '댓글';
      b.addEventListener('click', function (ev) {
        ev.preventDefault();
        if (typeof window.imgCommentOpen === 'function') window.imgCommentOpen(fno);
      });
      wrap.parentNode.insertBefore(b, wrap.nextSibling);
      return;
    }
    // 패널도 없으면 디시가 쓰는 방식 그대로 (패널과 버튼을 함께 만듦)
    if (typeof window.imgCommentLoad === 'function' && window.jQuery) {
      try { window.imgCommentLoad(window.jQuery(im), fno, flag); } catch (e) {}
    }
  }
  // 불러온 사진을 디시가 사진을 처음 볼 때와 같게 처리한다.
  // 디시는 사진이 로드된 뒤의 lazy 로딩 load 콜백(dccon_replace)에서 사진을 .imgwrap으로 감싸고 댓글 버튼·패널을 만든다.
  // 숨긴 사진은 원본 주소를 떼어 뒀으므로 그 콜백이 돌지 않는다 → 로드가 끝나면 같은 함수를 여기서 직접 부른다.
  function afterDeferredPhoto(im, url) {
    im.addEventListener('load', function onLoaded() {
      im.removeEventListener('load', onLoaded);
      if (im.closest && im.closest('.imgwrap')) {
        try { ensureImgCommentButton(im); } catch (e) {}
        return;
      }
      if (typeof window.dccon_replace === 'function' && window.jQuery) {
        try { window.dccon_replace(im); } catch (e) {}
      }
    });
    im.setAttribute('src', url);
  }
  // 불러온 움짤(동영상): 주소를 채워 넣고 다시 읽어 재생 (음소거·자동재생 속성은 디시 마크업 그대로)
  function restoreVideo(v, url) {
    var so = v.querySelector('source');
    (so || v).setAttribute('src', url);
    try { v.load(); } catch (e) {}
    try {
      var p = v.play();
      if (p && p.catch) p.catch(function () {});
    } catch (e) {}
  }
  function deferredImage(id, url) {
    var im = deferMap[id];
    var b = document.querySelector('.dcapp-defer-btn[data-dcapp-defer-id="' + id + '"]');
    deferClearTimer(id);
    if (!im) {
      if (b) deferReset(b, '불러오지 못했어요 · 다시 누르기');
      syncDeferAll();
      return false;
    }
    if (url) {
      im.classList.remove('dcapp-defer-img');
      if (b) b.parentNode.removeChild(b);
      if (im.tagName === 'VIDEO') restoreVideo(im, url);
      else afterDeferredPhoto(im, url);
    } else if (b) {
      deferReset(b, '불러오지 못했어요 · 다시 누르기');
    }
    syncDeferAll();
    return true;
  }

  // 이미지 댓글 머리글의 댓글 수: 디시는 '[N]'으로 적으므로 대괄호를 떼고 배지 모양으로 (디시가 다시 쓰면 다음 적용 때 또 뗌)
  function tidyImgCommentCount() {
    document.querySelectorAll('.img-comment .all-comment-tit .tit .ct').forEach(function (c) {
      var m = (c.textContent || '').match(/^\s*\[\s*(\d+)\s*\]\s*$/);
      if (m) c.textContent = m[1];
      c.classList.add('dcapp-ct');
    });
  }
  // 이미지 댓글 미리보기가 떠 있는 사진: 디시는 이때 '댓글' 버튼을 만들지 않으므로 사진 위 우하단에 버튼을 붙인다.
  // 누르면 디시 함수 imgCommentOpen이 미리보기를 접고 전체 댓글을 연다 (닫으면 디시가 버튼을 다시 보여 줌)
  function ensureImgOpenButtons() {
    if (cfg.hideImgComment) return;   // 사진 댓글 버튼 숨김 설정이면 만들지 않음
    document.querySelectorAll('div.img-comment[id^="img_comment_div"]').forEach(function (panel) {
      var fno = panel.id.slice('img_comment_div'.length);
      if (!/^\d+$/.test(fno) || document.getElementById('img_comment_open_btn' + fno)) return;
      if (!panel.querySelector('.all-comment.preview') || getComputedStyle(panel).display === 'none') return;   // 미리보기가 보일 때만
      var list = panel.querySelector('.all-comment.list');
      if (list && getComputedStyle(list).display !== 'none') return;   // 전체 목록이 열려 있으면 디시가 관리
      // 사진 칸(.imgwrap): 패널 바로 앞 (사이에 .num이 끼어 있을 수 있음)
      var wrap = null;
      for (var p = panel.previousElementSibling, i = 0; p && !wrap && i < 3; p = p.previousElementSibling, i++) {
        if (p.classList && p.classList.contains('imgwrap')) wrap = p;
      }
      if (!wrap) return;
      var media = wrap.querySelector('img, video');
      if (!media) return;
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'btn-imgcomment';
      b.id = 'img_comment_open_btn' + fno;
      b.setAttribute('onclick', 'imgCommentOpen(' + fno + ')');
      b.textContent = '댓글';
      media.insertAdjacentElement('afterend', b);   // 사진 안(우하단 겹침)에 — 디시 기본 위치
    });
  }
  // 사진 댓글 버튼 누르기: 댓글창이 열려 있으면 닫고, 닫혀 있으면 연다 (디시 함수 imgCommentClose / imgCommentOpen 사용)
  document.addEventListener('click', function (e) {
    var ob = e.target && e.target.closest ? e.target.closest('button.btn-imgcomment') : null;
    if (!ob || !/^img_comment_open_btn\d+$/.test(ob.id) || cfg.hideImgComment) return;
    e.preventDefault();
    e.stopPropagation();   // 디시 인라인 onclick(imgCommentOpen)은 따로 실행하지 않음
    var fno = ob.id.slice('img_comment_open_btn'.length);
    var panel = document.getElementById('img_comment_div' + fno);
    var list = panel ? panel.querySelector('.all-comment.list') : null;
    var opened = !!list && getComputedStyle(list).display !== 'none';
    if (opened) {
      if (typeof window.imgCommentClose === 'function') window.imgCommentClose(fno);
    } else if (typeof window.imgCommentOpen === 'function') {
      window.imgCommentOpen(fno);
    }
  }, true);
  function apply() {
    try { if (typeof watchIpPopup === 'function') watchIpPopup(); } catch (e) {}
    ensureStyle();
    try { tidyImgCommentCount(); } catch (e) {}
    try { ensureImgOpenButtons(); } catch (e) {}
    try { autoConfirmAnonModify(); } catch (e) {}
    // 테마 색을 쓰는 페이지는 첫 적용 때 색을 바로 입히고 나서 보여 줌 (그 전에 디시 파란색이 잠깐 비치던 것 방지). 이후 바뀜은 뒤에서 처리
    if (cfg.tint && !tintFirstDone) { tintFirstDone = true; try { tintPage(); } catch (e) {} }
    try { spoilerGuard(); } catch (e) {}
    try { buildArticleHead(); buildVote(); styleVoteIframes(); hideGallogListBtn(); } catch (e) {}
    try { homeRankTwoUp(); } catch (e) {}
    try { homeRankRemeasure(); } catch (e) {}
    try { fitCommentBox(document.getElementById('comment_memo')); } catch (e) {}
    try { buildCommentSort(); buildCommentInputBtn(); } catch (e) {}
    try { cacheListIds(); buildNextPrev(); } catch (e) {}
    try { adBlockCSS(); adFilterCSS(); hideListPromos(); } catch (e) {}
    try { listCommentCount(); } catch (e) {}
    try { markReadRows(); } catch (e) {}
    try { expandListNicks(); } catch (e) {}
    try { expandArticleNick(); } catch (e) {}
    try { markViewButtons(); } catch (e) {}
    try { listRowLayout(); } catch (e) {}
    try { applyListFilter(); } catch (e) {}
    try { pageSeparators(); } catch (e) {}
    try { pageStickyBar(); } catch (e) {}
    try { buildPager(); } catch (e) {}
    try { hideBelowPaging(); } catch (e) {}
    try { hideListTypeTabs(); } catch (e) {}
    try { buildHeadBar(); } catch (e) {}
    try { hideGallNickTip(); } catch (e) {}
    try { avoidFloatBar(); } catch (e) {}
    try { fillAnon(); } catch (e) {}
    if (cfg.tint) { try { tintPage(); } catch (e) {} requestAnimationFrame(function () { if (cfg.tint) { try { tintPage(); } catch (e) {} } }); }
    try { document.documentElement.classList.remove('dcapp-pending'); } catch (e) {}   // 앱 스타일·테마 색이 붙었으니 문서 시작 때 가린 본문을 보여 줌
    if (cfg.tint || tintKey) scheduleTint();
    try { sizeReplyBoxes(); } catch (e) {}
    try { markCommentFieldsReadonly(); } catch (e) {}
    try { hideDory(); } catch (e) {}
    try { skipPwChange(); } catch (e) {}
    var enabled = cfg.enabled !== false;
    var mode = cfg.mode || 'collapse';
    var dset = new Set(cfg.dccons || []);
    var dpset = new Set((cfg.dcconPkgs || []).map(String));
    findUnits().forEach(function (u) {
      var reason = null;
      if (enabled && u.el.getAttribute('data-dcapp-revealed') !== '1') reason = blockedReason(u, identity(u), dset, dpset);
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
    // 차단한 디시콘: '차단됨 표시'면 그 자리에 회색 안내 칸(누르면 원본 디시콘 표시), '완전히 숨김'이면 흔적 없이
    document.querySelectorAll('img, video').forEach(function (m) {
      var k = dcconKey(m);
      if (!k) return;
      var mp = m.getAttribute('data-dccon-package') || m.getAttribute('package_idx') || '';
      var revealed = m.getAttribute('data-dcapp-dccon-reveal') === '1';
      var off = enabled && !revealed && (dcconBlockedIn(m, dset) || (mp && dpset.has(String(mp))));
      m.classList.toggle('dcapp-dccon-off', off);
      var prev = m.previousElementSibling;
      var lab = prev && prev.classList.contains('dcapp-dccon-label') ? prev : null;
      var wantLabel = off && mode !== 'remove';
      if (wantLabel && !lab && m.parentNode) {
        lab = document.createElement('span');
        lab.className = 'dcapp-dccon-label';
        lab.textContent = '차단한 디시콘';
        lab.style.cursor = 'pointer';
        lab.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          m.setAttribute('data-dcapp-dccon-reveal', '1');
          m.classList.remove('dcapp-dccon-off');
          if (lab && lab.parentNode) lab.parentNode.removeChild(lab);
        });
        m.parentNode.insertBefore(lab, m);
      } else if (!wantLabel && lab) {
        lab.parentNode.removeChild(lab);
      }
    });
    try { applyImageBlocks(enabled); } catch (e) {}
    try { deferPostImages(); } catch (e) {}
    if (enabled && cfg.hideBest) hideBestNotice();
    try { homeRankOnly(); } catch (e) {}
    if (cfg.hideHeader !== false) hideSiteHeader();
    else document.querySelectorAll('.dcapp-header-hidden').forEach(function (el) { el.classList.remove('dcapp-hide', 'dcapp-header-hidden'); });
  }

  // ---------- 길게 누르기 → 차단 메뉴 ----------
  function describe(unitEl, target, allowImage) {
    var d = { kind: 'dccon', nick: '', userId: '', ip: '', snippet: '', dcconKey: '', dcconSrc: '', imgKey: '', imgSrc: '', imgIndex: -1, imgCount: 0, imgFilenos: [] };
    if (unitEl) {
      var u = { el: unitEl, kind: unitEl.getAttribute('data-dcapp-unit') };
      var idn = identity(u);
      d.kind = u.kind; d.nick = idn.nick; d.userId = idn.id; d.ip = idn.ip;
      // 본문 위 작성자 칸은 칸 전체 글자에 날짜·'스크랩 갤로그 가기'까지 섞임 → 글 제목만
      var tit = u.kind === 'article' ? unitEl.querySelector('.tit') : null;
      d.snippet = txt(tit || unitEl).slice(0, 80);
    }
    var m = mediaAt(target);
    var key = dcconKey(m);
    if (!key && unitEl && !(allowImage && imgEligible(m))) {
      var all = Array.prototype.filter.call(unitEl.querySelectorAll('img, video'), dcconKey);
      if (all.length === 1) { m = all[0]; key = dcconKey(m); }
    }
    if (key) { d.dcconKey = key; d.dcconSrc = mediaSrc(m); }
    else if (allowImage && imgEligible(m)) {
      var url = galleryMediaURL(m), ik = imgBlockKey(url);
      if (ik) {
        d.imgKey = ik; d.imgSrc = url;
        // 원본 저장: 가린 사진을 포함한 글 속 전체 사진에서 몇 번째인지 (PC 원본 첨부 목록과 짝짓는 데 씀)
        var photos = bodyPhotos(null);
        d.imgIndex = photos.indexOf(m);
        d.imgCount = photos.length;
        d.imgFilenos = photos.map(photoFileno);
      }
    }
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
  var lpHeld = false;
  function clearLP() { if (lp) { clearTimeout(lp.timer); lp = null; } }

  document.addEventListener('touchstart', function (e) {
    if (pick.on || blockPick || e.touches.length !== 1) return;
    var target = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!target || !target.closest) return;
    if (target.closest('input, textarea, select, [contenteditable="true"], [contenteditable=""]')) return;   // 입력 중인 칸은 그대로
    var unitEl = target.closest('[data-dcapp-unit]');
    var media = mediaAt(target);
    var bodyImg = imgEligible(media);     // 본문 사진·움짤: 길게 누르면 이미지 차단 메뉴
    if (!unitEl && !dcconKey(media) && !bodyImg) return;
    if (unitEl && unitEl.classList.contains('dcapp-collapsed')) return;
    // 댓글 글자를 길게 누르면 → 앱이 댓글 내용만 따로 띄움 (선택·복사하기 쉽게, 드래그하다 차단 메뉴가 뜨지 않게)
    var cmtBox = (unitEl && unitEl.getAttribute('data-dcapp-unit') === 'comment' && !dcconKey(media)) ? target.closest('.txt, .usertxt') : null;
    if (cmtBox && unitEl.contains(cmtBox) && !target.closest('a[href]')) {
      var ct = e.touches[0];
      clearLP();
      lp = {
        x: ct.clientX, y: ct.clientY,
        timer: setTimeout(function () {
          lp = null;
          suppressClickUntil = Date.now() + 800;
          var nickEl0 = nickElement({ el: unitEl, kind: 'comment' });
          post('cmttext', { nick: nickEl0 ? txt(nickEl0).replace(IP_RE, '').trim() : '', text: (cmtBox.innerText || cmtBox.textContent || '').trim(), x: ct.clientX, y: ct.clientY });
          [60, 300, 700].forEach(function (ms) { setTimeout(clearSelection, ms); });   // 길게 누르면 iOS가 글자를 선택해 버림 → 풀기
        }, 450)
      };
      return;
    }
    // 차단·메모 메뉴는 닉네임(또는 그 옆 메모 칸)을 길게 누를 때만 — 본문·댓글 글자는 평소처럼 길게 눌러 복사
    if (!dcconKey(media) && !bodyImg) {
      var nk = unitEl ? nickElement({ el: unitEl, kind: unitEl.getAttribute('data-dcapp-unit') }) : null;
      var onNick = (nk && (nk === target || nk.contains(target))) || !!target.closest('.dcapp-memo') || !!nickArea(target);
      // 글 목록 행(post)은 닉네임뿐 아니라 그 글 행 어디를 꾹 눌러도 (버튼 등 특수 요소는 제외). 본문(article)·댓글은 기존대로 닉네임만
      var onListRow = !!unitEl && unitEl.getAttribute('data-dcapp-unit') === 'post' && !target.closest('button, input, textarea, select');
      if (!onNick && !onListRow) return;
    }
    var t = e.touches[0];
    clearLP();
    lp = {
      x: t.clientX, y: t.clientY,
      timer: setTimeout(function () {
        lp = null;
        suppressClickUntil = Date.now() + 800;
        lpHeld = true;      // 손을 뗄 때(touchend) 한 번 더 막음 — 오래 누르고 있다 떼도 글로 이동하지 않게
        post('longpress', describe(unitEl, target, true));
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
  function endTouch() {
    if (lpHeld) { lpHeld = false; suppressClickUntil = Date.now() + 700; }
    clearLP();
  }
  document.addEventListener('touchend', endTouch, { capture: true, passive: true });
  document.addEventListener('touchcancel', endTouch, { capture: true, passive: true });

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
    post('longpress', describe(unitEl, t, false));
  }, true);

  // 글 목록 행을 길게 눌러 메뉴가 뜬 직후 손을 뗄 때 생기는 click은 글 링크로 이동하지 않게 (짧게 한 번 탭하는 건 평소처럼 글로 이동)
  window.addEventListener('click', function (e) {
    if (Date.now() >= suppressClickUntil) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (!t || !t.closest || !t.closest('[data-dcapp-unit="post"]')) return;
    e.preventDefault(); e.stopPropagation();
    if (e.stopImmediatePropagation) e.stopImmediatePropagation();
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
      var media = mediaAt(target);
      if (unitEl || dcconKey(media)) post('longpress', describe(unitEl, target, false));
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
    // 차단해서 가려진 사진을 짧게 누르면 가림만 풀어 보여 줌 (풀린 뒤 다시 누르면 평소처럼 사진 보기)
    var hiddenBlk = target && target.closest ? target.closest('.dcapp-imgblk[data-dcapp-blocked="1"]') : null;
    if (hiddenBlk && hiddenBlk.getAttribute('data-dcapp-img-revealed') !== '1') {
      e.preventDefault(); e.stopPropagation();
      hiddenBlk.setAttribute('data-dcapp-img-revealed', '1');
      return;
    }
    // 스포일러 경고 칸(그 안의 '스포일러 주의' 사진 포함)을 누르면 → 사진 보기가 아니라 경고 칸을 치우고 본문 흐림을 풂 (칸 안의 '설정' 링크는 그대로 동작)
    var spo = target && target.closest ? target.closest('#spoiler') : null;
    if (spo && spo === spoilerBox()) {
      var spoLink = target.closest('a[href]');
      if (!(spoLink && spo.contains(spoLink))) {
        e.preventDefault(); e.stopPropagation();
        revealSpoiler();
        return;
      }
    }
    // (닉네임 탭은 디시 원래 동작(답글 등) 그대로 — 앱 차단·메모 메뉴는 길게 누르기로만)
    // 글 속 사진 탭 → 앱 사진 보기 (아래로 쓸어 닫기 / 확대 / 넘기기)
    // (움짤은 사진 자리에 <video class="dc_mv">가 들어와서 디시 웹 확대창이 뜸 → 같이 앱 사진 보기로)
    var tapped = target && target.closest ? target.closest('img, video.dc_mv') : null;
    var abody = tapped ? articleBody() : null;
    if (abody && abody.contains(tapped) && !dcconKey(tapped)) {
      // 보여 줄 목록: 차단해서 가린 사진은 뺌 (눌러서 보여 준 사진은 포함). 스포일러 경고 칸 사진은 빠짐
      var full = bodyPhotos(null);
      var shots = bodyPhotos(tapped).filter(function (x) { return !imgHidden(x); });
      var at = shots.indexOf(tapped);
      if (at >= 0) {
        e.preventDefault(); e.stopPropagation();
        // slots: 보여 줄 사진이 글 속 전체 목록의 몇 번째인지 / allCount·allFilenos: 가린 사진까지 포함한 전체 (PC 원본 첨부 목록과 짝짓는 기준)
        post('images', { urls: shots.map(galleryMediaURL), index: at,
          keys: shots.map(function (x) { return imgBlockKey(galleryMediaURL(x)); }),
          slots: shots.map(function (x) { return full.indexOf(x); }),
          allCount: full.length,
          allFilenos: full.map(photoFileno) });
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
    // 댓글 수정 칸(디시 ⋯ 메뉴 → 수정)은 디시 수정 창 그대로 씀: 앱 댓글 입력창으로 가로채거나 읽기 전용으로 두지 않음
    if (el.classList.contains('comment-edit-caption') || (el.closest && el.closest('.comment-edit'))) return false;
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
    if (cfg.dockComment === false || nativeCmtOn()) return;
    var f = commentFieldNear(e.target), tapped = e.target;
    // 포커스가 잡히는 순간 레이아웃을 바꾸면 iOS가 키보드를 안 띄워서, 키보드가 올라온 뒤에 붙임
    if (f) setTimeout(function () { if (document.activeElement === tapped) dockOn(f); }, 150);
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
  // 터치 시작 때 바로 풀면 누르는 도중에 레이아웃이 바뀌어 탭(답글 열기 등)이 씹힘 → 클릭이 끝난 뒤에 풀기
  document.addEventListener('click', function (e) {
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    if (dock.el && !(t && dock.el.contains(t))) {
      var a = document.activeElement;
      if (a && dock.el.contains(a) && a.blur) a.blur();
      undock();
    }
  }, true);
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
    // 댓글 헤더의 새로고침(sp-reload)은 숨겨 둬도 눌러지도록 먼저 찾음
    // 이미지 댓글(글 안 사진 밑 '댓글') 머리글에도 sp-reload가 있어서, 본댓글 상자 안 것만 고름 (이미지 댓글 새로고침을 누르면 이미지 댓글 양식이 열려 버림)
    var hiddenReload = document.querySelector('#comment_box .all-comment-tit .sp-reload');
    if (hiddenReload) return hiddenReload;
    var cands = document.querySelectorAll('[class*="refresh"], [class*="reload"], [onclick*="omment"], [href*="omment"]');
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      if (!visible(c)) continue;
      if (c.closest('[id^="img_comment_div"], [id^="img_comment_write_div"]')) continue;    // 이미지 댓글 쪽은 제외
      var label = (clsOf(c) + ' ' + (c.id || '') + ' ' + (c.getAttribute('onclick') || '') + ' ' + (c.getAttribute('href') || '')).toLowerCase();
      var inComment = !!c.closest('[class*="comment"], [id*="comment"]');
      if (/refresh|reload/.test(label) && (inComment || /comment|cmt/.test(label))) return c;
    }
    return null;
  }
  // ---------- 유동 글 수정: 디시 비밀번호 확인 페이지를 보여 주지 않고 앱에 저장한 유동 비밀번호로 바로 확인 ----------
  // 저장된 비밀번호가 있으면 칸에 넣고 디시 확인 함수(boardconfirm_pw)를 바로 부름 → 맞으면 디시가 수정 화면으로 보냄.
  // 디시가 틀렸다고 알리면(alert) 확인 페이지를 그대로 보여 줌. 저장된 비밀번호가 없으면 기존처럼 확인 페이지
  function autoConfirmAnonModify() {
    if (!/(^|\/)confirmpw\//.test(location.pathname)) return;
    var root = document.documentElement;
    if (root.getAttribute('data-dcapp-autopw') === '1') return;          // 한 번만 시도
    var mode = document.getElementById('mode'), pw = document.getElementById('board_pw'), route = document.getElementById('route_id');
    if (!mode || !pw || mode.value !== 'modify' || typeof window.boardconfirm_pw !== 'function') return;
    if (loginState() === 'in') return;                                   // 로그인한 글은 디시 원래 흐름
    var gid = route ? String(route.value || '') : '';
    var ag = (cfg.anonG || {})[gid];
    var saved = (ag && ag.pw) || (cfg.anon || {}).pw;
    if (!saved) return;
    root.setAttribute('data-dcapp-autopw', '1');
    root.classList.add('dcapp-pwauto');                                  // 확인 페이지는 잠깐 가림
    setVal(pw, saved);
    var origAlert = window.alert, shown = false;
    function showPage() {
      if (shown) return;
      shown = true;
      root.classList.remove('dcapp-pwauto');
      window.alert = origAlert;
    }
    window.alert = function (msg) { showPage(); return origAlert.call(window, msg); };   // 틀렸다는 안내면 확인 페이지를 보여 줌
    setTimeout(showPage, 12000);
    try { window.boardconfirm_pw(); } catch (e) { showPage(); }
  }
  // ---------- 글 수정·삭제 비밀번호 확인이 429(Too Many Attempts)로 막히면 → 잠시 뒤 확인 버튼을 자동으로 다시 누름 ----------
  // 디시 페이지는 이 오류를 처리하지 않아 화면이 그대로 멈춘 것처럼 보임
  var pwRetry = { n: 0, t: null, url: '' };
  window.addEventListener('dcapp-pw429', function () {
    var f = document.getElementById('board_pw_form'), pw = document.getElementById('board_pw');
    if (!f || !pw || !pw.value) return;
    if (pwRetry.url !== location.href) { pwRetry.url = location.href; pwRetry.n = 0; }
    if (pwRetry.t) return;                                   // 이미 다음 시도를 예약함 (연달아 온 429)
    if (pwRetry.n >= 300) { post('pw429end', {}); pwRetry.n = 0; return; }
    if (pwRetry.n % 10 === 0) post('pw429', { n: pwRetry.n });      // 10번마다 진행 상황 알림
    pwRetry.n++;
    pwRetry.t = setTimeout(function () {
      pwRetry.t = null;
      var b = document.body.contains(f) ? f.querySelector('button[type="submit"]') : null;
      if (b) b.click();
    }, 200);
  });
  // ---------- 댓글 등록이 429로 막히면 → 등록될 때까지 '댓글 새로고침 → 등록 버튼 다시 누르기' 반복 ----------
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
    var wasOn = cmtRetry.on;
    cmtRetry.on = false; cmtRetry.tries = 0; cmtRetry.refreshed = false; cmtRetry.waitingList = false; cmtRetry.tsWaitAt = 0;
    clearTimeout(cmtRetry.timer); clearTimeout(cmtRetry.watchdog);
    cmtRetry.timer = cmtRetry.watchdog = null;
    document.documentElement.classList.remove('dcapp-cmtretry');
    cmtRetry.askedCheck = false;
    hideAllCheck();                                       // 체크로 드러난 칸도 다시 숨김
    if (wasOn) post('cmtretry', { state: 'stop' });     // 앱의 '댓글을 다는 중' 말풍선을 내리게
  }
  // 다음 누르기 예약 (한 줄로만 — 디시가 연달아 보낸 429가 와도 겹치지 않게)
  function scheduleCmtRetry() {
    if (!cmtRetry.on || cmtRetry.timer || cmtRetry.waitingList) return;
    cmtRetry.timer = setTimeout(function () { cmtRetry.timer = null; retryCommentOnce(); }, 100);
  }
  // 댓글이 등록됐는데 목록에 안 나타나는 경우(가끔 디시가 새로 불러온 목록에 빠져 있음) → 앱이 글을 다시 불러오게
  // 디시가 코드(캡차)를 요구하면 → 앱 댓글 입력창에 코드 칸과 그림을 띄움 (로그인했어도 링크가 든 댓글 등은 코드를 요구함)
  window.addEventListener('dcapp-cmtwrite', function (ev) {
    var d = ev.detail || {};
    if (d.status !== 200) return;
    if (new URLSearchParams(d.body || '').get('mode') === 'com_modify') return;     // 댓글 수정 저장은 디시 수정 창이 처리 (앱 입력창은 안 띄움)
    var j = null;
    try { j = JSON.parse(d.text || '{}'); } catch (e) { return; }
    if (!j || j.result !== false) return;
    var cause = String(j.cause || '');
    var captcha = cause === 'captcha', wrong = !captcha && cause.indexOf('코드') >= 0;
    if (!captcha && !wrong) return;
    var ta = composeTarget;
    if (!ta) return;
    setTimeout(function () {      // 디시가 코드 칸을 그릴 때까지 잠깐 기다림
      composeInfo(ta).then(function (info) { post('cmtcaptcha', { img: info.codeImg || '', ph: info.codePh || '', wrong: wrong }); });
    }, 600);
  });
  window.addEventListener('dcapp-cmtwrite', function (ev) {
    var d = ev.detail || {};
    if (d.status !== 200) return;
    var ok = false;
    try { var j = JSON.parse(d.text || '{}'); ok = j.result !== false && j.result !== 0 && j.result !== '0'; } catch (e) { return; }
    if (!ok) return;
    try { setReplyHint(null); } catch (e) {}
    post('cmtok', {});     // 앱 댓글 입력창 닫기
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
    function findMine() {
      var mine = null;
      Array.prototype.some.call(document.querySelectorAll('li.comment, li.comment-add'), function (li) {
        if ((li.textContent || '').replace(/\s+/g, ' ').indexOf(key) >= 0) { mine = li; return true; }
        return false;
      });
      return mine;
    }
    function written(mine) {
      // 작성한 댓글 기록: 쓴 신분(닉네임·IP·아이디)은 목록에 나온 내 댓글에서 읽음
      var who = mine ? identity({ el: mine, kind: 'comment' }) : { nick: nickIn, ip: '', id: '' };
      post('cmtwritten', { memo: memo.slice(0, 80), nick: who.nick || nickIn, ip: who.ip || '', id: who.id || '', title: title });
    }
    // 느린 연결에서는 목록 반영이 늦을 수 있어 2.5초 뒤 한 번 더 확인 — 그래도 없을 때만 앱이 글을 다시 불러옴 (전체 새로고침 최소화)
    setTimeout(function () {
      if (location.href !== page) return;
      var mine = findMine();
      if (mine) return written(mine);
      setTimeout(function () {
        if (location.href !== page) return;
        var mine2 = findMine();
        written(mine2);
        if (!mine2) post('cmtmissing', {});
      }, 2500);
    }, 2500);
  });
  window.addEventListener('dcapp-cmtwrite', function (ev) {
    var d = ev.detail || {};
    hideAllCheck();      // 등록 요청에 응답이 왔으니 체크로 드러났던 답글 칸은 다시 숨김 (확인 토큰은 한 번만 쓰임)
    if (d.status === 429) {
      if (!cmtRetry.on) {
        var memo = '';
        try { memo = new URLSearchParams(d.body || '').get('comment_memo') || ''; } catch (e) {}
        if (!memo || !cmtRetry.form || !document.body.contains(cmtRetry.form)) return;   // 디시콘 등 → 안 함
        cmtRetry.on = true; cmtRetry.memo = memo; cmtRetry.tries = 0; cmtRetry.url = location.href;
        document.documentElement.classList.add('dcapp-cmtretry');
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
      if (typeof dcTs === 'undefined' || !dcTs) return false;
      if (typeof turnstile !== 'undefined' && dcTs.id !== null && turnstile.getResponse(dcTs.id)) return false;   // 이미 통과
      if (dcTs.state === 'interactive') return true;
      // 상태 이름이 달라도 체크박스가 화면에 실제로 떠 있으면(통과 상태가 아니면) 체크가 필요한 것으로 봄
      if (/^ok/.test(dcTs.state || '')) return false;
      var h = dcTs.host;
      if (h && h.isConnected) {
        var fr = h.querySelector ? h.querySelector('iframe') : null;
        var r = (fr || h).getBoundingClientRect();
        if (r.width > 20 && r.height > 20 && getComputedStyle(h).visibility !== 'hidden') return true;
      }
      return false;
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
      var nowC = Date.now();
      if (!cmtRetry.askedCheck) {
        cmtRetry.askedCheck = true; cmtRetry.checkAt = nowC; cmtRetry.revealAt = nowC;
        try { revealCheck(f); } catch (e) {}
        post('cmtretry', { state: 'check' });
      } else if (nowC - cmtRetry.checkAt < CHECK_LIMIT_MS && nowC - cmtRetry.revealAt >= 1000 && tsShown(tsHost()) === 'hidden') {
        // 체크박스가 가려졌거나 다른 칸으로 옮겨졌으면 다시 찾아 드러냄 (처음 체크를 요청한 뒤 90초 안에서만)
        cmtRetry.revealAt = nowC;
        try { revealCheck(f); } catch (e) {}
      }
      clearTimeout(cmtRetry.watchdog);
      cmtRetry.timer = setTimeout(function () { cmtRetry.timer = null; retryCommentOnce(); }, 100);
      return;
    }
    var resumed = cmtRetry.askedCheck;      // Cloudflare 체크를 기다리다 끝난 것 → 앱 말풍선을 다시 켬
    cmtRetry.askedCheck = false; cmtRetry.checkAt = 0; cmtRetry.revealAt = 0;
    if (resumed) post('cmtretry', { state: 'start' });
    // 다시 누르기 전에 댓글 목록을 먼저 새로 받고, 그 목록이 화면에 반영된 뒤 등록 (답글 양식은 목록 안에 있어 새로 받으면 사라지므로 그대로 누름)
    if (!cmtRetry.refreshed && !f.closest('.all-comment-lst, [id^="comment_addDiv"]')) {
      cmtRetry.refreshed = true;
      var how = 'none';
      try { how = refreshComments(); } catch (e) {}
      clearTimeout(cmtRetry.watchdog);
      if (how === 'none') {      // 다시 받을 방법이 없으면 짧게 쉬고 바로 다음 누르기
        cmtRetry.timer = setTimeout(function () { cmtRetry.timer = null; retryCommentOnce(); }, 800);
        return;
      }
      // 목록이 다시 받아져 화면에 반영되면(또는 최대 3.5초 뒤) 다음 누르기 — 고정 0.8초보다 느린 연결에서도 안전
      cmtRetry.waitingList = true;
      waitCmtList(3500).then(function () {
        cmtRetry.waitingList = false;
        if (cmtRetry.on && !cmtRetry.timer) retryCommentOnce();
      });
      return;
    }
    cmtRetry.refreshed = false;
    // 보안 확인이 아직 돌고 있으면(토큰 없음) 끝날 때까지 기다렸다가 누름 — 빈 토큰으로 보내면 디시가 '진행 중' 거절하고 위젯을 처음부터 다시 돌림
    if (tsIsPendingNoToken()) {
      if (!cmtRetry.tsWaitAt) cmtRetry.tsWaitAt = Date.now();
      if (Date.now() - cmtRetry.tsWaitAt < 50000) {
        clearTimeout(cmtRetry.watchdog);
        cmtRetry.timer = setTimeout(function () { cmtRetry.timer = null; retryCommentOnce(); }, 300);
        return;
      }
    }
    cmtRetry.tsWaitAt = 0;
    var btn = f.querySelector('button.btn-comment-write, button[type="submit"], input[type="submit"]');
    cmtRetry.tries++;
    if (btn) btn.click();
    else if (f.requestSubmit) f.requestSubmit();
    else { stopCmtRetry(); return; }
    // 디시가 Cloudflare 체크를 기다리다 보내지 않는 등 응답이 안 오면 → 25초 뒤 다시 누름
    clearTimeout(cmtRetry.watchdog);
    cmtRetry.watchdog = setTimeout(scheduleCmtRetry, 25000);
  }

  // ---------- 등록을 막는 안내 창(#ip_not_popup: 차단된 IP·매니저 차단 등) → 앱으로 문구를 넘김 ----------
  function checkIpPopup() {
    var pop = document.getElementById('ip_not_popup');
    if (!pop) return;
    var d = pop.style.display;
    if (!d || d === 'none') return;           // 디시가 .show()로 띄운 순간만
    var msg = Array.prototype.map.call(pop.querySelectorAll('.txt'), function (e) { return (e.innerText || '').trim(); })
      .filter(Boolean).join(' ').replace(/IP 오류 신고/g, '').replace(/\s+/g, ' ').trim();
    pop.style.display = 'none';
    post('banned', { msg: msg });
  }
  // 0.15초마다 확인하던 것을 없애고, 안내 창이 있는 페이지에서 그 칸의 style이 바뀔 때만 반응 (배터리: 평소엔 아무것도 돌지 않음)
  var ipPopWatched = null;
  function watchIpPopup() {
    var pop = document.getElementById('ip_not_popup');
    if (!pop || pop === ipPopWatched) return;
    ipPopWatched = pop;
    new MutationObserver(function () { try { checkIpPopup(); } catch (e) {} }).observe(pop, { attributes: true, attributeFilter: ['style', 'class'] });
    try { checkIpPopup(); } catch (e) {}
  }
  watchIpPopup();

  // ---------- 앱 댓글 입력창: 댓글 칸을 누르면 웹 키보드 대신 앱 입력창을 띄움 ----------
  // 등록은 앱이 디시 댓글 양식에 채워서 디시 페이지가 처리 (Cloudflare 체크·429 재시도도 그대로)
  var composeTarget = null;
  function nativeCmtOn() { return cfg.nativeComment !== false && !/\/write/.test(location.pathname); }
  function replyNickOf(ta) {
    var box = ta.closest ? ta.closest('[id^="comment_addDiv"]') : null;
    if (!box) return '';
    var ch = String(box.id).replace('comment_addDiv', '');
    var li = document.querySelector('li[ch="' + ch + '"]');
    var n = li ? li.querySelector('.nick') : null;
    return n ? (n.textContent || '').replace(/\s+/g, ' ').trim() : '';
  }
  function replyChOf(ta) {
    var box = ta.closest ? ta.closest('[id^="comment_addDiv"]') : null;
    return box ? String(box.id).replace('comment_addDiv', '') : '';
  }
  async function composeInfo(ta) {
    var form = ta.closest('form');
    // 대댓글 칸은 디시가 입력칸 이름 뒤에 _reple을 붙임 (comment_nick_reple 등)
    function f(n) { return form ? (form.querySelector('input[name="' + n + '"]') || form.querySelector('input[name="' + n + '_reple"]')) : null; }
    var nick = f('comment_nick'), pw = f('comment_pw'), code = f('captcha_codeC');
    var codeOn = !!(code && code.getBoundingClientRect().height > 0), img = null;
    if (codeOn) {
      var im = form.querySelector('.code img');
      if (im && im.src) {
        try {
          var blob = await (await fetch(im.src, { credentials: 'include' })).blob();
          img = await new Promise(function (res) { var r = new FileReader(); r.onload = function () { res(r.result); }; r.readAsDataURL(blob); });
        } catch (e) {}
      }
    }
    return {
      reply: ta.id !== 'comment_memo', replyNick: replyNickOf(ta), ch: replyChOf(ta), text: ta.value || '',
      anon: !!(nick || pw), nick: nick ? nick.value : '', pw: pw ? pw.value : '',
      nickLocked: !!(nick && (nick.disabled || nick.readOnly)), code: codeOn, codeImg: img, codePh: code ? (code.getAttribute('placeholder') || '') : ''
    };
  }
  function composeFor(ta) {
    // 체크박스를 눌러야 하는 동안에는 입력창을 열지 않음 (입력창이 체크박스를 가림). 대신 안내만 다시 띄움
    if (tsCheckActive()) { post('cmtcheckhint', {}); return; }      // 안내만 (쓰던 입력창은 건드리지 않음)
    composeTarget = ta;
    composeInfo(ta).then(function (info) { if (composeTarget === ta) post('cmtcompose', info); });
  }
  // 댓글 칸은 읽기 전용으로 두어 눌러도 웹 키보드가 안 뜨게 (앱 입력창이 대신 뜸)
  // 듀오 옆 세로 줄(시계·배터리) 폭을 설정값이 아니라 화면에서 직접 잼 — 접기/펴기·회전으로 바뀌어도 맞게 (안전 영역 값 env로 읽음)
  function sideColumnNow() {
    try {
      var probe = document.getElementById('dcapp-sideprobe');
      if (!probe) {
        probe = document.createElement('div');
        probe.id = 'dcapp-sideprobe';
        probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;padding-left:env(safe-area-inset-left);padding-right:env(safe-area-inset-right)';
        (document.body || document.documentElement).appendChild(probe);
      }
      var cs = getComputedStyle(probe);
      return Math.max(parseFloat(cs.paddingLeft) || 0, parseFloat(cs.paddingRight) || 0) >= 40;
    } catch (e) { return false; }
  }
  window.addEventListener('resize', function () { try { markCommentFieldsReadonly(); } catch (e) {} });
  window.addEventListener('orientationchange', function () { setTimeout(function () { try { markCommentFieldsReadonly(); } catch (e) {} }, 300); });
  function markCommentFieldsReadonly() {
    var on = nativeCmtOn();
    var root = document.documentElement;
    if (root.classList.contains('dcapp-nc') !== on) root.classList.toggle('dcapp-nc', on);
    var pin = on && cfg.pinComment === true;
    if (root.classList.contains('dcapp-pin') !== pin) root.classList.toggle('dcapp-pin', pin);
    // 여백 설정은 앱이 이 화면의 자리(분할이면 왼쪽·오른쪽 중 어느 쪽 끝에 닿는지)에 맞춰 보내 줌 (setDuo). 보내온 값이 없을 때만 화면 probe
    var dc = cfg.duoOff === true ? false : (typeof cfg.duoCol === 'boolean' ? cfg.duoCol : sideColumnNow());
    if (root.classList.contains('dcapp-duocol') !== dc) root.classList.toggle('dcapp-duocol', dc);
    var fl = dc && cfg.duoFlip === true;
    if (root.classList.contains('dcapp-duoflip') !== fl) root.classList.toggle('dcapp-duoflip', fl);
    // 돌린 방향의 옆 줄이 화면 오른쪽 끝에도 닿을 때만 오른쪽 쪽 여백(뒤집힌 쪽)을 붙임 (분할 왼쪽 목록은 제외)
    var flr = fl && (typeof cfg.duoFlipR === 'boolean' ? cfg.duoFlipR : true);
    if (root.classList.contains('dcapp-duoflip-r') !== flr) root.classList.toggle('dcapp-duoflip-r', flr);
    Array.prototype.forEach.call(document.querySelectorAll('textarea'), function (t) {
      if (on && isCommentField(t)) {
        if (!t.hasAttribute('readonly')) { t.setAttribute('readonly', ''); t.setAttribute('data-dcapp-ro', '1'); }
      } else if (t.getAttribute('data-dcapp-ro') === '1') {
        t.removeAttribute('readonly'); t.removeAttribute('data-dcapp-ro');
      }
    });
  }
  document.addEventListener('focusin', function (e) {
    var t = e.target;
    if (!nativeCmtOn() || !t || t.tagName !== 'TEXTAREA' || !isCommentField(t)) return;
    try { t.blur(); } catch (x) {}
    // 아래 고정 댓글칸이 쓰던 대댓글 내용을 보여 주는 중이면: 대댓글이 아니라 일반 댓글로 이어 쓰게 함 (내용은 그대로 두고 숨겨진 답글 칸의 글은 비움)
    if (replyMirror && t.id === 'comment_memo') {
      var m = replyMirror;
      replyMirror = null;
      t.removeAttribute('data-dcapp-mirror');
      try {
        var li = m.ch ? document.querySelector('li[ch="' + m.ch + '"]') : null;
        var ra = li ? openedReplyArea(li) : null;
        if (ra) { ra.value = ''; ra.dispatchEvent(new Event('input', { bubbles: true })); }
      } catch (e2) {}
    }
    composeFor(t);
  }, true);
  // 페이지가 다시 불려와(다른 앱 갔다 온 뒤 등) 댓글 칸이 새로 생겼으면, 앱 입력창이 쓰던 칸을 다시 찾아 이어 붙임 (그냥 댓글만. 대댓글 칸은 눌러야 생겨서 못 찾음)
  function ensureTarget(p) {
    var ta = composeTarget;
    if (ta && document.body.contains(ta)) return ta;
    if (p && p.reply === false) {
      var n = document.getElementById('comment_memo');
      if (n) { composeTarget = n; return n; }
    }
    return null;
  }
  // 대댓글은 페이지가 다시 불려오면 답글 칸이 없으므로, 그 댓글을 눌러 디시가 답글 칸을 다시 열게 한 뒤 연결
  async function ensureReplyTarget(p) {
    var cur = composeTarget;
    if (cur && document.body.contains(cur)) return true;
    if (!p || p.reply === false) return !!ensureTarget(p);
    if (!p.ch) return false;
    var li = document.querySelector('li[ch="' + p.ch + '"]');
    if (!li) return false;
    var area = openedReplyArea(li);
    if (!area) {
      try { (li.querySelector('.usertxt, .txt, p') || li).click(); } catch (e) {}
      for (var i = 0; i < 20 && !(area = openedReplyArea(li)); i++) await sleep(100);
    }
    if (!area) return false;
    composeTarget = area;
    return true;
  }
  // 앱 입력창의 내용을 디시 댓글 양식에 채움
  function composeFill(p) {
    var ta = ensureTarget(p);
    if (!ta) return null;
    var form = ta.closest('form');
    function setv(el, v) {
      if (!el || v == null) return;
      el.setAttribute('data-dcapp-user', '1');     // 앱 입력창 값 → 자동 채우기가 덮어쓰지 않게
      el.value = v;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }
    if (form) {
      function fi(n) { return form.querySelector('input[name="' + n + '"]') || form.querySelector('input[name="' + n + '_reple"]'); }
      setv(fi('comment_nick'), p.nick);
      setv(fi('comment_pw'), p.pw);
      setv(fi('captcha_codeC'), p.code);
    }
    try { ta.removeAttribute('maxlength'); } catch (e) {}      // 글자 수 제한은 앱이 걸지 않음
    setv(ta, p.text);
    return form;
  }
  // 대댓글을 쓰다 닫으면 글은 숨겨진 답글 칸에 들어가 아래 고정 댓글칸이 비어 보임 → 그 칸에 쓰던 내용을 그대로 보여 줌 (그 칸을 누르면 대댓글이 아니라 일반 댓글로 이어 씀)
  var replyMirror = null;
  function setReplyHint(p) {
    var memo = document.getElementById('comment_memo');
    if (!memo) return;
    if (p && p.reply && String(p.text || '').trim()) {
      if (!replyMirror && memo.value) return;              // 일반 댓글칸에 이미 글이 있으면 덮지 않음
      replyMirror = { ch: p.ch, replyNick: p.replyNick || '' };
      memo.value = p.text;
      memo.setAttribute('data-dcapp-mirror', '1');
    } else if (replyMirror || memo.getAttribute('data-dcapp-mirror')) {
      replyMirror = null;
      memo.removeAttribute('data-dcapp-mirror');
      memo.value = '';
    }
  }
  function composeSync(p) { var ok = !!composeFill(p); try { setReplyHint(p); } catch (e) {} return ok; }
  // Cloudflare 체크박스가 필요하면 체크박스가 실제로 화면에 보이게 드러냄 (기준: 디시 확인 위젯 dcTs.host)
  // 위젯은 디시가 마지막으로 누른 양식의 확인 칸으로 옮겨지므로, 제출하는 양식과 다른 칸(숨은 답글 칸 등)에 있을 수 있음
  // → 위젯이 숨은 칸이면 제출하는 양식의 칸으로 옮기고(토큰이 없을 때만), 답글 칸이면 칸을 드러내고(닉네임·입력칸·버튼 줄 숨김), 그 밖의 잘림·숨김은 조상 요소를 풀어서 해결
  var CHECK_LIMIT_MS = 90000, checkWatch = null, checkStartAt = 0;
  function tsHost() { return (window.dcTs && dcTs.host && dcTs.host.isConnected) ? dcTs.host : null; }
  /// 확인 칸(슬롯)에서 답글 칸 box까지 올라가며, 올라가는 줄의 형제(닉네임·입력칸·버튼 줄)를 .dcapp-tsx로 숨김 (댓글창 nc 모드에서만)
  function markCheckPath(box) {
    if (!document.documentElement.classList.contains('dcapp-nc')) return;
    var slot = box.querySelector('.dc-ts-slot, #dc-turnstile');
    if (!slot) return;
    var node = slot;
    while (node && node !== box) {
      var parent = node.parentElement;
      if (!parent) break;
      Array.prototype.forEach.call(parent.children, function (c) { if (c !== node) c.classList.add('dcapp-tsx'); });
      node = parent;
    }
  }
  function unmarkCheckPath(box) {
    box.removeAttribute('data-dcapp-show');
    box.querySelectorAll('.dcapp-tsx').forEach(function (el) { el.classList.remove('dcapp-tsx'); });
  }
  /// 보안 확인 토큰이 생겼는지 (통과했음)
  function tsHasToken() {
    try {
      if (typeof window.turnstile === 'undefined' || !window.dcTs || window.dcTs.id === null) return false;
      return !!window.turnstile.getResponse(window.dcTs.id);
    } catch (e) { return false; }
  }
  /// 체크박스가 지금 눌릴 수 있는지: 'ok' 보임 / 'off' 화면 밖(스크롤하면 보임) / 'hidden' 숨김·잘림·다른 것에 가려짐
  function tsShown(h) {
    if (!h || !h.isConnected) return 'hidden';
    var el = h.querySelector('iframe') || h;
    var r = el.getBoundingClientRect();
    if (r.width < 20 || r.height < 20 || getComputedStyle(el).visibility === 'hidden') return 'hidden';
    var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    if (cx < 0 || cy < 0 || cx > window.innerWidth || cy > window.innerHeight) return 'off';
    var top = document.elementFromPoint(cx, cy);
    return top && (top === el || h.contains(top)) ? 'ok' : 'hidden';
  }
  /// 체크박스를 가리거나 잘라 내는 조상(overflow 잘림, visibility 숨김)에 표시를 달아 CSS로 풀어 둠 (체크가 끝나면 hideAllCheck가 되돌림)
  function unclipAncestors(h) {
    var el = h.querySelector('iframe') || h;
    var r = el.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    for (var n = h.parentElement, k = 0; n && n !== document.body && k < 12; n = n.parentElement, k++) {
      var cs = getComputedStyle(n), a = n.getBoundingClientRect();
      var clips = cs.overflowY !== 'visible' && (cy < a.top || cy > a.bottom || cx < a.left || cx > a.right);
      if (clips || cs.visibility === 'hidden') n.setAttribute('data-dcapp-unclip', '1');
    }
  }
  /// 드러낸 답글 칸과 풀어 둔 조상을 모두 되돌림 (체크가 끝났거나, 댓글이 응답됐거나, 재시도를 멈췄을 때)
  function hideAllCheck() {
    document.querySelectorAll('[id^="comment_addDiv"][data-dcapp-show]').forEach(unmarkCheckPath);
    document.querySelectorAll('[data-dcapp-unclip]').forEach(function (n) { n.removeAttribute('data-dcapp-unclip'); });
  }
  /// 드러낸 칸을 지켜보다가 토큰이 나오거나 90초가 지나면 다시 숨김
  function ensureCheckWatch() {
    if (checkWatch) return;
    checkWatch = setInterval(function () {
      if (!document.querySelector('[data-dcapp-show], [data-dcapp-unclip]')) { clearInterval(checkWatch); checkWatch = null; return; }
      if (tsHasToken() || Date.now() - checkStartAt >= CHECK_LIMIT_MS) hideAllCheck();
    }, 300);
  }
  // 체크 상태: 위젯이 '클릭해 주세요'(interactive) 상태가 되고 토큰이 없으면 체크가 시작됨. 토큰이 생기거나 90초가 지나면 끝
  // 위젯이 다시 그려져 잠깐 대기(pending) 상태가 되어도 체크는 이어지는 것으로 봄 (입력창·가림막을 그 사이에 되돌리지 않게)
  var tsEp = { active: false, done: false, since: 0 }, tsCheckLast = false, checkSignalAt = 0;
  function tsInteractive() { return !!(window.dcTs && dcTs.state === 'interactive'); }
  function tsCheckActive() {
    if (tsHasToken()) return false;
    return tsEp.active || (!tsEp.done && tsInteractive());
  }
  /// 체크가 필요한 동안 로딩 가림막(.loading-box)을 숨김 (반투명 전체 화면이라 체크박스 위를 덮음). 상태가 바뀔 때만 앱에 알림
  function syncTsCheckClass() {
    if (tsHasToken()) { tsEp.active = false; tsEp.done = false; }
    else {
      if (!tsEp.active && !tsEp.done && tsInteractive()) { tsEp.active = true; tsEp.since = Date.now(); checkSignalAt = tsEp.since; }
      if (tsEp.active && Date.now() - tsEp.since >= CHECK_LIMIT_MS) { tsEp.active = false; tsEp.done = true; }
      if (tsEp.done && !tsInteractive()) tsEp.done = false;
    }
    var on = tsEp.active;
    document.documentElement.classList.toggle('dcapp-tscheck', on);
    if (on !== tsCheckLast) { tsCheckLast = on; post('tscheck', { on: on }); }
    tsAuxSync();
  }
  setInterval(syncTsCheckClass, 300);
  /// 보조 칸: 체크를 눌러야 하는데 위젯이 화면에서 눌릴 수 없는 자리(숨은 칸·가려짐)에 있으면, 화면 아래쪽 카드에 위젯을 다시 그림
  /// 체크 한 번에 한 번만 띄우고, 닫기 버튼으로 닫으면 그 체크 동안은 다시 띄우지 않음. 토큰이 생기거나 90초가 지나면 없앰
  var tsAux = { el: null, uses: 0, closed: false };
  function tsAuxSync() {
    if (!tsEp.active) { removeTsAux(); tsAux.closed = false; return; }
    if (tsAux.closed || tsAux.el) return;
    if (Date.now() - tsEp.since < 800) return;
    if (tsShown(tsHost()) === 'hidden') ensureTsAux();
  }
  function ensureTsAux() {
    var box = document.createElement('div');
    box.id = 'dcapp-tsaux';
    box.innerHTML = '<div class="dcapp-tsaux-tit">Cloudflare 확인</div>' +
      '<div class="dcapp-tsaux-sub">체크박스를 누르면 이어서 등록해요</div>' +
      '<div class="dc-ts-slot dcapp-tsaux-slot"></div>' +
      '<button type="button" class="dcapp-tsaux-x" aria-label="닫기">×</button>';
    (document.body || document.documentElement).appendChild(box);
    tsAux.el = box; tsAux.uses++;
    box.querySelector('.dcapp-tsaux-x').addEventListener('click', function () { tsAux.closed = true; removeTsAux(); });
    try { var rd = window.__dcappOrigTsRender || window.dcTsRender; if (typeof rd === 'function') rd(box.querySelector('.dc-ts-slot')); } catch (e) {}
  }
  function removeTsAux() {
    if (!tsAux.el) return;
    if (tsAux.el.parentNode) tsAux.el.parentNode.removeChild(tsAux.el);
    tsAux.el = null;
  }
  function tsAuxDiag() {
    var age = checkSignalAt ? Math.round((Date.now() - checkSignalAt) / 1000) : -1;
    return ' 체크중=' + (tsCheckActive() ? 'Y' : 'N') + ' 체크신호=' + (age < 0 ? '없음' : age + '초 전') +
      ' 보조칸=' + (tsAux.el ? '떠 있음' : (tsAux.closed ? '닫음' : '없음')) + '(' + tsAux.uses + '회)';
  }
  /// 체크박스를 드러냄. 반환 'check'는 앱이 '체크해 주세요' 안내를 띄울 때 쓰는 신호
  function revealCheck(form) {
    syncTsCheckClass();
    var h = tsHost();
    // 위젯이 숨은 칸(다른 답글 칸 등)에 있으면 제출하는 양식의 확인 칸으로 옮김 — 토큰이 아직 없을 때만, 화면에 보이는 칸은 옮기지 않음
    var moveTs = window.__dcappOrigTsUse || window.dcTsUse;     // 숨은 칸에서 꺼낼 때는 디시 원래 함수 (가드가 막지 않게)
    if (form && tsShown(h) === 'hidden' && !tsHasToken() && !(h && form.contains(h)) &&
        typeof moveTs === 'function' && form.querySelector('#dc-turnstile, .dc-ts-slot')) {
      try { moveTs.call(window, form); } catch (e) {}
      h = tsHost();
    }
    if (h) {
      if (!document.querySelector('[data-dcapp-show], [data-dcapp-unclip]')) checkStartAt = Date.now();
      var box = h.closest('[id^="comment_addDiv"]');
      if (box && !box.hasAttribute('data-dcapp-show')) { box.setAttribute('data-dcapp-show', '1'); markCheckPath(box); }
      // 화면 밖이면 먼저 화면 안으로 가져온 뒤에 가려짐을 판단 (스크롤 전에는 잘린 것이 안 보이는 경우가 있음)
      if (tsShown(h) === 'off') { try { h.scrollIntoView({ block: 'center' }); } catch (e) {} }
      if (tsShown(h) === 'hidden') unclipAncestors(h);
    } else if (form) {
      try { form.scrollIntoView({ block: 'center' }); } catch (e) {}
    }
    ensureCheckWatch();
    return 'check';
  }
  function tsDescOf(n) {
    return n.tagName.toLowerCase() + (n.id ? '#' + n.id : '') +
      (typeof n.className === 'string' && n.className.trim() ? '.' + n.className.trim().split(/\s+/)[0] : '');
  }
  /// 진단: 체크박스(확인 위젯) 위치 한 줄 — 어느 양식인지, 칸 좌표·크기, 가리는 조상, 화면에 보이는지, 로딩 가림막 상태
  function tsHostDiag() {
    try {
      var lb = document.querySelector('.loading-box');
      var lbs = lb ? getComputedStyle(lb).display + (document.documentElement.classList.contains('dcapp-tscheck') ? '/가림해제' : '') : '없음';
      var st = (window.dcTs && dcTs.state) || '-';
      var h = tsHost();
      if (!h) return 'cfhost: 칸 연결 없음 state=' + st + ' 로딩가림막=' + lbs + tsAuxDiag();
      var box = h.closest('[id^="comment_addDiv"]'), form = h.closest('form');
      var where = box ? box.id : (form ? (form.id || '양식') : '양식 밖');
      var r = h.getBoundingClientRect(), fr = h.querySelector('iframe'), ir = fr ? fr.getBoundingClientRect() : null;
      var hid = [];
      for (var n = h.parentElement, k = 0; n && n !== document.body && k < 20 && hid.length < 6; n = n.parentElement, k++) {
        var cs = getComputedStyle(n), why = [];
        if (cs.display === 'none') why.push('display:none');
        if (cs.visibility === 'hidden') why.push('visibility');
        if (cs.overflowY !== 'visible' && n.getBoundingClientRect().height < r.height) why.push('overflow');
        if (why.length) hid.push(tsDescOf(n) + '(' + why.join(',') + ')');
      }
      return 'cfhost: 위치=' + where + ' 상태=' + tsShown(h) +
        ' 칸=' + [r.left, r.top, r.width, r.height].map(Math.round).join(',') +
        ' iframe=' + (ir ? Math.round(ir.width) + 'x' + Math.round(ir.height) : '없음') +
        ' 가림=' + (hid.join(' < ') || '없음') +
        ' 드러냄=' + document.querySelectorAll('[data-dcapp-show]').length +
        ' 풀어둠=' + document.querySelectorAll('[data-dcapp-unclip]').length +
        ' 로딩가림막=' + lbs + ' state=' + st + tsAuxDiag();
    } catch (e) { return 'cfhost: 진단 실패 ' + e.message; }
  }
  // 코드 새로고침: 디시 댓글 양식의 새로고침 버튼을 눌러 새 그림을 받아 돌려줌
  async function cmtRefreshCode(p) {
    var ta = ensureTarget(p);
    if (!ta) return null;
    var form = ta.closest('form');
    if (!form) return null;
    var btn = form.querySelector('[id*="captcha_reload"], .code [class*="reload"], .code button, .code a, [class*="reload"]');
    if (!btn) return null;
    try { btn.click(); } catch (e) { return null; }
    await sleep(800);
    var info = await composeInfo(ta);
    return info.codeImg || null;
  }
  // ---------- 보안 확인(Turnstile)이 끝난 뒤에만 등록 ----------
  // 디시는 20초가 지나도 토큰이 없으면 빈 토큰으로 보내고, 서버는 '보안 확인 진행 중'으로 거절하며, 요청이 끝나면 위젯을 0%로 초기화함(dcTsReset)
  // → 등록 버튼은 토큰이 나온 뒤에 누르고, 진행 중인 확인은 초기화하지 않음
  // 반환: ready(토큰 있음) / check(사용자가 체크해야 함) / error(확인 실패) / timeout(maxMs 안에 토큰 없음) / none(이 페이지엔 확인 칸 없음)
  async function waitTurnstileReady(maxMs) {
    if (!document.getElementById('dc-turnstile')) return 'none';
    var t0 = Date.now(), lastLoad = 0;
    // 대기를 시작할 때 위젯이 오류·만료로 굳어 있으면 (느린 연결에서 Cloudflare가 실패로 끝낸 경우) 이 호출에 한해 한 번 다시 시작
    // 다시 시작한 뒤 대기 중에 또 오류가 나면 'error'로 돌려보냄 → 다음에 등록을 누르면 또 한 번 다시 시작해 봄 (무한 재시도 방지)
    try {
      if (typeof window.turnstile !== 'undefined' && window.dcTs && window.dcTs.id !== null && typeof window.dcTsReset === 'function') {
        var s0 = window.dcTs.state || '', k0 = '';
        try { k0 = window.turnstile.getResponse(window.dcTs.id) || ''; } catch (e) {}
        if (!k0 && (s0 === 'error' || s0 === 'expired')) { tsRestarts++; window.dcTsReset(); }
      }
    } catch (e) {}
    for (;;) {
      var api = typeof window.turnstile !== 'undefined' && !!window.dcTs && window.dcTs.id !== null;
      if (api) {
        var tok = '';
        try { tok = window.turnstile.getResponse(window.dcTs.id) || ''; } catch (e) {}
        if (tok) return 'ready';
        var st = window.dcTs.state || '';
        if (st === 'interactive') return 'check';     // 페이지가 직접 '체크해야 함'이라고 기록한 상태만 봄 (위젯 크기로 추측하면 확인 중에도 잘못 판단함)
        if (st === 'error') return 'error';
      } else if (typeof window.dcTsLoad === 'function' && Date.now() - lastLoad > 3000) {
        lastLoad = Date.now();                        // 스크립트가 아직 없으면 다시 불러 봄 (디시 dcTsWait과 같은 동작, 중복 방지 검사는 디시 쪽이 함)
        try { window.dcTsLoad(); } catch (e) {}
      }
      if (Date.now() - t0 >= maxMs) return 'timeout';
      await sleep(200);
    }
  }
  async function tsGate(form) {
    var r = await waitTurnstileReady(50000);
    if (r === 'ready' || r === 'none') return null;   // 바로 등록해도 됨
    if (r === 'check') return revealCheck(form);     // 체크박스를 띄워 사용자가 누르게 함
    return r === 'error' ? 'tserror' : 'tswait';     // 확인 실패 / 50초 안에 토큰 없음 → 빈 토큰으로 보내지 않고 알림
  }
  // 재시도 중 보안 확인이 아직 진행 중(토큰 없음)인지 — 체크가 필요한 상태와 확인 실패는 제외
  function tsIsPendingNoToken() {
    try {
      if (!document.getElementById('dc-turnstile')) return false;
      if (typeof window.turnstile === 'undefined' || !window.dcTs || window.dcTs.id === null) return true;
      if (window.dcTs.state === 'interactive' || window.dcTs.state === 'error') return false;
      return !window.turnstile.getResponse(window.dcTs.id);
    } catch (e) { return false; }
  }

  // 댓글 등록 버튼은 양식의 onsubmit(comment_write_ok)을 부름. 이 함수가 아직 없으면 양식이 그냥 제출돼 페이지가 넘어가므로 준비될 때까지 기다림
  async function waitCommentReady(ms) {
    for (var t = 0; t < ms; t += 200) {
      if (typeof window.comment_write_ok === 'function') return true;
      await sleep(200);
    }
    return typeof window.comment_write_ok === 'function';
  }
  // 댓글 목록(/ajax/response-comment)이 다시 받아져 화면에 반영될 때까지 기다림 (최대 ms, 그 뒤엔 그냥 진행)
  function waitCmtList(ms) {
    return new Promise(function (resolve) {
      var t = null;
      function fin() { clearTimeout(t); window.removeEventListener('dcapp-cmtlist', fin); resolve(); }
      t = setTimeout(fin, ms);
      window.addEventListener('dcapp-cmtlist', fin);
    });
  }
  async function cmtSubmit(p) {
    if (!(await waitCommentReady(5000))) return 'notready';
    var form = composeFill(p);
    if (!form) return 'gone';
    cmtRetry.form = form;
    var gate = await tsGate(form); if (gate) return gate;          // Cloudflare 체크박스가 떠 있으면 사용자가 체크한 뒤 디시 등록을 누르게
    var btn = form.querySelector('button.btn-comment-write, button[type="submit"]');
    if (btn) btn.click();
    else if (form.requestSubmit) form.requestSubmit();
    else return 'nobtn';
    return 'sent';
  }
  // 글자콘 댓글: 디시의 글자콘 창을 화면 밖에서 열어 두고, 앱 화면이 입력·색을 그 창에 넣어 줌
  function txtconInfo() {
    function colors(id) {
      return Array.prototype.map.call(document.querySelectorAll('#' + id + ' button[data-txtcon-color]'), function (b) {
        return { hex: b.getAttribute('data-txtcon-color'), on: b.classList.contains('on') };
      });
    }
    var recent = Array.prototype.map.call(document.querySelectorAll('#txtcon_recent li'), function (li) {
      return (li.textContent || '').trim();
    }).filter(Boolean);
    var ta = document.getElementById('txtcon_memo');
    return { bg: colors('txtcon_bg_list'), font: colors('txtcon_font_list'), recent: recent,
             max: ta ? (parseInt(ta.getAttribute('maxlength'), 10) || 20) : 20, text: ta ? ta.value : '' };
  }
  async function txtconOpen() {
    var ta = ensureTarget({ reply: composeTarget ? undefined : false });
    if (!ta || typeof window.show_txtcon !== 'function') return null;
    var fmT = ta.closest ? ta.closest('form') : null;      // 대댓글에 다는 답은 txtconMention (디시콘과 같은 이유)
    try { window.show_txtcon(ta.id === 'comment_memo' ? 'txtconWrite' : (fmT && fmT.id === 'comment_write_mention' ? 'txtconMention' : 'txtconReple')); } catch (e) { return null; }
    for (var i = 0; i < 20 && !document.getElementById('txtcon_memo'); i++) await sleep(100);
    return document.getElementById('txtcon_memo') ? txtconInfo() : null;
  }
  function txtconSetText(t) {
    var ta = document.getElementById('txtcon_memo');
    if (!ta) return '';
    ta.value = t;
    ['input', 'keyup'].forEach(function (n) { ta.dispatchEvent(new Event(n, { bubbles: true })); });
    return ta.value;
  }
  function txtconSetColor(kind, hex) {
    var b = document.querySelector('#txtcon_' + (kind === 'font' ? 'font' : 'bg') + '_list button[data-txtcon-color="' + hex + '"]');
    if (b) b.click();
    return !!b;
  }
  async function txtconSend(p) {
    if (!(await waitCommentReady(5000))) return 'notready';
    var form = composeFill(p);
    if (!form) return 'gone';
    cmtRetry.form = form;
    var gate = await tsGate(form); if (gate) return gate;
    if (typeof window.insertTxtcon !== 'function') return 'nofeature';
    try { window.insertTxtcon(); } catch (e) { return 'err:' + e.message; }
    return 'sent';
  }
  function txtconClose() {
    try { if (typeof window.showTxtcon === 'function') window.showTxtcon(false); } catch (e) {}
    return true;
  }
  // 디시콘 댓글: 닉네임·비밀번호·코드를 양식에 채운 뒤, 디시 페이지의 디시콘 등록 함수로 바로 등록 (글자는 건드리지 않음)
  async function composeDcconSend(p, pkg, detail) {
    if (!(await waitCommentReady(5000))) return 'notready';
    var form = composeFill(p);
    var ta = composeTarget;
    if (!form) return 'gone';
    cmtRetry.form = form;
    var gate = await tsGate(form); if (gate) return gate;
    if (typeof window.insertDccon !== 'function') return 'nofeature';
    try {
      // 대댓글에 다는 답(@멘션)은 디시가 별도 양식(comment_write_mention)과 모드(com_mention)를 씀 → 모드를 잘못 주면 대댓글 자기 번호로 답글이 가서 '삭제된 댓글'이라고 나옴
      var fm = ta.closest ? ta.closest('form') : null;
      window.dcconMode = ta.id === 'comment_memo' ? 'commentWrite' : (fm && fm.id === 'comment_write_mention' ? 'commentMention' : 'commentReple');
      window.insertDccon({ dcconPackage: String(pkg), dcconDetail: String(detail) });
    } catch (e) { return 'err:' + e.message; }
    return 'sent';
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
    if (nativeCmtOn() && ta.tagName === 'TEXTAREA' && isCommentField(ta)) { composeFor(ta); return true; }
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
      // 재시도 루프가 이어서 등록하는 중이면 입력창을 다시 열지 않음 (루프가 바로 등록함)
      if (!cmtRetry.on && el && document.body.contains(el) && document.activeElement !== el) {
        replyFocusTarget = el;
        focusReply();
        if (!nativeCmtOn()) post('wantfocus', {});
      }
    }
    tsRefocus.prev = st;
  }, 300);
  // ---------- 보안 확인(Cloudflare Turnstile) 미리 불러두기 ----------
  // 디시는 댓글 칸에 포커스가 가야 Turnstile 스크립트를 내려받기 시작함 → 느린 연결에서는 등록을 누르고 기다리는 20초 안에 토큰이 나오지 못함
  // (진단: state=pending, token_ms=0, focus_ms=26552). 보안 확인 칸이 있는 페이지에서는 디시 함수가 준비되는 대로 미리 불러 둠
  // 이미 불러왔거나 통과했으면 아무것도 하지 않음 (디시 dcTsLoad도 스크립트 중복 방지 검사를 함). 포커스 시각(dcTs.focusAt)은 건드리지 않음
  var tsPre = { tries: 0, called: false, skipped: '' };
  var tsRestarts = 0;     // 보안 확인이 오류·만료로 굳었을 때 다시 시작한 횟수 (진단용)
  (function preloadTurnstile() {
    function tick() {
      tsPre.tries++;
      try {
        if (!document.getElementById('dc-turnstile')) { tsPre.skipped = 'no-slot'; return; }   // 이 페이지엔 보안 확인 칸이 없음
        if (typeof window.turnstile !== 'undefined') { tsPre.skipped = 'loaded'; return; }
        if (window.dcTs && window.dcTs.id !== null) { tsPre.skipped = 'rendered'; return; }
        if (document.querySelector('script[src*="challenges.cloudflare.com/turnstile/"]')) { tsPre.skipped = 'script'; return; }
        if (typeof window.dcTsLoad === 'function') { window.dcTsLoad(); tsPre.called = true; return; }
      } catch (e) { tsPre.skipped = 'err'; return; }
      if (tsPre.tries < 100) setTimeout(tick, 300);  // 디시 함수(common.min.js)가 3G처럼 느린 연결에서 늦게 준비되는 경우 최대 약 30초까지 기다림
      else tsPre.skipped = 'timeout';
    }
    tick();
  })();
  // 디시는 댓글 등록 요청이 끝나면 위젯을 초기화(dcTsReset → turnstile.reset)함. 진행 중인 확인을 그렇게 날리면 처음부터 다시 기다리게 되므로,
  // 토큰 없이 진행 중(pending)이고 시작한 지 1분 30초가 안 됐으면 초기화하지 않음. 토큰이 나왔거나 오류·만료·체크 필요 상태면 평소대로 초기화
  (function guardTsReset() {
    var orig = window.dcTsReset;
    if (typeof orig !== 'function' || orig.__dcappGuard) return;
    var guarded = function () {
      try {
        if (typeof window.turnstile !== 'undefined' && window.dcTs && window.dcTs.id !== null && window.dcTs.state === 'pending') {
          var tok = '';
          try { tok = window.turnstile.getResponse(window.dcTs.id) || ''; } catch (e) {}
          if (!tok && Date.now() - (window.dcTs.loadAt || 0) < 90000) return;
        }
      } catch (e) {}
      return orig.apply(this, arguments);
    };
    guarded.__dcappGuard = true;
    window.dcTsReset = guarded;
  })();
  // 디시는 댓글 칸에 포커스가 가거나 답글 칸을 열 때 위젯을 그 양식의 칸으로 옮김 → 위젯이 새로 그려져 챌린지가 처음부터 돌고 체크박스가 사라짐
  // 체크박스를 눌러야 하는 동안에는 옮기지 않음. 디시 원래 함수는 __dcappOrigTsUse로 보관 (숨은 칸에서 꺼낼 때 revealCheck가 씀)
  (function guardTsUse() {
    var orig = window.dcTsUse;
    if (typeof orig !== 'function' || orig.__dcappGuard) return;
    window.__dcappOrigTsUse = orig;
    var guarded = function () {
      if (tsCheckActive()) return;
      return orig.apply(this, arguments);
    };
    guarded.__dcappGuard = true;
    window.dcTsUse = guarded;
  })();
  window.__dcappOrigTsRender = window.dcTsRender;     // 보조 칸이 위젯을 그릴 때 쓰는 디시 함수
  // 진단: 보안 확인 상태 한 줄 (스크립트 로드 여부, 위젯 생성 여부, 디시가 기록한 오류)
  function tsDiag() {
    try {
      var d = (typeof dcTs !== 'undefined' && dcTs) ? dcTs : null;
      return 'turnstile: js=' + (typeof window.turnstile) + ' slot=' + (document.getElementById('dc-turnstile') ? 'Y' : 'N') +
        ' dcTsLoad=' + (typeof window.dcTsLoad) + ' rendered=' + (d && d.id !== null ? 'Y' : 'N') +
        ' state=' + (d ? d.state : '-') + ' err=' + (d ? (d.err || '-') : '-') + ' retried=' + (d ? !!d.retried : '-') +
        ' preload=' + tsPre.tries + '/' + (tsPre.called ? 'called' : (tsPre.skipped || 'waiting')) + ' restart=' + tsRestarts;
    } catch (e) { return 'turnstile: 진단 실패 ' + e.message; }
  }

  // 답글 칸을 열고 포커스를 옮김 (디시가 답글 칸을 열 때 조금 늦게 만들 수 있어서 칸이 생길 때까지 기다림)
  function openReplyFor(li) {
    // 남아 있던 글자 선택은 풀고 진행 (선택이 남아 있어서 첫 탭이 무시되던 문제)
    var sel = window.getSelection && window.getSelection();
    if (sel && !sel.isCollapsed) { try { sel.removeAllRanges(); } catch (x) {} }
    var replyTries = 0;
    (function waitForReply() {
      var ta = openedReplyArea(li);
      if (!ta) { if (++replyTries < 20) setTimeout(waitForReply, 60); return; }
      replyFocusTarget = ta;
      var focused = focusReply();
      if (!(focused && nativeCmtOn())) post('wantfocus', {});     // 앱에서 한 번 더 (iOS가 스크립트 focus로는 키보드를 안 띄우는 경우 대비)
    })();
  }
  // 디시의 답글 열기(body에 걸린 click)가 끝난 뒤에 실행되도록 document의 버블 단계에서
  document.addEventListener('click', function (e) {
    if (!e.isTrusted) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    var li = t && t.closest ? t.closest('li.comment, li.comment-add') : null;
    if (!li || /^comment_addDiv/.test(li.id || '') || t.closest('form, a, button, input, textarea, .ginfo-area, .comment-edit, .comment-more')) return;   // 답글 칸 자체는 제외 · 댓글 수정 칸·⋯ 메뉴는 답글 열기 아님
    openReplyFor(li);
  }, false);

  // 댓글 안의 링크를 누르면 → 바로 넘어가지 않고, 앱이 '대댓글 달기 / 링크로 이동'을 물어봄
  var pendingReplyLi = null;
  document.addEventListener('click', function (e) {
    if (!e.isTrusted) return;
    var t = e.target.nodeType === 1 ? e.target : e.target.parentElement;
    var a = t && t.closest ? t.closest('a[href]') : null;
    if (!a) return;
    var li = a.closest('li.comment, li.comment-add');
    if (!li || /^comment_addDiv/.test(li.id || '') || a.closest('.ginfo-area, form, button, input, textarea')) return;
    if (/^\s*(#|javascript:)/i.test(a.getAttribute('href') || '')) return;
    e.preventDefault(); e.stopPropagation();
    if (e.stopImmediatePropagation) e.stopImmediatePropagation();
    pendingReplyLi = li;
    // 디시가 줄바꿈(<br>)·다음 링크까지 한 주소로 묶어 놓는 경우가 있음 → 누른 위치의 주소를 고름 (못 고르면 첫 주소)
    var href = a.href;
    var cut = href.search(/%3Cbr|<br|%0A|%0D|%20https?:|\s/i);
    if (cut > 8) {
      var first = href.slice(0, cut);
      try {
        // 주소 경계는 'http' 시작점 (사이에 <br>만 있어 글자로는 붙어 보임). 눌린 지점에서 가장 가까운 주소의 글자 영역을 고름
        var txt = a.textContent || '', urls = [], re = /https?:\/\/.*?(?=https?:\/\/|[\s<>"']|$)/gi, mm;
        while ((mm = re.exec(txt))) { if (!mm[0]) { re.lastIndex++; continue; } urls.push({ u: mm[0], s: mm.index, e: mm.index + mm[0].length }); }
        if (urls.length > 1) {
          var tw = document.createTreeWalker(a, NodeFilter.SHOW_TEXT, null), nodes = [], pos = 0, tn;
          while ((tn = tw.nextNode())) { nodes.push({ n: tn, s: pos }); pos += tn.nodeValue.length; }
          var locate = function (off, atEnd) {
            for (var ni = 0; ni < nodes.length; ni++) {
              var nd = nodes[ni], len = nd.n.nodeValue.length;
              if (off < nd.s + len || (atEnd && off <= nd.s + len)) return { n: nd.n, o: Math.max(0, off - nd.s) };
            }
            return null;
          };
          var best = null, bestD = 1e9;
          urls.forEach(function (it) {
            var st = locate(it.s, false), en = locate(it.e, true);
            if (!st || !en) return;
            var r = document.createRange();
            r.setStart(st.n, st.o); r.setEnd(en.n, en.o);
            var rects = r.getClientRects(), d = 1e9;
            for (var ri = 0; ri < rects.length; ri++) {
              var rc = rects[ri];
              var dx = e.clientX < rc.left ? rc.left - e.clientX : (e.clientX > rc.right ? e.clientX - rc.right : 0);
              var dy = e.clientY < rc.top ? rc.top - e.clientY : (e.clientY > rc.bottom ? e.clientY - rc.bottom : 0);
              d = Math.min(d, dy * 4 + dx);       // 줄(세로)이 가장 중요
            }
            if (d < bestD) { bestD = d; best = it; }
          });
          if (best) first = best.u;
        }
      } catch (err) {}
      href = first;
    }
    post('cmtlink', { href: href });
  }, true);
  // 앱에서 '대댓글 달기'를 고르면: 댓글 본문을 눌러 디시가 답글 칸을 열게 하고 포커스
  function replyPending() {
    var li = pendingReplyLi;
    pendingReplyLi = null;
    if (!li || !document.body.contains(li)) return false;
    (li.querySelector('.usertxt, .txt, p') || li).click();
    openReplyFor(li);
    return true;
  }

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
  // 글 목록에서 제목이 같은 글의 주소 (분할 화면: 방금 쓴 글을 오른쪽에 열기 위함)
  function findPostByTitle(t) {
    var want = String(t || '').replace(/\s+/g, ' ').trim();
    if (!want) return null;
    var rows = document.querySelectorAll('.gall-detail-lst li a.lt');
    for (var i = 0; i < rows.length; i++) {
      var a = rows[i];
      if (!/\/(board|mini|person)\/[^\/]+\/\d+/.test(a.href || '')) continue;
      var s = a.querySelector('.subjectin') || a;
      var txt = (s.textContent || '').replace(/\s+/g, ' ').trim();
      if (txt === want || txt.indexOf(want) === 0 || txt.replace(/^\[[^\]]*\]\s*/, '') === want) return a.href;
    }
    return null;
  }
  function refreshComments() {
    // 댓글만 다시 받음 (디시 댓글 새로고침 버튼, 없으면 댓글 목록 다시 받기) — 화면 위치는 그대로 둠
    var box = document.getElementById('comment_box');
    var b = commentRefreshButton();
    // 다시 받는 동안 디시 쪽 동작(포커스·스크롤)으로 화면이 튀면 처음 위치로 되돌림
    var y = window.scrollY, tries = 0;
    var keep = setInterval(function () {
      if (Math.abs(window.scrollY - y) > 2) window.scrollTo(0, y);
      if (++tries >= 20) clearInterval(keep);
    }, 100);
    if (b) b.click();
    else if (box && typeof window.comment_list === 'function') window.comment_list(0);
    else { clearInterval(keep); return 'none'; }
    return 'clicked';
  }
  function scrollToComments() {
    var box = document.getElementById('comment_box') || document.querySelector('[class*="comment-box"], [class*="comment_box"]');
    if (box) box.scrollIntoView({ block: 'start' });
    return !!box;
  }

  // ---------- 댓글 영역이 화면에 걸쳐 있는지 앱에 알림 (컨트롤바 '내리면 숨기기'에서 댓글을 볼 땐 다시 보이게) ----------
  // 댓글 영역 윗부분이 화면 아래쪽 끝에서 60px 안으로 들어와 있고, 아랫부분이 아직 화면 위로 다 지나가지 않았을 때만 on.
  // 댓글 영역을 지나쳐 더 내려가거나(아래 글 목록 등) 그 위로 돌아가면 off. 안 보이게 숨겨졌거나 높이가 0이면 off. 바뀔 때만 보냄
  var cmtViewOn = false, cmtViewTick = false;
  function checkCmtView() {
    cmtViewTick = false;
    var box = document.getElementById('comment_box');
    var r = box ? box.getBoundingClientRect() : null;
    var on = !!r && r.height > 0 && r.top < window.innerHeight - 60 && r.bottom > 0;
    if (on !== cmtViewOn) { cmtViewOn = on; post('cmtview', { on: on }); }
  }
  window.addEventListener('scroll', function () {
    if (!cmtViewTick) { cmtViewTick = true; requestAnimationFrame(checkCmtView); }
  }, { passive: true });
  window.addEventListener('resize', checkCmtView);
  setTimeout(checkCmtView, 300);

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
  /// 게시물 필터 깔때기 아이콘 (말머리 줄 맨 왼쪽)
  var FILTER_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.5 9.5h9M9.5 12.8h5M11.2 16h1.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
  var lastHeadSig = null;
  /// 말머리 이름들을 앱에 알림 (필터 시트의 말머리 고르기). 같은 목록이면 다시 보내지 않음
  function reportHeadNames(names) {
    var sig = names.join('|');
    if (sig === lastHeadSig) return;
    lastHeadSig = sig;
    post('headnames', { names: names });
  }
  /// 말머리 줄(#dcapp-headbar): 맨 왼쪽 깔때기(게시물 필터) + 말머리 탭. 말머리 탭이 없는 갤러리에서도 깔때기는 보임
  function buildHeadBar() {
    if (!document.querySelector('ul.gall-detail-lst') || !document.getElementById('pagination_div')) return;
    var row = headRow();
    var tabs = [];
    if (row) row.items.forEach(function (a) {
      var name = txt(a);
      if (!name || name.length > 12) return;
      var url = name === '전체' ? '' : headHref(a);
      if (name !== '전체' && !url) return;
      if (tabs.some(function (t) { return t.name === name; })) return;
      tabs.push({ name: name, url: url, el: a });
    });
    if (tabs.length < 2) {
      // 말머리가 없는 갤러리: 말머리 줄을 두지 않음 → 게시물 필터는 앱 상단바 우측에 있음
      var old = document.getElementById('dcapp-headbar');
      if (old) old.parentNode.removeChild(old);
      reportHeadNames([]);
      return;
    }
    row.box.classList.add('dcapp-hide');
    var cur = new URLSearchParams(location.search).get('headid') || '';
    var sig = tabs.map(function (t) { return t.name; }).join('|') + '#' + cur;
    var names = tabs.map(function (t) { return t.name; }).filter(function (n) { return n !== '전체'; });
    var bar = document.getElementById('dcapp-headbar');
    if (bar && bar.getAttribute('data-sig') === sig && bar.nextSibling === row.box) { reportHeadNames(names); return; }
    if (!bar) {
      bar = document.createElement('div');
      bar.id = 'dcapp-headbar';
    }
    bar.setAttribute('data-sig', sig);
    bar.innerHTML = '';
    // 왼쪽 고정 묶음(깔때기 + '전체')과 오른쪽 가로 스크롤 묶음(나머지 말머리). 스크롤해도 왼쪽 두 버튼은 그대로
    var fixed = document.createElement('div');
    fixed.className = 'dcapp-hfix';
    var scroll = document.createElement('div');
    scroll.className = 'dcapp-hscroll';
    var fb = document.createElement('button');
    fb.type = 'button';
    fb.id = 'dcapp-filterbtn';
    fb.setAttribute('aria-label', '게시물 필터');
    fb.innerHTML = FILTER_ICON;
    fb.addEventListener('click', function () { post('listfilter', {}); });
    fixed.appendChild(fb);
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
      (t.name === '전체' ? fixed : scroll).appendChild(b);
    });
    bar.appendChild(fixed);
    bar.appendChild(scroll);
    row.box.parentNode.insertBefore(bar, row.box);
    var sel = bar.querySelector('button.on');
    if (sel && scroll.contains(sel)) { var dx = sel.getBoundingClientRect().left - scroll.getBoundingClientRect().left; if (dx > scroll.clientWidth - 60) scroll.scrollLeft += dx - 16; }
    reportHeadNames(names);
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
    // 글쓰기 양식이 없고 갤러리에서 차단됐다는 안내만 있으면 → 앱이 차단 안내를 띄우고 글쓰기를 막음
    if (!document.getElementById('subject')) {
      var bodyTxt = (document.body ? document.body.innerText : '').replace(/\s+/g, ' ').trim();
      if (bodyTxt.length < 700 && /차단|이용\s?제한/.test(bodyTxt) && !/cloudflare|보안|verify|확인하는 중/i.test(bodyTxt)) {
        return { ok: false, banned: true, msg: bodyTxt.slice(0, 200) };
      }
    }
    var name = document.getElementById('name'), pw = document.getElementById('password');
    var heads = [];
    document.querySelectorAll('#swiper-headtxt li[data-no], .malwrt-lst li[data-no]').forEach(function (li) {
      var a = li.querySelector('a');
      var oc = a && a.getAttribute('onclick') || '';
      if (!/head_select/.test(oc)) return;                       // 관리자 전용 말머리 등은 못 고름
      var no = String(li.getAttribute('data-no'));
      // 말머리별 안내 문구: 디시 head_select()가 #placeholder{말머리번호} 값을 편집기에 넣음 (값에 <br> 같은 HTML이 올 수 있어서 원문 그대로 넘기고 앱이 정리)
      var phEl = document.getElementById('placeholder' + no);
      heads.push({ no: no, name: txt(a), ph: phEl ? phEl.value : '' });
    });
    // 기본 안내 문구(말머리가 없거나 안내가 비어 있을 때): #placeholder0, 없으면 본문 칸의 data-ph
    var ph0 = document.getElementById('placeholder0'), textboxEl = document.getElementById('textbox');
    var phDefault = ph0 ? ph0.value : (textboxEl ? (textboxEl.getAttribute('data-ph') || '') : '');
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
      heads: heads, head: ht ? String(ht.value) : '', phDefault: phDefault,
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
    if (/series/i.test(n.className || '') || /order-series/.test(html.slice(0, 200))) return { label: '시리즈', src: '' };
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
      if (special && (media || !(n.innerText || '').trim() || /vote|poll|movie|series/i.test(n.className || ''))) {
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
  // ---------- 투표 만들기 (앱 화면에서 쓴 것을 디시 투표 양식에 채워 등록) ----------
  // 디시 투표 창(#votePopup)은 띄우지 않는다. 디시 양식(#voteUpload)의 칸을 채우고 디시 vote_submit을 그대로 불러서
  // 디시가 투표를 만들고 편집기에 투표 칸을 넣게 한다. 결과는 기존처럼 collectWebInserts로 앱이 가져간다.
  // 보기 사진 한 장을 디시 투표 사진 올리기(uploadVote)로 올림. 끝나면 보기 칸에 주소가 들어가고 'ok', 실패면 'fail'
  function voteUploadImage(sort, o) {
    return new Promise(function (resolve) {
      var $ = window.jQuery;
      var input = document.querySelector('#vote_img_form input[name=vote_img]');
      if (!input || typeof window.uploadVote !== 'function') return resolve('nofeature');
      var bin = atob(o.b64), bytes = new Uint8Array(bin.length);
      for (var k = 0; k < bin.length; k++) bytes[k] = bin.charCodeAt(k);
      var dt = new DataTransfer();
      dt.items.add(new File([bytes], 'vote_' + sort + '.' + o.ext, { type: o.mime }));
      $('input[name=vote_img_sort]').val(String(sort));
      $('input[name=vote_img_' + sort + ']').val('');
      input.files = dt.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));    // 디시 인라인 onchange → uploadVote
      var waited = 0, timer = setInterval(function () {
        waited += 200;
        if ($('input[name=vote_img_' + sort + ']').val()) { clearInterval(timer); resolve('ok'); }
        else if (input.value === '' && waited > 400) { clearInterval(timer); resolve('fail'); }   // 디시가 응답 뒤 파일 칸을 비움
        else if (waited >= 60000) { clearInterval(timer); resolve('timeout'); }
      }, 200);
    });
  }
  // 디시 투표 폼에 값을 채워 등록 (디시 투표 창은 띄우지 않음). 보기 사진·기간·공개·권한까지 디시 폼 칸과 같은 값
  async function submitVote(p) {
    if (!isWritePage()) return 'notwrite';
    var $ = window.jQuery;
    if (!$ || typeof window.vote_submit !== 'function' || !$('#voteUpload').length) return 'nofeature';
    if ($('#poll_no').val()) return 'hasPoll';     // 글 하나에 투표는 하나
    var title = String(p.title || '').trim();
    var opts = (p.options || []).map(function (o) {
      return { text: String(o.text || '').trim(), b64: o.b64 || '', mime: o.mime || 'image/jpeg', ext: o.ext || 'jpg' };
    });
    if (!title || title.length > 40 || opts.length < 2 || opts.length > 20 ||
        opts.some(function (o) { return !o.text || o.text.length > 30; })) return 'invalid';
    // 이전 시도의 보기·사진·설정을 디시 초기화 함수로 지운 뒤 채움
    if (typeof window.resetVote === 'function') { try { window.resetVote(); } catch (e) {} }
    var guard = 0;
    while ($('#voteList > li > .item > input').length < opts.length && guard++ < 25) {
      if (typeof window.addVote !== 'function') return 'nofeature';
      window.addVote();                            // 디시 '보기 추가' (보기 칸과 복수 선택 개수 칸을 함께 늘림)
    }
    var inputs = $('#voteList > li > .item > input');
    if (inputs.length !== opts.length) return 'nofeature';
    inputs.each(function (i) { $(this).val(opts[i].text); });
    // 보기 사진: 한 장씩 올림 (올라가면 보기 칸에 디시 주소가 들어감)
    for (var i = 0; i < opts.length; i++) {
      if (!opts[i].b64) continue;
      var r = await voteUploadImage(inputs.eq(i).data('sort'), opts[i]);
      if (r !== 'ok') return 'imgfail:' + (i + 1);
    }
    var form = $('#voteUpload');
    function setCheck(el, on) { if (el.is(':checked') !== !!on) el.prop('checked', !!on).trigger('change'); }
    function selectVal(sel, v) { if (v != null && sel.find('option[value="' + v + '"]').length) sel.val(String(v)); }
    form.find('input[name=vote_title]').val(title);
    setCheck(form.find('input[name=vote_multi]'), p.multi);
    if (p.multi) selectVal(form.find('select[name=vote_multi_cnt]'), Math.max(2, Math.min(opts.length, parseInt(p.multiCount, 10) || 2)));
    setCheck(form.find('input[name=end_date]'), p.endDate);                 // 종료 시간 설정 (끄면 작성자가 종료할 때까지)
    if (p.endDate) {
      if (p.date) form.find('input[name=vote_date]').val(String(p.date));
      selectVal(form.find('select[name=vote_hour]'), p.hour);
      selectVal(form.find('select[name=vote_minute]'), p.minute);
    }
    setCheck(form.find('input[name=vote_preview]'), p.preview);             // 종료 전 결과 미리보기 (결과 공개)
    selectVal(form.find('#vote_permission'), p.permission);                 // A: 모두 · M: 고정닉만
    // 디시 팝업은 숨기고, 편집기에 투표 칸을 넣을 자리를 잡음 (openWebFeature와 같은 준비)
    try { $('#votePopup').hide(); } catch (e) {}
    clearEditor();
    try {
      $('#textbox').summernote('focus');
      $('#textbox').summernote('editor.saveRange');
    } catch (e) {}
    try { window.vote_submit(); } catch (e) { return 'error:' + e.message; }   // 동기 요청이라 끝나면 바로 결과가 보임
    return $('#poll_no').val() ? 'ok' : 'failed';
  }
  // ---------- 시리즈 만들기 (앱 화면에서 쓴 제목·게시물 주소를 디시 시리즈 창에 채워 디시 함수로 만듦) ----------
  // 디시 시리즈 창(#seriesPopup)은 띄우지 않는다. 주소 확인(addSeries)과 저장(saveSeries('insert'))은 디시 함수 그대로,
  // 저장되면 편집기에 시리즈 칸이 들어가고 기존처럼 collectWebInserts로 앱이 가져간다. 등록은 write_submit이 디시 양식에 넣음.
  function submitSeries(p) {
    if (!isWritePage()) return 'notwrite';
    var $ = window.jQuery;
    if (!$ || typeof window.addSeries !== 'function' || typeof window.saveSeries !== 'function' || !$('#seriesPopup').length) return 'nofeature';
    var title = String(p.title || '').trim();
    var urls = (p.urls || []).map(function (u) { return String(u).trim(); }).filter(function (u) { return u !== ''; });
    if (!title || title.length > 20 || urls.length < 1 || urls.length > 50) return 'invalid';
    if ((p.existing || 0) >= 5) return 'limit';                  // 디시: 시리즈는 글 하나에 5개까지
    if (window.series_order_no < 1) { try { localStorage.removeItem('upload_series'); } catch (e) {} }   // 처음 만드는 시리즈: 옛 목록 지움 (seriesPop과 같음)
    $('#seriesBoxBottom').html('').show();
    $('#seriesTitle').val(title);
    $('#urlText').val(urls.join('\n'));
    try { window.addSeries(); } catch (e) { return 'error:' + e.message; }   // 디시 서버에서 게시물 주소 확인 (동기)
    if (!$('#seriesBoxBottom > li').length) { $('#seriesBoxBottom').html(''); return 'nourl'; }
    var bad = $('#seriesBoxBottom input[name=is_allowed_series]').filter(function () { return $(this).val() == '0'; }).length;
    if (bad > 0) { $('#seriesBoxBottom').html(''); return 'notallowed'; }
    clearEditor();                                              // openWebFeature와 같은 준비: 편집기에는 새로 넣은 시리즈만
    try {
      $('#textbox').summernote('focus');
      $('#textbox').summernote('editor.saveRange');
    } catch (e) {}
    try { window.saveSeries('insert'); } catch (e) { return 'error:' + e.message; }   // 제목·주소 저장 + 편집기에 시리즈 칸
    return $('.note-editable .block.series').length ? 'ok' : 'failed';
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
  // 디시콘 패키지 찾기: 디시 '디시콘 정보' 창이 쓰는 getDcconDetail(mode=u)에 디시콘 번호(dccon.php?no=)를 보내면 그 디시콘의 패키지 창이 옴
  // → 패키지 번호(data-package-idx)·이름·패키지 안 디시콘 번호 전부를 읽음. 글·댓글의 어떤 디시콘이든 됨 (2026-11-25 확인). 못 찾으면 null
  function dcconNoOf(src) {
    var q = /[?&]no=([^&#"'\s]+)/.exec(src || '');
    return q ? q[1] : '';
  }
  async function dcconPackageFor(key) {
    var k = String(key || '');
    if (!/^[0-9a-zA-Z]{20,}$/.test(k)) return null;
    var html = '';
    try {
      var res = await fetch('/dccon/getDcconDetail', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' },
        body: 'dcconInfo=' + encodeURIComponent(k) + '&mode=u'
      });
      if (res.ok) html = await res.text();
    } catch (e) { return null; }
    var page = new DOMParser().parseFromString(html || '', 'text/html');
    var pop = page.querySelector('[data-package-idx]');
    var pkg = pop ? String(pop.getAttribute('data-package-idx') || '') : '';
    var keys = [];
    page.querySelectorAll('.dccon-img-lst img, .dccon-img-lst video, .dccon-img-lst source').forEach(function (m) {
      ['data-src', 'src', 'ori-data', 'data-gif', 'poster'].forEach(function (attr) {
        var no = dcconNoOf(m.getAttribute(attr));
        if (no && keys.indexOf(no) < 0) keys.push(no);
      });
    });
    if (!/^\d+$/.test(pkg) || !keys.length) return null;
    if (keys.indexOf(k) < 0) keys.push(k);   // 누른 디시콘의 번호도 함께
    var name = page.querySelector('.top-tit .name') || page.querySelector('.dccon-caption-box .name');
    return { pkg: pkg, name: name ? (name.textContent || '').trim() : '', keys: keys };
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
  // 디시가 유튜브 검색 결과를 고를 때 쓰는 것과 같은 방식(summernote insertYt)으로 영상 칸을 만들고 그 HTML을 돌려줌.
  // 편집기는 호출하기 전 상태로 되돌리지 않음 (호출하는 쪽이 본문 HTML을 새로 넣음). 실패하면 ''
  function captureYtBlock(id) {
    var $ = window.jQuery, ed = $ && $('#textbox');
    if (!ed || !ed.length || !ed.summernote || !/^[A-Za-z0-9_-]{11}$/.test(id)) return '';
    try {
      ed.summernote('code', '');
      ed.summernote('focus');
      ed.summernote('editor.saveRange');
      ed.summernote('insertYt', id);
      var out = String(ed.summernote('code') || '');
      return out.indexOf(id) >= 0 ? out : '';
    } catch (e) { return ''; }
  }
  async function nativeSubmit(p) {
    if (!isWritePage()) return 'notwrite';
    var $ = window.jQuery;
    var name = document.getElementById('name'), pw = document.getElementById('password');
    // 앱이 정한 값은 '직접 입력한 칸'으로 표시 → 유동 닉네임 자동 채우기가 옛 값으로 덮어쓰지 않게
    if (name && p.nick != null && !name.disabled && !name.readOnly) { setField(name, p.nick); name.setAttribute('data-dcapp-user', '1'); }
    if (pw && p.pw != null) { setField(pw, p.pw); pw.setAttribute('data-dcapp-user', '1'); }
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
      // 디시의 업로드 로딩 표시가 사라지고 사진 수가 더 변하지 않을 때까지 잠깐 더 기다림 (올라가는 도중에 본문을 덮어쓰지 않게)
      var lastCnt = -1, stable = 0;
      for (var w2 = 0; w2 < 40 && stable < 3; w2++) {
        await sleep(250);
        var lb = document.querySelector('.loading-box');
        var busy = !!(lb && lb.getBoundingClientRect().height > 0 && getComputedStyle(lb).display !== 'none');
        var cnt = box ? box.querySelectorAll('img').length : 0;
        if (!busy && cnt === lastCnt) stable++; else stable = 0;
        lastCnt = cnt;
      }
    }
    // 디시가 만든 사진 칸(업로드 순서대로)
    var imgHTML = [];
    if (box) box.querySelectorAll('img').forEach(function (im) {
      var blk = im.closest('div.block') || im;
      if (box.contains(blk) && imgHTML.indexOf(blk.outerHTML) < 0) imgHTML.push(blk.outerHTML);
    });
    // 본문의 유튜브 영상 칸: 디시 방식으로 만들어 둠 (실패한 것은 아래에서 디시 영상 목록으로 붙임)
    var ytHTML = {}, ytFallback = [];
    blocks.forEach(function (b) {
      if (b.t !== 'youtube' || Object.prototype.hasOwnProperty.call(ytHTML, b.id)) return;
      ytHTML[b.id] = captureYtBlock(String(b.id));
      if (!ytHTML[b.id]) ytFallback.push(String(b.id));
    });
    // 앱에서 정한 순서대로 다시 짜기: 글자 칸은 줄마다 문단, 사진 칸은 디시가 만든 칸 그대로
    var html = '', k = 0;
    blocks.forEach(function (b) {
      if (b.t === 'raw') {
        html += b.html;                                   // 수정: 원래 있던 사진·디시콘 등은 그대로
      } else if (b.t === 'youtube') {
        html += ytHTML[b.id] || '';                       // 유튜브 영상 칸 (순서 그대로)
      } else if (b.t === 'image') {
        if (k < imgHTML.length) html += imgHTML[k++] + '<p><br></p>';
      } else {
        html += b.html ? b.html : String(b.text || '').split('\n').map(function (l) { return l.length ? '<p>' + escHTML(l) + '</p>' : '<p><br></p>'; }).join('');
      }
    });
    while (k < imgHTML.length) html += imgHTML[k++] + '<p><br></p>';   // 혹시 남은 사진
    if (useSN) { ed.summernote('code', html); try { ed.val(html); } catch (e) {} }
    else if (box) box.innerHTML = html;
    if (box) box.dispatchEvent(new Event('input', { bubbles: true }));
    // 사진이 빠진 채 등록되지 않게: 올린 사진 수만큼 본문에 들어갔는지 확인
    if (imgs.length) {
      var inBody = box ? Array.prototype.filter.call(box.querySelectorAll('img'), function (im) { return /viewimage/.test(im.getAttribute('src') || ''); }).length : 0;
      var rawImgs = blocks.filter(function (b) { return b.t === 'raw' && /viewimage/.test(b.html || ''); }).length;
      if (inBody < imgs.length + rawImgs) return 'imgmissing:' + inBody + '/' + (imgs.length + rawImgs);
    }
    // 본문의 유튜브 링크 → 영상으로 첨부 (디시 '유튜브 추가'와 같은 함수. 같은 영상이 이미 붙어 있으면 건너뜀)
    ytFallback.forEach(function (id) {
      if (!/^[A-Za-z0-9_-]{11}$/.test(String(id))) return;
      if (($('#yData').val() || '').indexOf('|' + id) >= 0) return;
      if (typeof window.insertChagneThum === 'function') { try { window.insertChagneThum('yt', id); } catch (e) {} }
    });
    // 유튜브 영상만 첨부하는 글: 링크 글자를 뗐으니 본문이 비어 디시가 '내용을 입력해 주세요'라며 막음 → 안 보이는 글자 한 칸을 넣어 채움
    if ((Array.isArray(p.youtube) ? p.youtube.length : 0) > 0) {
      var bodyText = String(box ? (box.textContent || '') : '').replace(/[\u200B\u00A0\s]/g, '');
      var hasMedia = !!(box && box.querySelector('img, video, iframe, embed, object'));
      if (!bodyText && !hasMedia) {
        var filler = '<p>&nbsp;</p>';
        if (useSN) { ed.summernote('code', filler); try { ed.val(filler); } catch (e) {} } else if (box) box.innerHTML = filler;
        if (box) box.dispatchEvent(new Event('input', { bubbles: true }));
      }
    }
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
    var out = ['script: v372-dccon-package','URL: ' + location.href, 'UA: ' + navigator.userAgent];
    out.push(tsDiag());
    out.push(tsHostDiag());
    // 화면 폭·안전 영역·본문 컨테이너 폭 (아이패드 가로 양옆 여백 확인용)
    try {
      var probe = document.createElement('div');
      probe.style.cssText = 'position:fixed;left:0;top:0;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
      document.body.appendChild(probe);
      var pcs = getComputedStyle(probe);
      var safe = pcs.paddingTop + ' ' + pcs.paddingRight + ' ' + pcs.paddingBottom + ' ' + pcs.paddingLeft;
      document.body.removeChild(probe);
      var vv = window.visualViewport;
      var vp = document.querySelector('meta[name="viewport"]');
      out.push('screen: inner=' + innerWidth + 'x' + innerHeight + ' client=' + document.documentElement.clientWidth + ' screen=' + screen.width + 'x' + screen.height +
        ' vv=' + (vv ? Math.round(vv.width) + 'x' + Math.round(vv.height) + ' scale=' + vv.scale : '-') + ' dpr=' + devicePixelRatio);
      out.push('viewport meta: ' + (vp ? vp.content : '(없음)') + ' | safe-area(t r b l): ' + safe);
      ['html', 'body', '.container', '.gall-detail-lst', '.sec-wrap', '.main-wrapping'].forEach(function (sel) {
        var el = document.querySelector(sel);
        if (!el) return;
        var r = el.getBoundingClientRect(), cs = getComputedStyle(el);
        out.push('box ' + sel + ': left=' + Math.round(r.left) + ' width=' + Math.round(r.width) + ' margin=' + cs.marginLeft + '/' + cs.marginRight +
          ' padding=' + cs.paddingLeft + '/' + cs.paddingRight + ' bg=' + cs.backgroundColor + ' maxW=' + cs.maxWidth);
      });
    } catch (e) { out.push('layout diag error: ' + e.message); }
    // 뒤로가기 흰 공백 진단: 헤드바 위치·스크롤, 헤드바 바로 앞 형제 요소의 태그·클래스·높이
    try {
      var hb = document.getElementById('dcapp-headbar');
      if (!hb) out.push('headbar: (없음)');
      else {
        var hr = hb.getBoundingClientRect();
        var hps = hb.previousElementSibling;
        var hpr = hps ? hps.getBoundingClientRect() : null;
        out.push('headbar: top=' + Math.round(hr.top) + ' scrollY=' + Math.round(window.scrollY) +
          ' prev=' + (hps ? hps.tagName + '.' + clsOf(hps) + ' top=' + Math.round(hpr.top) + ' bottom=' + Math.round(hpr.bottom) + ' h=' + Math.round(hpr.height) : '(없음)'));
      }
    } catch (e) { out.push('headbar diag error: ' + e.message); }
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
    // 글 아래 수정·삭제 버튼: 위치, 그 자리 맨 위에 있는 요소, 감싼 칸들의 구조 (세로 줄 터치 차단막·덧씌운 칸에 가려졌는지 확인용)
    try {
      var sai = document.getElementById('dcapp-sideprobe');
      var saiCS = sai ? getComputedStyle(sai) : null;
      var saiR = saiCS ? (parseFloat(saiCS.paddingRight) || 0) : 0;
      out.push('--- 글 아래 버튼 ---  html클래스=' + document.documentElement.className.split(/\s+/).filter(function (c) { return /^dcapp-duo/.test(c); }).join(',') +
               ' 안전영역(좌,우)=' + (saiCS ? saiCS.paddingLeft + ',' + saiCS.paddingRight : '?') + ' 화면폭=' + innerWidth);
      var barea = document.querySelector('.gall-thum-btm') || document.body;
      Array.prototype.forEach.call(barea.querySelectorAll('button, a'), function (b) {
        if (!/^(수정|삭제|목록보기|글쓰기)$/.test(txt(b))) return;
        var r = b.getBoundingClientRect();
        var top = r.width ? document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2) : null;
        out.push('  [' + txt(b) + '] ' + b.tagName + '.' + clsOf(b).slice(0, 30) + ' 좌=' + Math.round(r.left) + ' 우=' + Math.round(r.right) + ' 폭=' + Math.round(r.width) +
                 ' 맨위요소=' + (top ? (top.tagName + (top.id ? '#' + top.id : '') + '.' + String(top.className).slice(0, 30)) : '(안 보임)') +
                 (top && (top === b || b.contains(top)) ? ' (버튼 자신)' : (top ? ' (다른 요소가 덮고 있음)' : '')) +
                 (r.width && r.right > innerWidth - saiR + 1 ? ' ★세로 줄 안에 걸쳐 있음' : ''));
        var e = b.parentElement, depth = 0;
        while (e && e !== barea && depth < 5 && r.width) {
          var cs = getComputedStyle(e), er = e.getBoundingClientRect();
          out.push('      ↑ ' + e.tagName + (e.id ? '#' + e.id : '') + '.' + clsOf(e).slice(0, 30) + ' 폭=' + Math.round(er.width) + ' 높이=' + Math.round(er.height) +
                   ' disp=' + cs.display + ' pos=' + cs.position + ' 오른쪽테두리=' + cs.borderRightWidth + ' 오른쪽안쪽여백=' + cs.paddingRight);
          e = e.parentElement; depth++;
        }
      });
    } catch (e0) {}
    var bp = document.getElementById('board_pw');      // 글 수정·삭제 비밀번호 확인 페이지
    if (bp) out.push('board_pw: 글자수=' + (bp.value || '').length + ' 직접입력표시=' + (bp.getAttribute('data-dcapp-user') || '0') +
                     ' readonly=' + !!bp.readOnly + ' disabled=' + !!bp.disabled + ' 채우기시도=' + (bp.getAttribute('data-dcapp-anon-tries') || '0'));
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
  // 본문에 새로 들어온 사진은 80ms 디바운스를 기다리면 그 사이에 원본이 보이므로, 변화가 생기는 즉시(그리기 전에) 차단 칸을 씌움
  new MutationObserver(function (muts) {
    var hit = false;
    for (var i = 0; i < muts.length && !hit; i++) {
      var added = muts[i].addedNodes;
      for (var j = 0; j < added.length && !hit; j++) {
        var n = added[j];
        if (n.nodeType === 1 && (/^(IMG|VIDEO)$/.test(n.tagName) || (n.querySelector && n.querySelector('img, video')))) hit = true;
      }
    }
    if (hit) { try { applyImageBlocks(cfg.enabled !== false); } catch (e) {} }
  }).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('load', function (e) {
    var t = e.target, body = articleBody();
    if (t && t.tagName === 'IMG' && body && body.contains(t)) schedule();
  }, true);

  window.__dcapp = {
    setConfig: function (c) {
      cfg = c || {};
      runtimeImg = {};
      imgChecked = {};
      // 탭해서 펼쳐 본 글도 차단 설정이 바뀌면 다시 접히게 (펼친 뒤 다시 차단했을 때 바로 가려지도록)
      document.querySelectorAll('[data-dcapp-revealed]').forEach(function (el) { el.removeAttribute('data-dcapp-revealed'); });
      clearSelection();
      tintFirstDone = false;
      apply();
      return true;
    },
    // 앱이 이 화면의 여백 설정(옆 세로 줄 쪽·뒤집힘·오른쪽 끝 닿음)을 다시 보냄 — 분할·회전으로 자리가 바뀔 때 페이지를 새로 불러오지 않고 맞춤
    setDuo: function (col, flip, flipR) {
      cfg.duoCol = !!col; cfg.duoFlip = !!flip; cfg.duoFlipR = !!flipR;
      markCommentFieldsReadonly();
      return true;
    },
    clearSelection: function () { clearSelection(); return true; },
    markBlockedImageKey: function (key) { if (key) runtimeImg[key] = true; apply(); return true; },
    loginState: loginState,
    deferredImage: deferredImage,
    openGalleryInfo: openGalleryInfo,
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
      return h ? describe(h, null, false) : null;
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
    reportPost: reportPost,
    alarmAuthor: alarmAuthor,
    moveWriteFocus: moveWriteFocus,
    focusReply: focusReply,
    replyPending: replyPending,
    cmtSubmit: cmtSubmit,
    cmtRefreshCode: cmtRefreshCode,
    findPostByTitle: findPostByTitle,
    composeSync: composeSync,
    ensureReplyTarget: ensureReplyTarget,
    composeDcconSend: composeDcconSend,
    txtconOpen: txtconOpen,
    txtconSetText: txtconSetText,
    txtconSetColor: txtconSetColor,
    txtconSend: txtconSend,
    txtconClose: txtconClose,
    headTabs: headTabs,
    openNotice: openNotice,
    focusTitle: focusTitle,
    submitWrite: submitWrite,
    writeInfo: writeInfo,
    refreshCaptcha: refreshCaptcha,
    nativeSubmit: nativeSubmit,
    // 컨트롤바 '댓글작성': 글 아래 댓글 칸을 누른 것과 같이 앱 댓글 입력창을 연다
    focusCommentInput: function () { focusCommentInput(); return true; },
    setReadPosts: setReadPosts,
    setListFilter: setListFilter,
    articleIdentity: articleIdentity,
    openWebFeature: openWebFeature,
    submitVote: submitVote,
    submitSeries: submitSeries,
    collectWebInserts: collectWebInserts,
    dcconTabs: dcconTabs,
    dcconItems: dcconItems,
    dcconPackageFor: dcconPackageFor,
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
    /// 문서 맨 처음(document-start)에 실행: 앱 스타일이 붙기 전 원본 디시 화면이 잠깐 보이는 것(깜빡임)을 막으려고 본문을 가려 둠.
    /// 본문 스타일 적용(apply)이 끝나면 풀고, 그래도 안 풀리면 시간이 지나 풀어서 원본 화면이 보이게 함 (화면이 멈추지 않게)
    static let preload = #"""
(function () {
  var de = document.documentElement;
  if (!de) return;
  var st = document.createElement('style');
  st.id = 'dcapp-pending-style';
  st.textContent = 'html.dcapp-pending body{visibility:hidden!important}';
  de.appendChild(st);
  de.classList.add('dcapp-pending');
  setTimeout(function () {
    var h = document.documentElement;
    if (h) h.classList.remove('dcapp-pending');
  }, 5000);
})();
"""#

    static let netLog = #"""
// DCApp 네트워크 기록 — 페이지가 몰래 불러오는 주소 중 알림 관련(alarm/noti/push/alim/bell/memo) 것만 기록
(function () {
  if (window.__dcappNet) return;
  var log = window.__dcappNet = [];
  // 보안 확인(Cloudflare) 서버와 연결을 미리 맞춰 둠 — 스크립트(common.min.js)를 내려받는 동안 연결 설정을 끝내 두려고 (글·글쓰기 페이지에서만)
  (function () {
    if (!/\/(board|mini|person)\/[^\/]+\/\d+|\/write(mini|pr)?\//.test(location.pathname)) return;
    function add() {
      var p = document.head || document.documentElement;
      if (!p) return false;
      [null, 'anonymous'].forEach(function (cors) {   // 스크립트(무자격)와 fetch(CORS)는 연결 풀이 달라서 둘 다
        var l = document.createElement('link');
        l.rel = 'preconnect'; l.href = 'https://challenges.cloudflare.com';
        if (cors) l.crossOrigin = cors;
        p.appendChild(l);
      });
      return true;
    }
    if (!add()) document.addEventListener('DOMContentLoaded', add, { once: true });
  })();
  var RE = /alarm|noti|push|alim|bell|memo|recv|message|comment-write|ts_state|pwcheck|ajax\/access/i;
  // 댓글·글 등록 요청에 실린 Cloudflare 체크 상태만 뽑기 (비밀번호 등 다른 값은 안 뽑음)
  function tsSummary(body) {
    if (!body || body.indexOf('ts_state') < 0) return '';
    try {
      var q = new URLSearchParams(body);
      return '  <TS state=' + (q.get('ts_state') || '') +
        ' token=' + ((q.get('cf-turnstile-response') || '').length ? 'O' : 'X') +
        ' focus_ms=' + (q.get('ts_focus_ms') || '') + ' token_ms=' + (q.get('ts_token_ms') || '') + ' err=' + (q.get('ts_err') || '') + '>';
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
      var secret = /pwcheck/i.test(String(info.u));      // 비밀번호 확인 요청은 본문(비밀번호)을 기록하지 않음
      add('xhr', info.m, info.u + tsSummary(reqBody) + (reqBody && !secret ? '  <BODY ' + reqBody.slice(0, 200) + '>' : '') + (info.h ? '  <H' + info.h + '>' : ''), x.status, text);
      // 댓글 등록 결과 → content 스크립트(429 자동 재등록)로
      try {
        if (/\/ajax\/comment-write/.test(String(info.u))) {
          window.dispatchEvent(new CustomEvent('dcapp-cmtwrite', { detail: { status: x.status, body: reqBody, text: text } }));
        }
      } catch (e) {}
      // 댓글 목록을 다시 받음 → 429 자동 재등록이 목록 반영 뒤에 다음 누르기를 하도록
      try {
        if (/\/ajax\/response-comment/.test(String(info.u))) window.dispatchEvent(new CustomEvent('dcapp-cmtlist', { detail: { status: x.status } }));
      } catch (e) {}
      // 댓글 등록 요청이 끝남 → 댓글 쓰는 동안 꺼 둔 광고 차단을 다시 켜도록
      try {
        if (/\/ajax\/comment-write/.test(String(info.u))) {
          setTimeout(function () { window.webkit.messageHandlers.dcapp.postMessage({ type: 'cmtdone', status: x.status }); }, 0);
        }
      } catch (e) {}
      // 글 수정·삭제 비밀번호 확인이 429로 막히면 → 페이지 스크립트가 잠시 뒤 다시 시도
      try {
        if (x.status === 429 && /\/ajax\/pwcheck-board/.test(String(info.u))) window.dispatchEvent(new CustomEvent('dcapp-pw429'));
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
