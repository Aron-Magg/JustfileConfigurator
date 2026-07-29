/* JustfileConfigurator dashboard — renders entirely from window.PROJECT_DATA. */
(function () {
    "use strict";
    var D = window.PROJECT_DATA || {};
    var PLATFORMS = ["arch", "debian", "macos", "windows"];
    var PLATFORM_LABEL = { arch: "Arch", debian: "Debian", macos: "macOS", windows: "Windows" };

    function el(tag, attrs, kids) {
        var n = document.createElement(tag);
        if (attrs) Object.keys(attrs).forEach(function (k) {
            if (k === "class") n.className = attrs[k];
            else if (k === "text") n.textContent = attrs[k];
            else n.setAttribute(k, attrs[k]);
        });
        (kids || []).forEach(function (c) { n.appendChild(c); });
        return n;
    }
    function $(id) { return document.getElementById(id); }

    /* ---- Theme -------------------------------------------------------- */
    function initTheme() {
        var html = document.documentElement;
        var saved = localStorage.getItem("jfc-theme") || "auto";
        html.setAttribute("data-theme", saved);
        $("theme-toggle").addEventListener("click", function () {
            var order = ["auto", "light", "dark"];
            var cur = html.getAttribute("data-theme") || "auto";
            var next = order[(order.indexOf(cur) + 1) % order.length];
            html.setAttribute("data-theme", next);
            localStorage.setItem("jfc-theme", next);
            this.title = "Theme: " + next;
        });
    }

    /* ---- Commands ----------------------------------------------------- */
    var activeCats = { safe: true, modifying: true, confirm: true };
    function renderCommands() {
        var list = $("commands-list");
        var filters = $("cat-filters");
        ["safe", "modifying", "confirm"].forEach(function (cat) {
            var b = el("button", { "class": "chip-toggle", "aria-pressed": "true", type: "button" });
            b.innerHTML = '<span class="badge ' + cat + '">' + cat + "</span>";
            b.addEventListener("click", function () {
                activeCats[cat] = !activeCats[cat];
                b.setAttribute("aria-pressed", activeCats[cat] ? "true" : "false");
                applyCommandFilters();
            });
            filters.appendChild(b);
        });
        (D.commands || []).forEach(function (c) {
            var card = el("div", { "class": "card", "data-cat": c.category, "data-text": (c.command + " " + c.description + " " + c.module).toLowerCase() });
            var head = el("div", { "class": "card-head" }, [
                el("code", { text: "just " + c.command }),
                el("span", { "class": "badge " + c.category, text: c.category })
            ]);
            card.appendChild(head);
            card.appendChild(el("p", { text: c.description }));
            card.appendChild(el("div", { "class": "mod", text: "module: " + c.module }));
            list.appendChild(card);
        });
    }
    function applyCommandFilters() {
        var q = ($("search").value || "").toLowerCase().trim();
        Array.prototype.forEach.call(document.querySelectorAll(".card"), function (card) {
            var okCat = activeCats[card.getAttribute("data-cat")];
            var okText = !q || card.getAttribute("data-text").indexOf(q) !== -1;
            card.classList.toggle("hidden", !(okCat && okText));
        });
    }

    /* ---- Tree --------------------------------------------------------- */
    function buildTree(items) {
        var root = { name: "template", type: "dir", children: {} };
        (items || []).forEach(function (it) {
            var parts = it.path.split("/");
            var node = root;
            parts.forEach(function (part, i) {
                if (!node.children[part]) {
                    node.children[part] = { name: part, type: (i === parts.length - 1 ? it.type : "dir"), children: {} };
                }
                node = node.children[part];
            });
        });
        return root;
    }
    function renderTreeNode(node) {
        var keys = Object.keys(node.children).sort(function (a, b) {
            var da = node.children[a].type === "dir", db = node.children[b].type === "dir";
            if (da !== db) return da ? -1 : 1;
            return a.localeCompare(b);
        });
        var wrap = el("div", { "class": "tree-children" });
        keys.forEach(function (k) {
            var child = node.children[k];
            var isDir = child.type === "dir";
            var row = el("div", { "class": "tree-item " + (isDir ? "dir" : "file") });
            row.appendChild(el("span", { "class": "tw", text: isDir ? "▸" : "" }));
            row.appendChild(el("span", { "class": "ico", text: isDir ? "📁" : "📄" }));
            row.appendChild(el("span", { text: k + (isDir ? "/" : "") }));
            wrap.appendChild(row);
            if (isDir) {
                var sub = renderTreeNode(child);
                wrap.appendChild(sub);
                row.addEventListener("click", function () {
                    var col = sub.classList.toggle("collapsed");
                    row.querySelector(".tw").textContent = col ? "▸" : "▾";
                });
                row.querySelector(".tw").textContent = "▾";
            }
        });
        return wrap;
    }
    function renderTree() {
        var root = buildTree(D.tree);
        $("tree-view").appendChild(renderTreeNode(root));
    }

    /* ---- Matrix ------------------------------------------------------- */
    function renderMatrix() {
        var t = $("matrix-table");
        var head = el("tr", null, [el("th", { text: "Tool" }), el("th", { text: "Required" })]);
        PLATFORMS.forEach(function (p) { head.appendChild(el("th", { text: PLATFORM_LABEL[p] })); });
        t.appendChild(el("thead", null, [head]));
        var body = el("tbody");
        (D.tools || []).forEach(function (tool) {
            var tr = el("tr", null, [
                el("td", null, [el("code", { text: tool.command })]),
                el("td", { "class": "req-" + tool.required, text: tool.required })
            ]);
            PLATFORMS.forEach(function (p) {
                var applies = ("," + tool.platforms + ",").indexOf("," + p + ",") !== -1;
                tr.appendChild(el("td", { "class": applies ? "yes" : "no", text: applies ? "✓" : "—" }));
            });
            body.appendChild(tr);
        });
        t.appendChild(body);
    }

    /* ---- Packages ----------------------------------------------------- */
    function renderPackages() {
        var t = $("packages-table");
        var head = el("tr", null, [el("th", { text: "Tool" })]);
        PLATFORMS.forEach(function (p) { head.appendChild(el("th", { text: PLATFORM_LABEL[p] })); });
        head.appendChild(el("th", { text: "Description" }));
        t.appendChild(el("thead", null, [head]));
        var body = el("tbody");
        (D.tools || []).forEach(function (tool) {
            var tr = el("tr", null, [el("td", null, [el("code", { text: tool.command })])]);
            PLATFORMS.forEach(function (p) {
                var pkg = tool[p];
                var isPkg = pkg && pkg !== "-";
                tr.appendChild(el("td", { "class": isPkg ? "" : "no" }, [isPkg ? el("code", { text: pkg }) : el("span", { text: "—" })]));
            });
            tr.appendChild(el("td", { text: tool.description }));
            body.appendChild(tr);
        });
        t.appendChild(body);
    }

    /* ---- Rules / add-OS / env ---------------------------------------- */
    var ADD_OS_STEPS = [
        "Add a row to .just/manifests/platforms.tsv (keep the Arch → Debian → macOS → Windows order).",
        "Add a package column to .just/manifests/tools.tsv.",
        "Create .just/adapters/<os>.sh implementing pkg_mgr / pkg_check / pkg_install / pkg_install_cmd.",
        "Extend detect_platform() in .just/scripts/unix/lib.sh.",
        "Add [<os>] recipe variants wherever behaviour differs."
    ];
    function renderLists() {
        (D.rules || []).forEach(function (r) { $("rules-list").appendChild(el("li", { text: r })); });
        ADD_OS_STEPS.forEach(function (s) { $("addos-list").appendChild(el("li", { text: s })); });
        (D.env || []).forEach(function (v) { $("env-list").appendChild(el("li", { text: v })); });
    }

    /* ---- Boot --------------------------------------------------------- */
    function boot() {
        if (!window.PROJECT_DATA) {
            document.querySelector("main").innerHTML =
                '<div class="panel">project-data.js not found. Run <code>just docs-build</code>.</div>';
            return;
        }
        initTheme();
        renderCommands();
        renderTree();
        renderMatrix();
        renderPackages();
        renderLists();
        $("search").addEventListener("input", applyCommandFilters);
        $("foot-meta").textContent =
            (D.commands || []).length + " commands · " + (D.tools || []).length +
            " tools · " + (D.platforms || []).length + " platforms · generated by just docs-build";
    }
    document.addEventListener("DOMContentLoaded", boot);
})();
