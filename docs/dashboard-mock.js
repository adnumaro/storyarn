// ============================================================
// Storyarn Dashboard Mock — "The Crimson Accord" (Narrative RPG)
// Copy-paste into browser console
// ============================================================

(function () {
  // --- 1. STAT CARDS ---
  var stats = [
    { value: "147", label: "Sheets" },
    { value: "1,204", label: "Variables" },
    { value: "83", label: "Flows" },
    { value: "2,847", label: "Dialogue Lines" },
    { value: "24", label: "Scenes" },
    { value: "68,312", label: "Words" }
  ];

  var cards = document.querySelectorAll(".card.bg-base-200\\/50");
  for (var i = 0; i < cards.length; i++) {
    if (stats[i]) {
      cards[i].querySelector(".text-2xl").textContent = stats[i].value;
    }
  }

  // --- 2. NODE DISTRIBUTION ---
  var nodes = [
    { label: "Dialogue", value: 1842 },
    { label: "Condition", value: 634 },
    { label: "Instruction", value: 412 },
    { label: "Hub", value: 187 },
    { label: "Jump", value: 156 },
    { label: "Entry", value: 83 },
    { label: "Exit", value: 83 },
    { label: "Slug Line", value: 72 },
    { label: "Subflow", value: 38 }
  ];

  var maxNode = 1842;
  var sections = document.querySelectorAll("section.card");

  var nodeDist = sections[0];
  if (nodeDist) {
    var html = "";
    for (var j = 0; j < nodes.length; j++) {
      var n = nodes[j];
      var pct = Math.round((n.value / maxNode) * 100);
      html += '<div class="flex items-center gap-3 py-1.5">';
      html += '<div class="flex-1 min-w-0"><span class="text-sm truncate block">' + n.label + "</span></div>";
      html += '<div class="w-32 flex items-center gap-2">';
      html += '<div class="flex-1 bg-base-300 rounded-full h-2">';
      html += '<div class="bg-primary rounded-full h-2 transition-all" style="width: ' + pct + '%"></div>';
      html += "</div>";
      html += '<span class="text-xs text-base-content/60 w-8 text-right tabular-nums">' + n.value.toLocaleString() + "</span>";
      html += "</div></div>";
    }
    nodeDist.querySelector(".space-y-1").innerHTML = html;
  }

  // --- 3. TOP SPEAKERS ---
  var speakers = [
    { name: "Elara Nightwhisper", value: 487 },
    { name: "Commander Aldric", value: 341 },
    { name: "Thorne Blackwood", value: 298 },
    { name: "Sera (Narrator)", value: 264 },
    { name: "Kael the Wanderer", value: 189 },
    { name: "High Priestess Yara", value: 156 },
    { name: "Merchant Fynn", value: 112 }
  ];

  var maxSpeaker = 487;
  var topSpeakers = sections[1];
  if (topSpeakers) {
    var shtml = "";
    for (var k = 0; k < speakers.length; k++) {
      var s = speakers[k];
      var spct = Math.round((s.value / maxSpeaker) * 100);
      shtml += '<div class="flex items-center gap-3 py-1.5">';
      shtml += '<div class="flex-1 min-w-0"><a class="text-sm hover:underline truncate block">' + s.name + "</a></div>";
      shtml += '<div class="w-32 flex items-center gap-2">';
      shtml += '<div class="flex-1 bg-base-300 rounded-full h-2">';
      shtml += '<div class="bg-primary rounded-full h-2 transition-all" style="width: ' + spct + '%"></div>';
      shtml += "</div>";
      shtml += '<span class="text-xs text-base-content/60 w-8 text-right tabular-nums">' + s.value + "</span>";
      shtml += "</div></div>";
    }
    topSpeakers.querySelector(".space-y-1").innerHTML = shtml;
  }

  // --- 4. ISSUES & WARNINGS ---
  var arrowSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="size-4 text-base-content/30 group-hover:text-base-content/60 transition-colors"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>';

  var issues = [
    { badge: "badge-error", label: "Error", msg: "Flow \"Siege of Ashenmoor\" has unreachable nodes after condition branch" },
    { badge: "badge-error", label: "Error", msg: "Flow \"The Betrayal\" has 2 disconnected node(s)" },
    { badge: "badge-warning", label: "Warning", msg: "Flow \"Tavern Encounter\" has 4 disconnected node(s)" },
    { badge: "badge-warning", label: "Warning", msg: "Flow \"Final Confrontation\" references deleted variable mc.aldric.loyalty" },
    { badge: "badge-warning", label: "Warning", msg: "Japanese: 1,204 text(s) pending translation (12% done)" },
    { badge: "badge-warning", label: "Warning", msg: "Korean: 2,847 text(s) pending translation (0% done)" },
    { badge: "badge-info", label: "Info", msg: "12 sheet(s) have no blocks defined" },
    { badge: "badge-info", label: "Info", msg: "3 flow(s) have no dialogue nodes" }
  ];

  var issueSection = sections[2];
  if (issueSection) {
    var ihtml = "";
    for (var m = 0; m < issues.length; m++) {
      var iss = issues[m];
      ihtml += '<a class="flex items-center gap-3 py-2 px-3 rounded-lg hover:bg-base-200 transition-colors group cursor-pointer">';
      ihtml += '<span class="badge badge-sm ' + iss.badge + '">' + iss.label + "</span>";
      ihtml += '<span class="text-sm flex-1">' + iss.msg + "</span>";
      ihtml += arrowSvg;
      ihtml += "</a>";
    }
    issueSection.querySelector(".space-y-1").innerHTML = ihtml;
  }

  // --- 5. LOCALIZATION PROGRESS ---
  var languages = [
    { name: "Spanish", pct: 100, detail: "2,847 / 2,847" },
    { name: "French", pct: 94, detail: "2,676 / 2,847" },
    { name: "German", pct: 87, detail: "2,477 / 2,847" },
    { name: "Japanese", pct: 12, detail: "342 / 2,847" },
    { name: "Korean", pct: 0, detail: "0 / 2,847" }
  ];

  var locSection = sections[3];
  if (locSection) {
    var lhtml = "";
    for (var p = 0; p < languages.length; p++) {
      var l = languages[p];
      var colorClass = l.pct === 100 ? "bg-success" : (l.pct >= 50 ? "bg-primary" : "bg-warning");
      lhtml += '<div class="flex items-center gap-3 py-1.5">';
      lhtml += '<div class="w-24"><a class="text-sm hover:underline">' + l.name + "</a></div>";
      lhtml += '<div class="flex-1 bg-base-300 rounded-full h-2.5">';
      lhtml += '<div class="' + colorClass + ' rounded-full h-2.5 transition-all" style="width: ' + l.pct + '%"></div>';
      lhtml += "</div>";
      lhtml += '<span class="text-xs text-base-content/60 w-12 text-right tabular-nums">' + l.pct + "%</span>";
      lhtml += '<span class="text-xs text-base-content/40 w-24 text-right">' + l.detail + "</span>";
      lhtml += "</div>";
    }
    locSection.querySelector(".space-y-1").innerHTML = lhtml;
  }

  // --- 6. RECENT ACTIVITY ---
  var iconSvgs = {
    "git-branch": '<line x1="6" x2="6" y1="3" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>',
    "file-text": '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>',
    "map": '<path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3z"/><path d="M9 3v15"/><path d="M15 6v15"/>',
    "scroll-text": '<path d="M15 12h-5"/><path d="M15 8h-5"/><path d="M19 17V5a2 2 0 0 0-2-2H4"/><path d="M8 21h12a2 2 0 0 0 2-2v-1a1 1 0 0 0-1-1H11a1 1 0 0 0-1 1v1a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v2"/>'
  };

  var activity = [
    { icon: "git-branch", name: "Final Confrontation", type: "Flow", time: "3m ago" },
    { icon: "git-branch", name: "The Betrayal", type: "Flow", time: "18m ago" },
    { icon: "file-text", name: "MC.Elara", type: "Sheet", time: "1h ago" },
    { icon: "file-text", name: "MC.Aldric", type: "Sheet", time: "1h ago" },
    { icon: "map", name: "Ashenmoor Castle", type: "Scene", time: "3h ago" },
    { icon: "scroll-text", name: "Act III \u2014 The Siege", type: "Screenplay", time: "5h ago" },
    { icon: "git-branch", name: "Siege of Ashenmoor", type: "Flow", time: "5h ago" },
    { icon: "map", name: "Crimson Forest", type: "Scene", time: "1d ago" },
    { icon: "file-text", name: "NPC.Merchant Fynn", type: "Sheet", time: "1d ago" },
    { icon: "git-branch", name: "Tavern Encounter", type: "Flow", time: "2d ago" },
    { icon: "file-text", name: "Items.Weapons", type: "Sheet", time: "2d ago" },
    { icon: "map", name: "The Sunken Temple", type: "Scene", time: "3d ago" }
  ];

  var activitySection = sections[4];
  if (activitySection) {
    var existing = activitySection.querySelectorAll(".flex.items-center.gap-3.py-2");
    for (var r = 0; r < existing.length; r++) { existing[r].remove(); }
    var emptyState = activitySection.querySelector(".text-center");
    if (emptyState) { emptyState.remove(); }

    var ahtml = "";
    for (var q = 0; q < activity.length; q++) {
      var a = activity[q];
      var paths = iconSvgs[a.icon] || "";
      ahtml += '<div class="flex items-center gap-3 py-2">';
      ahtml += '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="size-4 text-base-content/40">' + paths + "</svg>";
      ahtml += '<span class="text-sm flex-1"><span class="font-medium">' + a.name + '</span> <span class="text-base-content/50">\u00b7 ' + a.type + "</span></span>";
      ahtml += '<span class="text-xs text-base-content/40">' + a.time + "</span>";
      ahtml += "</div>";
    }

    var wrapper = document.createElement("div");
    wrapper.innerHTML = ahtml;
    while (wrapper.firstChild) {
      activitySection.appendChild(wrapper.firstChild);
    }
  }

  console.log("Done - The Crimson Accord");
})();
