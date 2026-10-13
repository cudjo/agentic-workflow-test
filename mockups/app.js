/* =========================================================================
   Мокап v1 — демонстрационный JS (минимальный, НЕ продуктовая логика).
   Нужен только чтобы на гейте 2 можно было «пощупать» состояния:
   переключение вида, фильтрация на статичных данных, диалоги, табы редактора.
   Продуктовая реализация будет другой (серверные запросы, debounce, санитайзер).
   ========================================================================= */
(function () {
  "use strict";

  var $  = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

  /* ---------------------------------------------------------------------
     Переключатель вида «Плитки / Список».
     Семантика: role="group" + кнопки с aria-pressed. В проде:
     выбранный вид сохраняется в localStorage (AC-24..AC-27, дефолт — плитки).
     --------------------------------------------------------------------- */
  function initViewToggle() {
    var group = $("[data-view-toggle]");
    var list = $("[data-notes-list]");
    if (!group || !list) return;

    function apply(view, focus) {
      $$("[data-view-btn]", group).forEach(function (btn) {
        var on = btn.getAttribute("data-view") === view;
        btn.setAttribute("aria-pressed", on ? "true" : "false");
        if (on && focus) btn.focus();
      });
      list.classList.toggle("results--grid", view === "grid");
      list.classList.toggle("results--list", view === "list");
      $$("[data-grid-only]", list).forEach(function (el) { el.hidden = view !== "grid"; });
      $$("[data-list-only]", list).forEach(function (el) { el.hidden = view !== "list"; });
      // В проде: localStorage.setItem("notes.view", view)
      var out = $("[data-view-status]");
      if (out) out.textContent = "Текущий вид: " + (view === "grid" ? "плитки" : "список");
    }

    group.addEventListener("click", function (e) {
      var btn = e.target.closest("[data-view-btn]");
      if (!btn) return;
      apply(btn.getAttribute("data-view"), false);
    });

    // Навигация стрелками внутри группы (NFR-15/16)
    group.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      var btns = $$("[data-view-btn]", group);
      var i = btns.indexOf(document.activeElement);
      if (i === -1) return;
      e.preventDefault();
      var next = e.key === "ArrowRight" ? (i + 1) % btns.length : (i - 1 + btns.length) % btns.length;
      btns[next].focus();
      themeToggleViewFrom(btns[next]);
    });
    function themeToggleViewFrom(btn) { apply(btn.getAttribute("data-view"), false); }

    apply(list.getAttribute("data-view") === "list" ? "list" : "grid", false);
  }

  /* ---------------------------------------------------------------------
     Поиск + фильтр по тегам на статичных демо-данных.
     Логика совпадения — И (AC-41). Пустой результат → empty-state (AC-42).
     В проде: серверный поиск, подстрочно, регистронезависимо (Q-S1/S2), debounce.
     --------------------------------------------------------------------- */
  function initSearchAndFilter() {
    var search = $("[data-search-input]");
    var clear  = $("[data-search-clear]");
    var chips  = $$("[data-tag-chip]");
    var cards  = $$("[data-note]");
    var status = $("[data-result-status]");
    var emptyNoResults = $("[data-empty-noresults]");
    var emptyNoNotes   = $("[data-empty-nonotes]");
    var resetAll = $$("[data-reset-filters]");
    var filterbarCount = $("[data-filter-count]");
    if (!cards.length) return;

    var activeTag = null;

    function norm(s) { return (s || "").toLowerCase().trim(); }

    function run() {
      var q = norm(search ? search.value : "");
      var shown = 0;

      cards.forEach(function (card) {
        var text = norm(card.getAttribute("data-text") || card.textContent);
        var tags = norm(card.getAttribute("data-tags"));
        var okQ = !q || text.indexOf(q) !== -1;
        var okT = !activeTag || tags.split(",").indexOf(norm(activeTag)) !== -1;
        var visible = okQ && okT;
        card.hidden = !visible;
        if (visible) shown++;
      });

      if (clear) clear.hidden = !q;
      if (status) {
        status.textContent = shown + " " + plural(shown, "заметка", "заметки", "заметок") +
          (q || activeTag ? " — по фильтру" : " — все заметки");
      }
      if (filterbarCount) {
        var n = activeTag ? 1 : 0;
        filterbarCount.textContent = n ? "Активен фильтр: " + activeTag : "Фильтры не применены";
      }

      var filtersActive = Boolean(q || activeTag);
      if (emptyNoResults) emptyNoResults.hidden = !(shown === 0 && filtersActive);
      if (emptyNoNotes) emptyNoNotes.hidden = shown !== 0 || filtersActive;
      // Прячем только сам список; блок с empty-state остаётся видимым
      var list = $("[data-notes-list]");
      if (list) list.hidden = shown === 0;
    }

    function plural(n, one, few, many) {
      var m10 = n % 10, m100 = n % 100;
      if (m10 === 1 && m100 !== 11) return one;
      if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
      return many;
    }

    if (search) search.addEventListener("input", run);
    if (clear) clear.addEventListener("click", function () { search.value = ""; search.focus(); run(); });

    chips.forEach(function (chip) {
      chip.addEventListener("click", function () {
        var tag = chip.getAttribute("data-tag-chip");
        var isOn = chip.getAttribute("aria-pressed") === "true";
        chips.forEach(function (c) { c.setAttribute("aria-pressed", "false"); });
        if (isOn) { activeTag = null; }
        else { chip.setAttribute("aria-pressed", "true"); activeTag = tag; }
        run();
      });
    });

    resetAll.forEach(function (btn) {
      btn.addEventListener("click", function () {
        if (search) search.value = "";
        activeTag = null;
        chips.forEach(function (c) { c.setAttribute("aria-pressed", "false"); });
        run();
        if (search) search.focus();
      });
    });

    run();
  }

  /* ------------------- Диалоги (подтверждение удаления) ----------------- */
  function initDialogs() {
    $$("[data-open-dialog]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var dlg = document.getElementById(btn.getAttribute("data-open-dialog"));
        if (dlg && typeof dlg.showModal === "function") dlg.showModal();
      });
    });
    $$("[data-close-dialog]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var dlg = btn.closest("dialog");
        if (dlg) dlg.close();
      });
    });
  }

  /* ------------- Табы «Редактор / Просмотр» на узких экранах -------------
     На широких экранах табы скрыты (display:none), режим не влияет:
     видны обе панели (live-сплит). */
  function initEditorTabs() {
    var group = $("[data-editor-tabs]");
    if (!group) return;
    var shell = group.closest(".editor-shell") || document.body;

    function show(which) {
      shell.setAttribute("data-editor-mode", which);
      $$("[data-editor-tab]", group).forEach(function (b) {
        var on = b.getAttribute("data-editor-tab") === which;
        b.setAttribute("aria-selected", on ? "true" : "false");
        b.setAttribute("tabindex", on ? "0" : "-1");
      });
    }

    group.addEventListener("click", function (e) {
      var b = e.target.closest("[data-editor-tab]");
      if (b) show(b.getAttribute("data-editor-tab"));
    });
    group.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      e.preventDefault();
      var current = document.activeElement.getAttribute("data-editor-tab");
      var next = $('[data-editor-tab="' + (current === "editor" ? "preview" : "editor") + '"]', group);
      if (next) { next.focus(); show(next.getAttribute("data-editor-tab")); }
    });
    show("editor");
  }

  /* ---------- Демонстрационные переключатели состояний экрана ----------- */
  function initStateSwitchers() {
    $$("[data-state-group]").forEach(function (group) {
      var targetSel = group.getAttribute("data-state-group");
      group.addEventListener("click", function (e) {
        var btn = e.target.closest("[data-set-state]");
        if (!btn) return;
        var state = btn.getAttribute("data-set-state");
        $$("[data-set-state]", group).forEach(function (b) {
          b.setAttribute("aria-pressed", b === btn ? "true" : "false");
        });
        $$(targetSel).forEach(function (el) {
          el.hidden = el.getAttribute("data-state") !== state;
        });
      });
    });
  }

  /* ---------- Демо: счётчик символов + имитация «есть несохранённое» ---- */
  function initEditorDemo() {
    var editor = $("[data-md-input]");
    var counter = $("[data-char-counter]");
    var dirty = $("[data-dirty-state]");
    var clean = $("[data-clean-state]");
    if (!editor) return;
    function render() {
      var isDirty = editor.value !== editor.getAttribute("data-initial");
      if (counter) counter.textContent = editor.value.length.toLocaleString("ru-RU") + " / 100 000";
      if (dirty) dirty.hidden = !isDirty;
      if (clean) clean.hidden = isDirty;
    }
    editor.addEventListener("input", render);
    render();
  }

  /* --------- Кнопки панели форматирования markdown (toolbar) -------------
     Демонстрационная вставка: wrap выделения, префикс строк, код-блок, ссылка.
     В продукте те же операции + отмена/повтор и горячие клавиши. */
  function initMarkdownToolbar() {
    var editor = $("[data-md-input]");
    if (!editor) return;

    /* fromMouse: при клике мышью возвращаем фокус в редактор, чтобы продолжать
       печатать; при активации с клавиатуры (Enter/Space на кнопке) фокус
       оставляем на кнопке — иначе ломается обход toolbar по Tab. */
    function commit(start, end, text, selFrom, selTo, fromMouse) {
      editor.setRangeText(text, start, end, "end");
      if (typeof selFrom === "number") editor.setSelectionRange(selFrom, selTo);
      if (fromMouse) editor.focus();
      editor.dispatchEvent(new Event("input"));
    }

    function lineBounds(value, start, end) {
      var from = value.lastIndexOf("\n", Math.max(start - 1, 0)) + 1;
      var to = value.indexOf("\n", end);
      if (to === -1) to = value.length;
      return [from, to];
    }

    function stripBlockMarker(line) {
      return line.replace(/^(\s*)(?:[-*+]\s+|\d+\.\s+|#{1,6}\s+|>\s+)?/, "$1");
    }

    // 1) Оборачивающие пары: **|**, *|*, `|`
    $$("[data-md-insert]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        var parts = btn.getAttribute("data-md-insert").split("|");
        var start = editor.selectionStart, end = editor.selectionEnd;
        var sel = editor.value.slice(start, end) || "текст";
        commit(start, end, parts[0] + sel + (parts[1] || ""),
               start + parts[0].length, start + parts[0].length + sel.length, e.detail > 0);
      });
    });

    // 2) Блочные префиксы: #, ##, ###, "- ", "1. ", "> "
    $$("[data-md-prefix]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        var prefix = btn.getAttribute("data-md-prefix");
        var numbered = /^\d+\.\s$/.test(prefix);
        var start = editor.selectionStart, end = editor.selectionEnd;
        var b = lineBounds(editor.value, start, end);
        var lines = editor.value.slice(b[0], b[1]).split("\n");
        var changed = lines.map(function (line, i) {
          return stripBlockMarker(line) + (numbered ? (i + 1) + ". " : prefix);
        }).join("\n");
        commit(b[0], b[1], changed, b[0], b[0] + changed.length, e.detail > 0);
      });
    });

    // 3) Блок кода: ``` с обеих сторон
    $$("[data-md-block]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        var fence = btn.getAttribute("data-md-block");
        var start = editor.selectionStart, end = editor.selectionEnd;
        var sel = editor.value.slice(start, end) || "код";
        var text = fence + "\n" + sel + "\n" + fence;
        commit(start, end, text, start + fence.length + 1, start + fence.length + 1 + sel.length, e.detail > 0);
      });
    });

    // 4) Ссылка: [текст](url)
    $$("[data-md-link]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        var start = editor.selectionStart, end = editor.selectionEnd;
        var sel = editor.value.slice(start, end) || "текст";
        var text = "[" + sel + "](https://)";
        commit(start, end, text, start + 1, start + 1 + sel.length, e.detail > 0);
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initViewToggle();
    initSearchAndFilter();
    initDialogs();
    initEditorTabs();
    initStateSwitchers();
    initEditorDemo();
    initMarkdownToolbar();
  });
})();
