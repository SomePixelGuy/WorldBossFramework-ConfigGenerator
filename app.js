(() => {
  "use strict";

  const data = window.WBF_DATA || { pals: [], items: [], activeSkills: [], passiveSkills: [] };
  const palIds = new Set(data.pals.map((entry) => entry.id.toLowerCase()));
  const itemIds = new Set(data.items.map((entry) => entry.id.toLowerCase()));
  const activeSkillIds = new Set(data.activeSkills.map((entry) => entry.id.toLowerCase()));
  const passiveSkillIds = new Set(data.passiveSkills.map((entry) => entry.id.toLowerCase()));

  const $ = (selector) => document.querySelector(selector);
  const listElement = $("#spawner-list");
  const formElement = $("#spawner-form");
  const outputElement = $("#config-output");
  const validationResults = $("#validation-results");
  const validationStatus = $("#validation-status");
  const downloadButton = $("#download");
  const toastElement = $("#toast");

  let nextUid = 1;
  let toastTimer = null;

  const uid = (prefix) => `${prefix}-${nextUid++}`;

  const defaultMember = (palId = "SheepBall") => ({
    uid: uid("member"),
    palId,
    level: 5,
    designation: "alpha",
    uncapturable: true,
    scale: 1.5,
    hpMultiplier: 1000,
    attackMultiplier: 1.5,
    defenseMultiplier: 20,
    activeSkills: ["HyperBeam", "PowerBall", "HolyBlast"],
    passiveSkills: ["WorldTree_ATK_DEF", "CoolTimeReduction_Up_1", "CoolTimeReduction_Up_2", "Deffence_up3"]
  });

  const emptyMember = () => ({
    uid: uid("member"),
    palId: "",
    level: 5,
    designation: "normal",
    uncapturable: true,
    scale: 1.5,
    hpMultiplier: 1,
    attackMultiplier: 1,
    defenseMultiplier: 1,
    activeSkills: ["", "", ""],
    passiveSkills: ["", "", "", ""]
  });

  const defaultReward = (kind = "item") => ({
    uid: uid("reward"),
    kind,
    item: kind === "item" ? "AncientCivilizationParts" : "",
    count: kind === "item" ? "5" : "250",
    chance: 1
  });

  function emptySpawner(id = "") {
    return {
      uid: uid("spawner"),
      id,
      enabled: true,
      title: "",
      firstDefeatTitle: "",
      autoEnabled: false,
      queueOrder: 1000,
      mapX: "",
      mapY: "",
      groundClearance: 100,
      rotationPitch: 0,
      rotationYaw: 0,
      rotationRoll: 0,
      matchRadius: 5000,
      respawnPlayerRadius: 15000,
      memberSpacing: 800,
      arenaRadius: 15000,
      blockBuilding: false,
      shopOfferEnabled: false,
      shopCurrencyCost: "",
      shopMaxPurchases: 0,
      shopCooldownSeconds: 0,
      shopResetSchedule: false,
      members: [],
      rewards: [],
      activeMemberUid: null,
      activeRewardUid: null
    };
  }

  function defaultSpawner(number = 1) {
    const spawner = emptySpawner(number === 1 ? "test_arena" : `world_boss_${number}`);
    const member = defaultMember();
    const itemReward = defaultReward("item");
    const currencyReward = defaultReward("currency");
    Object.assign(spawner, {
      title: number === 1 ? "The Woolen Calamity" : `World Boss ${number}`,
      autoEnabled: true,
      queueOrder: number * 10,
      mapX: number === 1 ? 95 : 0,
      mapY: number === 1 ? -520 : 0,
      shopCurrencyCost: 1000,
      members: [member],
      rewards: [itemReward, currencyReward],
      activeMemberUid: member.uid,
      activeRewardUid: itemReward.uid
    });
    return spawner;
  }

  const firstSpawner = defaultSpawner();
  const state = {
    spawners: [firstSpawner],
    selectedUid: firstSpawner.uid,
    expandedSpawnerUids: new Set([firstSpawner.uid]),
    activeSection: "basics",
    generatedText: "",
    dirty: true
  };

  const escapeHtml = (value) => String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");

  const selectedSpawner = () => state.spawners.find((spawner) => spawner.uid === state.selectedUid) || null;
  const valueAttr = (value) => escapeHtml(value ?? "");
  const copyIcon = () => `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="11" height="11" rx="2"></rect><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"></path></svg>`;

  function selectedMember(spawner) {
    let member = spawner.members.find((entry) => entry.uid === spawner.activeMemberUid);
    if (!member) {
      member = spawner.members[0] || null;
      spawner.activeMemberUid = member?.uid || null;
    }
    return member;
  }

  function selectedReward(spawner) {
    let reward = spawner.rewards.find((entry) => entry.uid === spawner.activeRewardUid);
    if (!reward) {
      reward = spawner.rewards[0] || null;
      spawner.activeRewardUid = reward?.uid || null;
    }
    return reward;
  }

  function showToast(message) {
    toastElement.textContent = message;
    toastElement.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastElement.classList.remove("show"), 2400);
  }

  function inputField(label, key, value, options = {}) {
    const {
      type = "text", min, max, step, placeholder = "", help = "", list = "",
      scope = "spawner", index = "", span = false, inputMode = ""
    } = options;
    const fieldId = `field-${scope}-${index === "" ? "root" : index}-${key}`;
    const attributes = [
      `id="${fieldId}"`, `type="${type}"`, `data-scope="${scope}"`, `data-key="${key}"`,
      `value="${valueAttr(value)}"`, `placeholder="${valueAttr(placeholder)}"`
    ];
    if (index !== "") attributes.push(`data-index="${index}"`);
    if (min !== undefined) attributes.push(`min="${min}"`);
    if (max !== undefined) attributes.push(`max="${max}"`);
    if (step !== undefined) attributes.push(`step="${step}"`);
    if (list) attributes.push(`list="${list}"`);
    if (inputMode) attributes.push(`inputmode="${inputMode}"`);
    return `<div class="field${span ? " field-span" : ""}">
      <label for="${fieldId}">${escapeHtml(label)}</label>
      <input ${attributes.join(" ")}>
      ${help ? `<small>${help}</small>` : ""}
    </div>`;
  }

  function selectField(label, key, value, choices, options = {}) {
    const { help = "", scope = "spawner", index = "", disabled = false } = options;
    const fieldId = `field-${scope}-${index === "" ? "root" : index}-${key}`;
    return `<div class="field">
      <label for="${fieldId}">${escapeHtml(label)}</label>
      <select id="${fieldId}" data-scope="${scope}" data-key="${key}"${index !== "" ? ` data-index="${index}"` : ""}${disabled ? " disabled" : ""}>
        ${choices.map(([choiceValue, choiceLabel]) => `<option value="${valueAttr(choiceValue)}"${String(value) === String(choiceValue) ? " selected" : ""}>${escapeHtml(choiceLabel)}</option>`).join("")}
      </select>
      ${help ? `<small>${help}</small>` : ""}
    </div>`;
  }

  function toggleRow(label, key, checked, description, options = {}) {
    const { scope = "spawner", index = "" } = options;
    return `<div class="toggle-row">
      <div class="toggle-copy"><strong>${escapeHtml(label)}</strong><span>${description}</span></div>
      <label class="switch">
        <input type="checkbox" data-scope="${scope}" data-key="${key}"${index !== "" ? ` data-index="${index}"` : ""}${checked ? " checked" : ""} aria-label="${escapeHtml(label)}">
        <span class="switch-track"></span>
      </label>
    </div>`;
  }

  function sectionCard(title, description, body, extraClass = "") {
    return `<section class="form-card ${extraClass}">
      <div class="card-heading"><div><h3>${escapeHtml(title)}</h3>${description ? `<p>${description}</p>` : ""}</div></div>
      ${body}
    </section>`;
  }

  function renderSidebar() {
    $("#spawner-count").textContent = state.spawners.length;
    if (!state.spawners.length) {
      listElement.innerHTML = `<div class="empty-collection">No spawners configured.</div>`;
      return;
    }
    listElement.innerHTML = state.spawners.map((spawner) => {
      const expanded = state.expandedSpawnerUids.has(spawner.uid);
      return `
      <article class="spawner-card${spawner.uid === state.selectedUid ? " selected" : ""}">
        <div class="spawner-actions">
          <button class="spawner-action spawner-duplicate" type="button" data-action="duplicate-spawner" data-uid="${spawner.uid}" aria-label="Duplicate ${escapeHtml(spawner.title || spawner.id || "spawner")}" title="Duplicate spawner">${copyIcon()}</button>
          <button class="spawner-action spawner-remove" type="button" data-action="remove-spawner" data-uid="${spawner.uid}" aria-label="Remove ${escapeHtml(spawner.title || spawner.id || "spawner")}" title="Remove spawner">×</button>
        </div>
        <button class="spawner-select" type="button" data-action="select-spawner" data-uid="${spawner.uid}">
          <strong>${escapeHtml(spawner.title || "Untitled spawner")}</strong>
          <small>${escapeHtml(spawner.id || "missing_id")}</small>
          <span class="spawner-meta">
            <span>${spawner.members.length} member${spawner.members.length === 1 ? "" : "s"}</span>
            <span>${spawner.rewards.length} reward${spawner.rewards.length === 1 ? "" : "s"}</span>
            ${spawner.enabled ? "" : `<span class="off">disabled</span>`}
          </span>
        </button>
        <div class="sidebar-member-dropdown${expanded ? " expanded" : ""}">
          <button class="sidebar-member-toggle" type="button" data-action="toggle-members" data-uid="${spawner.uid}" aria-expanded="${expanded}" aria-controls="member-list-${spawner.uid}">
            <span>Members</span>
            <span class="member-count">${spawner.members.length}</span>
            <span class="member-chevron" aria-hidden="true"></span>
          </button>
          <div class="sidebar-member-list" id="member-list-${spawner.uid}" role="list" aria-label="${escapeHtml(spawner.title || spawner.id || "Spawner")} members"${expanded ? "" : " hidden"}>
            ${spawner.members.length ? spawner.members.map((member, index) => `
            <div class="sidebar-member-row${member.uid === spawner.activeMemberUid ? " active" : ""}" role="listitem">
              <button class="sidebar-member-select" type="button" data-action="select-member" data-spawner-uid="${spawner.uid}" data-member-uid="${member.uid}">
                <span class="member-number">${index + 1}</span>
                <span class="member-name">${escapeHtml(member.palId || "Pal / NPC ID required")}</span>
                <span class="member-level">Lv. ${escapeHtml(member.level)}</span>
              </button>
              <div class="sidebar-member-actions">
                <button class="member-icon-button duplicate" type="button" data-action="duplicate-member" data-spawner-uid="${spawner.uid}" data-member-uid="${member.uid}" aria-label="Duplicate member ${index + 1}" title="Duplicate member">${copyIcon()}</button>
                <button class="member-icon-button remove" type="button" data-action="remove-member" data-spawner-uid="${spawner.uid}" data-member-uid="${member.uid}" aria-label="Remove member ${index + 1}" title="Remove member">×</button>
              </div>
            </div>`).join("") : `<div class="sidebar-member-empty">No members configured</div>`}
          </div>
        </div>
      </article>`;
    }).join("");
  }

  function renderEditor() {
    const spawner = selectedSpawner();
    $("#editor-empty").hidden = Boolean(spawner);
    $("#editor-shell").hidden = !spawner;
    if (!spawner) return;

    $("#selected-id-label").textContent = spawner.id || "Missing spawner ID";
    $("#selected-title").textContent = spawner.title || "Untitled spawner";
    $("#member-tab-count").textContent = spawner.members.length;
    $("#reward-tab-count").textContent = spawner.rewards.length;
    document.querySelectorAll("#section-tabs button").forEach((button) => {
      button.classList.toggle("active", button.dataset.section === state.activeSection);
      button.setAttribute("aria-current", button.dataset.section === state.activeSection ? "page" : "false");
    });
    renderForm(spawner);
  }

  function renderForm(spawner) {
    const renderers = {
      basics: renderBasics,
      location: renderLocation,
      arena: renderArena,
      members: renderMembers,
      rewards: renderRewards,
      shop: renderShop
    };
    formElement.innerHTML = `<div class="form-section">${renderers[state.activeSection](spawner)}</div>`;
  }

  function renderBasics(spawner) {
    return [
      sectionCard("Identity", "Used in commands, announcements, and the automatic encounter queue.", `
        <div class="field-grid">
          ${inputField("Spawner ID", "id", spawner.id, { help: "1–32 letters, numbers, underscores, or hyphens. Used by !worldboss summon.", placeholder: "frost_peak" })}
          ${inputField("Display title", "title", spawner.title, { help: "The boss name shown in server announcements.", placeholder: "The Frozen Tyrant" })}
          ${inputField("First-defeat title ID", "firstDefeatTitle", spawner.firstDefeatTitle, { span: true, help: "Optional PlayerTitleFramework title ID. Leave blank to grant no title.", placeholder: "world_boss_champion" })}
          ${inputField("Queue order", "queueOrder", spawner.queueOrder, { type: "number", min: 0, max: 1000000, step: 1, help: "Integer from 0 to 1,000,000." })}
        </div>`),
      sectionCard("Availability", "Choose whether this definition can load and enter the automatic queue.", `
        ${toggleRow("Spawner enabled", "enabled", spawner.enabled, "Disabled entries remain in the file but cannot be used.")}
        ${toggleRow("Automatic spawning", "autoEnabled", spawner.autoEnabled, "Adds this spawner to the controller's automatic encounter queue.")}
      `)
    ].join("");
  }

  function renderLocation(spawner) {
    const mapX = Number(spawner.mapX);
    const mapY = Number(spawner.mapY);
    const worldX = Number.isFinite(mapY) ? mapY * 459 - 123888 : null;
    const worldY = Number.isFinite(mapX) ? mapX * 459 + 158000 : null;
    const preview = worldX === null || worldY === null
      ? "Enter valid map coordinates to calculate the approximate world position."
      : `Approximate world position: X ${formatNumber(worldX)}, Y ${formatNumber(worldY)}. Terrain height is resolved at runtime.`;
    return [
      sectionCard("Map coordinates", "Use the coordinates shown by Palworld's in-game map overlay.", `
        <div class="field-grid">
          ${inputField("Map X", "mapX", spawner.mapX, { type: "number", min: -10000, max: 10000, step: "any", help: "Required value from −10,000 to 10,000." })}
          ${inputField("Map Y", "mapY", spawner.mapY, { type: "number", min: -10000, max: 10000, step: "any", help: "Required value from −10,000 to 10,000." })}
        </div>
        <div class="notice" id="world-coordinate-preview"><strong>Coordinate conversion:</strong> ${preview}</div>`, "coordinate-card"),
      sectionCard("Placement", "Fine-tune height and orientation at the resolved terrain position.", `
        <div class="field-grid">
          ${inputField("Ground clearance", "groundClearance", spawner.groundClearance, { type: "number", min: 10, max: 5000, step: "any", help: "Centimeters above terrain; 10–5,000." })}
        </div>
        <div class="field-grid three">
          ${inputField("Pitch", "rotationPitch", spawner.rotationPitch, { type: "number", min: -360, max: 360, step: "any", help: "Rotates forward/back around the Y axis." })}
          ${inputField("Yaw", "rotationYaw", spawner.rotationYaw, { type: "number", min: -360, max: 360, step: "any", help: "Rotates left/right around the vertical Z axis and rotates multi-member placement." })}
          ${inputField("Roll", "rotationRoll", spawner.rotationRoll, { type: "number", min: -360, max: 360, step: "any", help: "Rotates side-to-side around the X axis." })}
        </div>`)
    ].join("");
  }

  function renderArena(spawner) {
    return [
      sectionCard("Encounter ranges", "Distances are measured in Unreal centimeters.", `
        <div class="field-grid">
          ${inputField("Reward match radius (cm)", "matchRadius", spawner.matchRadius, { type: "number", min: 100, max: 20000, step: "any", help: "Players within this radius receive natural-defeat reward claims; 100–20,000 cm." })}
          ${inputField("Respawn player radius (cm)", "respawnPlayerRadius", spawner.respawnPlayerRadius, { type: "number", min: 1000, max: 100000, step: "any", help: "Players within this radius keep active bosses eligible for respawn checks; 1,000–100,000 cm." })}
          ${inputField("Arena radius (cm)", "arenaRadius", spawner.arenaRadius, { type: "number", min: 1000, max: 100000, step: "any", help: "Available radius for the encounter formation; 1,000–100,000 cm." })}
          ${inputField("Member spacing (cm)", "memberSpacing", spawner.memberSpacing, { type: "number", min: 100, max: 10000, step: "any", help: "Base spacing multiplied by the largest member scale; 100–10,000 cm." })}
        </div>`),
      sectionCard("Arena policy", "This property is accepted for forward compatibility.", `
        ${toggleRow("Block building", "blockBuilding", spawner.blockBuilding, "Currently suspended by WorldBossFramework; enabling it does not block construction in v0.7.1.")}
        <div class="notice"><strong>Current limitation:</strong> Native arena building restrictions remain disabled in the recovery build.</div>`)
    ].join("");
  }

  function memberNotice(member) {
    const special = specialId(member.palId);
    if (!special.preserved) return "";
    const skillNote = special.preserveSkills ? " RAID_ and GYM_ members also preserve native active skills." : "";
    return `<div class="notice"><strong>Special Pal ID:</strong> This designation is preserved, so Alpha and Predator are ignored.${skillNote}</div>`;
  }

  function renderMembers(spawner) {
    const member = selectedMember(spawner);
    const index = member ? spawner.members.indexOf(member) : -1;
    return `<div class="collection-toolbar">
      <p>Select a member from the encounter queue card to edit it here. Maximum 16.</p>
      <button class="button button-secondary button-small" type="button" data-action="add-member">Add Member</button>
    </div>
    ${member ? sectionCard(`Member ${index + 1}`, `${member.palId || "Pal / NPC ID required"} · Level ${member.level}`, `
      <div class="field-grid">
        ${inputField("Pal / NPC ID", "palId", member.palId, { scope: "member", index, list: "pal-options", help: "Exact character ID written to pal_id; 1–64 letters, numbers, underscores, dots, or hyphens." })}
        ${inputField("Level", "level", member.level, { scope: "member", index, type: "number", min: 1, max: 100, step: 1 })}
        ${selectField("Designation", "designation", member.designation, [["normal", "Normal"], ["alpha", "Alpha"], ["predator", "Predator"]], { scope: "member", index, help: "Alpha and Predator are mutually exclusive." })}
        ${inputField("Scale", "scale", member.scale, { scope: "member", index, type: "number", min: 0.1, max: 10, step: "any", help: "Model scale multiplier from 0.1 to 10." })}
      </div>
      ${toggleRow("Uncapturable", "uncapturable", member.uncapturable, "Prevents this member from being captured.", { scope: "member", index })}
      ${memberNotice(member)}
      <div class="field-grid three member-stat-grid">
        ${inputField("HP multiplier", "hpMultiplier", member.hpMultiplier, { scope: "member", index, type: "number", min: 0.01, max: 1000, step: "any" })}
        ${inputField("Attack multiplier", "attackMultiplier", member.attackMultiplier, { scope: "member", index, type: "number", min: 0.01, max: 1000, step: "any" })}
        ${inputField("Defense multiplier", "defenseMultiplier", member.defenseMultiplier, { scope: "member", index, type: "number", min: 0.01, max: 1000, step: "any", help: "2.0 means half incoming damage." })}
      </div>
      <div class="field-label member-skill-heading">Active skills</div>
      <div class="field-grid three">
        ${member.activeSkills.map((skill, slot) => inputField(`Slot ${slot + 1}`, `activeSkill${slot}`, skill, { scope: "member", index, list: "active-skill-options", placeholder: "Optional" })).join("")}
      </div>
      <div class="field-label member-skill-heading">Passive skills</div>
      <div class="field-grid">
        ${member.passiveSkills.map((skill, slot) => inputField(`Slot ${slot + 1}`, `passiveSkill${slot}`, skill, { scope: "member", index, list: "passive-skill-options", placeholder: "Optional" })).join("")}
      </div>`, "member-editor-card") : `<div class="empty-collection">Add a member from this tab. At least one member is required for an enabled spawner.</div>`}`;
  }

  function renderRewards(spawner) {
    selectedReward(spawner);
    const rows = spawner.rewards.map((reward, index) => `
      <tr class="${reward.uid === spawner.activeRewardUid ? "selected" : ""}" data-action="select-reward" data-reward-uid="${reward.uid}">
        <th scope="row"><span class="reward-number">${index + 1}</span></th>
        <td>
          <label class="sr-only" for="reward-kind-${index}">Reward ${index + 1} type</label>
          <select id="reward-kind-${index}" data-scope="reward" data-key="kind" data-index="${index}">
            <option value="item"${reward.kind === "item" ? " selected" : ""}>Item</option>
            <option value="currency"${reward.kind === "currency" ? " selected" : ""}>Shop currency</option>
          </select>
        </td>
        <td>
          <label class="sr-only" for="reward-item-${index}">Reward ${index + 1} item ID</label>
          ${reward.kind === "item"
            ? `<input id="reward-item-${index}" type="text" data-scope="reward" data-key="item" data-index="${index}" value="${valueAttr(reward.item)}" list="item-options" placeholder="Item ID">`
            : `<input id="reward-item-${index}" type="text" value="ServerShopFramework" disabled aria-label="Currency provider">`}
        </td>
        <td>
          <label class="sr-only" for="reward-count-${index}">Reward ${index + 1} count</label>
          <input id="reward-count-${index}" type="number" min="1" step="1" data-scope="reward" data-key="count" data-index="${index}" value="${valueAttr(reward.count)}">
        </td>
        <td>
          <label class="sr-only" for="reward-chance-${index}">Reward ${index + 1} drop chance</label>
          <input id="reward-chance-${index}" type="number" min="0" max="1" step="0.01" data-scope="reward" data-key="chance" data-index="${index}" value="${valueAttr(reward.chance)}">
        </td>
      </tr>`).join("");
    return `<div class="collection-toolbar">
      <p>Rewards generate contiguous indices from 1 to ${spawner.rewards.length}. Maximum 64.</p>
      <div class="collection-actions">
        <button class="button button-secondary button-small" type="button" data-action="add-reward">Add Reward</button>
        <button class="button button-secondary button-small" type="button" data-action="duplicate-reward"${spawner.activeRewardUid ? "" : " disabled"}>Duplicate Reward</button>
        <button class="button button-danger button-small" type="button" data-action="remove-reward"${spawner.activeRewardUid ? "" : " disabled"}>Remove Reward</button>
      </div>
    </div>
    ${rows ? `<div class="reward-sheet-wrap"><table class="reward-sheet">
      <thead><tr><th>#</th><th>Reward type</th><th>Item ID / provider</th><th>Count</th><th>Drop chance</th></tr></thead>
      <tbody>${rows}</tbody>
    </table></div>
    <p class="table-help">Drop chance ranges from 0.00 to 1.00 and is rolled once per eligible player.</p>` : `<div class="empty-collection">No defeat rewards configured. This is valid.</div>`}`;
  }

  function renderShop(spawner) {
    return [
      sectionCard("Early summon offer", "Optionally contribute a virtual-currency offer to ServerShopFramework.", `
        ${toggleRow("Enable shop offer", "shopOfferEnabled", spawner.shopOfferEnabled, `Creates the offer ID worldboss_${escapeHtml(spawner.id || "<spawner_id>")}.`)}
        <div class="field-grid">
          ${inputField("Currency cost", "shopCurrencyCost", spawner.shopCurrencyCost, { type: "number", min: 1, max: 9000000000000, step: 1, help: "Required when the offer is enabled; 1–9,000,000,000,000." })}
          ${inputField("Maximum purchases", "shopMaxPurchases", spawner.shopMaxPurchases, { type: "number", min: 0, max: 1000000, step: 1, help: "0 means unlimited; otherwise 1–1,000,000." })}
          ${inputField("Cooldown in seconds", "shopCooldownSeconds", spawner.shopCooldownSeconds, { type: "number", min: 0, max: 31536000, step: 1, help: "0 disables cooldown; maximum one year." })}
        </div>
        ${toggleRow("Reset automatic schedule", "shopResetSchedule", spawner.shopResetSchedule, "After the summoned boss is defeated, start a full interval instead of resuming the paused countdown.")}
        <div class="notice"><strong>Dependency:</strong> Shop offers require ServerShopFramework API 1. Failed summons use its virtual-currency refund path.</div>`)
    ].join("");
  }

  function specialId(value) {
    const match = String(value || "").match(/^([^_]+)_/);
    if (!match) return { preserved: false, preserveSkills: false };
    const prefix = match[1];
    const upper = prefix.toUpperCase();
    const known = new Set(["BOSS", "RAID", "GYM", "PREDATOR", "SUMMON", "POLICE"]);
    return {
      preserved: known.has(upper) || /^[A-Z][A-Z0-9]*$/.test(prefix),
      preserveSkills: upper === "RAID" || upper === "GYM"
    };
  }

  function markDirty() {
    state.dirty = true;
    downloadButton.disabled = true;
    const saveState = $("#save-state");
    saveState.classList.remove("current");
    saveState.innerHTML = `<span></span> ${state.generatedText ? "Changes not generated" : "Not generated"}`;
    if (state.generatedText) {
      validationStatus.textContent = "Out of date";
      validationStatus.className = "status-chip status-stale";
    }
  }

  function updateValue(target) {
    const spawner = selectedSpawner();
    if (!spawner || !target.dataset.scope || !target.dataset.key) return;
    const value = target.type === "checkbox" ? target.checked : target.value;
    const index = Number(target.dataset.index);
    if (target.dataset.scope === "spawner") {
      spawner[target.dataset.key] = value;
    } else if (target.dataset.scope === "member" && spawner.members[index]) {
      const member = spawner.members[index];
      const activeMatch = target.dataset.key.match(/^activeSkill(\d)$/);
      const passiveMatch = target.dataset.key.match(/^passiveSkill(\d)$/);
      if (activeMatch) member.activeSkills[Number(activeMatch[1])] = value;
      else if (passiveMatch) member.passiveSkills[Number(passiveMatch[1])] = value;
      else member[target.dataset.key] = value;
    } else if (target.dataset.scope === "reward" && spawner.rewards[index]) {
      const reward = spawner.rewards[index];
      reward[target.dataset.key] = value;
      if (target.dataset.key === "kind" && value === "currency") reward.item = "";
    }
    markDirty();
    updateVisibleLabels();
  }

  function updateVisibleLabels() {
    const spawner = selectedSpawner();
    if (!spawner) return;
    $("#selected-id-label").textContent = spawner.id || "Missing spawner ID";
    $("#selected-title").textContent = spawner.title || "Untitled spawner";
    renderSidebar();
    spawner.members.forEach((member, index) => {
      const label = document.querySelector(`[data-member-summary="${index}"]`);
      if (label) label.textContent = `${member.palId || "Pal ID required"} · Level ${member.level}`;
    });
    spawner.rewards.forEach((reward, index) => {
      const label = document.querySelector(`[data-reward-summary="${index}"]`);
      if (label) label.textContent = reward.kind === "currency"
        ? `${reward.count} shop currency`
        : `${reward.count} × ${reward.item || "Item ID required"}`;
    });
    if (state.activeSection === "location") {
      const mapX = Number(spawner.mapX);
      const mapY = Number(spawner.mapY);
      const preview = $("#world-coordinate-preview");
      if (preview) {
        preview.innerHTML = Number.isFinite(mapX) && Number.isFinite(mapY)
          ? `<strong>Coordinate conversion:</strong> Approximate world position: X ${formatNumber(mapY * 459 - 123888)}, Y ${formatNumber(mapX * 459 + 158000)}. Terrain height is resolved at runtime.`
          : `<strong>Coordinate conversion:</strong> Enter valid map coordinates to calculate the approximate world position.`;
      }
    }
  }

  function addSpawner() {
    let number = state.spawners.length + 1;
    const existing = new Set(state.spawners.map((spawner) => spawner.id.toLowerCase()));
    while (existing.has(`world_boss_${number}`)) number += 1;
    const spawner = defaultSpawner(number);
    state.spawners.push(spawner);
    state.selectedUid = spawner.uid;
    state.expandedSpawnerUids.add(spawner.uid);
    state.activeSection = "basics";
    markDirty();
    render();
    setTimeout(() => formElement.querySelector('[data-key="id"]')?.focus(), 0);
  }

  function removeSpawner(spawnerUid) {
    const spawner = state.spawners.find((entry) => entry.uid === spawnerUid);
    if (!spawner) return;
    if (!window.confirm(`Remove “${spawner.title || spawner.id || "this spawner"}”?`)) return;
    const oldIndex = state.spawners.indexOf(spawner);
    state.spawners.splice(oldIndex, 1);
    state.expandedSpawnerUids.delete(spawnerUid);
    if (state.selectedUid === spawnerUid) {
      state.selectedUid = state.spawners[Math.min(oldIndex, state.spawners.length - 1)]?.uid || null;
    }
    markDirty();
    render();
  }

  function duplicateSpawnerId(sourceId) {
    const existing = new Set(state.spawners.map((spawner) => String(spawner.id || "").toLowerCase()));
    const base = String(sourceId || "world_boss")
      .replace(/[^A-Za-z0-9_-]/g, "_")
      .replace(/^_+|_+$/g, "") || "world_boss";
    for (let copyNumber = 1; ; copyNumber += 1) {
      const suffix = copyNumber === 1 ? "_copy" : `_copy_${copyNumber}`;
      const candidate = `${base.slice(0, Math.max(1, 32 - suffix.length))}${suffix}`;
      if (!existing.has(candidate.toLowerCase())) return candidate;
    }
  }

  function duplicateSpawner(spawnerUid) {
    const sourceIndex = state.spawners.findIndex((spawner) => spawner.uid === spawnerUid);
    if (sourceIndex < 0) return;
    const source = state.spawners[sourceIndex];
    const memberUidMap = new Map();
    const rewardUidMap = new Map();
    const members = source.members.map((member) => {
      const duplicateUid = uid("member");
      memberUidMap.set(member.uid, duplicateUid);
      return {
        ...member,
        uid: duplicateUid,
        activeSkills: [...member.activeSkills],
        passiveSkills: [...member.passiveSkills]
      };
    });
    const rewards = source.rewards.map((reward) => {
      const duplicateUid = uid("reward");
      rewardUidMap.set(reward.uid, duplicateUid);
      return { ...reward, uid: duplicateUid };
    });
    const duplicate = {
      ...source,
      uid: uid("spawner"),
      id: duplicateSpawnerId(source.id),
      members,
      rewards,
      activeMemberUid: memberUidMap.get(source.activeMemberUid) || members[0]?.uid || null,
      activeRewardUid: rewardUidMap.get(source.activeRewardUid) || rewards[0]?.uid || null
    };
    state.spawners.splice(sourceIndex + 1, 0, duplicate);
    state.selectedUid = duplicate.uid;
    state.expandedSpawnerUids.add(duplicate.uid);
    markDirty();
    render();
    showToast(`Spawner duplicated as ${duplicate.id}.`);
  }

  function findSpawner(spawnerUid) {
    return state.spawners.find((spawner) => spawner.uid === spawnerUid) || null;
  }

  function selectMember(spawnerUid, memberUid) {
    const spawner = findSpawner(spawnerUid);
    if (!spawner || !spawner.members.some((member) => member.uid === memberUid)) return;
    state.selectedUid = spawner.uid;
    state.expandedSpawnerUids.add(spawner.uid);
    spawner.activeMemberUid = memberUid;
    state.activeSection = "members";
    render();
  }

  function duplicateMember(spawnerUid, memberUid) {
    const spawner = findSpawner(spawnerUid);
    const sourceIndex = spawner?.members.findIndex((member) => member.uid === memberUid) ?? -1;
    if (!spawner || sourceIndex < 0) return;
    if (spawner.members.length >= 16) return showToast("A spawner can contain at most 16 members.");
    const source = spawner.members[sourceIndex];
    const duplicate = {
      ...source,
      uid: uid("member"),
      activeSkills: [...source.activeSkills],
      passiveSkills: [...source.passiveSkills]
    };
    spawner.members.splice(sourceIndex + 1, 0, duplicate);
    state.selectedUid = spawner.uid;
    state.expandedSpawnerUids.add(spawner.uid);
    spawner.activeMemberUid = duplicate.uid;
    state.activeSection = "members";
    markDirty();
    render();
    showToast("Member duplicated.");
  }

  function removeMember(spawnerUid, memberUid) {
    const spawner = findSpawner(spawnerUid);
    const memberIndex = spawner?.members.findIndex((member) => member.uid === memberUid) ?? -1;
    if (!spawner || memberIndex < 0) return;
    spawner.members.splice(memberIndex, 1);
    if (spawner.activeMemberUid === memberUid) {
      spawner.activeMemberUid = spawner.members[Math.min(memberIndex, spawner.members.length - 1)]?.uid || null;
    }
    state.selectedUid = spawner.uid;
    markDirty();
    render();
  }

  function handleAction(action) {
    const spawner = selectedSpawner();
    if (!spawner) return;
    if (action === "add-member") {
      if (spawner.members.length >= 16) return showToast("A spawner can contain at most 16 members.");
      const member = defaultMember("");
      member.designation = "normal";
      member.hpMultiplier = 1;
      member.attackMultiplier = 1;
      member.defenseMultiplier = 1;
      member.activeSkills = ["", "", ""];
      member.passiveSkills = ["", "", "", ""];
      spawner.members.push(member);
      spawner.activeMemberUid = member.uid;
    } else if (action === "add-reward") {
      if (spawner.rewards.length >= 64) return showToast("A spawner can contain at most 64 rewards.");
      const reward = defaultReward("item");
      spawner.rewards.push(reward);
      spawner.activeRewardUid = reward.uid;
    } else if (action === "duplicate-reward") {
      const index = spawner.rewards.findIndex((reward) => reward.uid === spawner.activeRewardUid);
      if (index < 0) return showToast("Select a reward row to duplicate.");
      if (spawner.rewards.length >= 64) return showToast("A spawner can contain at most 64 rewards.");
      const reward = { ...spawner.rewards[index], uid: uid("reward") };
      spawner.rewards.splice(index + 1, 0, reward);
      spawner.activeRewardUid = reward.uid;
      showToast("Reward duplicated.");
    } else if (action === "remove-reward") {
      const index = spawner.rewards.findIndex((reward) => reward.uid === spawner.activeRewardUid);
      if (index < 0) return showToast("Select a reward row to remove.");
      spawner.rewards.splice(index, 1);
      spawner.activeRewardUid = spawner.rewards[Math.min(index, spawner.rewards.length - 1)]?.uid || null;
    }
    markDirty();
    renderEditor();
    renderSidebar();
  }

  const spawnerLoadFields = {
    enabled: ["enabled", "boolean"],
    title: ["title", "value"],
    first_defeat_title: ["firstDefeatTitle", "value"],
    auto_enabled: ["autoEnabled", "boolean"],
    queue_order: ["queueOrder", "value"],
    map_x: ["mapX", "value"],
    map_y: ["mapY", "value"],
    ground_clearance: ["groundClearance", "value"],
    rotation_pitch: ["rotationPitch", "value"],
    rotation_yaw: ["rotationYaw", "value"],
    rotation_roll: ["rotationRoll", "value"],
    match_radius: ["matchRadius", "value"],
    respawn_player_radius: ["respawnPlayerRadius", "value"],
    member_spacing: ["memberSpacing", "value"],
    arena_radius: ["arenaRadius", "value"],
    block_building: ["blockBuilding", "boolean"],
    shop_offer_enabled: ["shopOfferEnabled", "boolean"],
    shop_currency_cost: ["shopCurrencyCost", "value"],
    shop_max_purchases: ["shopMaxPurchases", "value"],
    shop_cooldown_seconds: ["shopCooldownSeconds", "value"],
    shop_reset_schedule: ["shopResetSchedule", "boolean"]
  };

  const memberLoadFields = {
    pal_id: ["palId", "value"],
    level: ["level", "value"],
    alpha: ["_alpha", "boolean"],
    predator: ["_predator", "boolean"],
    uncapturable: ["uncapturable", "boolean"],
    scale: ["scale", "value"],
    hp_multiplier: ["hpMultiplier", "value"],
    attack_multiplier: ["attackMultiplier", "value"],
    defense_multiplier: ["defenseMultiplier", "value"],
    active_skill_1: ["activeSkills", "value", 0],
    active_skill_2: ["activeSkills", "value", 1],
    active_skill_3: ["activeSkills", "value", 2],
    passive_skill_1: ["passiveSkills", "value", 0],
    passive_skill_2: ["passiveSkills", "value", 1],
    passive_skill_3: ["passiveSkills", "value", 2],
    passive_skill_4: ["passiveSkills", "value", 3]
  };

  const rewardLoadFields = {
    kind: ["kind", "value"],
    item: ["item", "value"],
    count: ["count", "value"],
    chance: ["chance", "value"]
  };

  function stripConfigComment(line) {
    let quote = "";
    let escaped = false;
    for (let index = 0; index < line.length; index += 1) {
      const character = line[index];
      if (escaped) {
        escaped = false;
      } else if (quote && character === "\\") {
        escaped = true;
      } else if (quote) {
        if (character === quote) quote = "";
      } else if (character === '"' || character === "'") {
        quote = character;
      } else if ((character === ";" || character === "#") && (index === 0 || /\s/.test(line[index - 1]))) {
        return line.slice(0, index);
      }
    }
    return line;
  }

  function parseLoadedValue(raw, lineNumber, errors) {
    const value = String(raw ?? "").trim();
    const quote = value[0];
    if (quote === '"' || quote === "'") {
      if (value.length < 2 || value.at(-1) !== quote) {
        errors.push(`Line ${lineNumber}: quoted value is not closed.`);
        return "";
      }
      const body = value.slice(1, -1);
      let decoded = "";
      for (let index = 0; index < body.length; index += 1) {
        const character = body[index];
        if (character !== "\\" || index === body.length - 1) {
          decoded += character;
          continue;
        }
        const escaped = body[index + 1];
        const replacements = { n: "\n", r: "\r", t: "\t", "\\": "\\", '"': '"', "'": "'" };
        decoded += Object.prototype.hasOwnProperty.call(replacements, escaped) ? replacements[escaped] : escaped;
        index += 1;
      }
      return decoded;
    }
    if (value === "true") return true;
    if (value === "false") return false;
    const numeric = Number(value);
    return value !== "" && Number.isFinite(numeric) ? numeric : value;
  }

  function assignLoadedField(target, descriptor, value, key, lineNumber, errors) {
    const [property, kind, slot] = descriptor;
    if (kind === "boolean" && typeof value !== "boolean") {
      errors.push(`Line ${lineNumber}: ${key} must be true or false.`);
      return;
    }
    if (slot !== undefined) target[property][slot] = value;
    else target[property] = value;
  }

  function parseSpawnerConfig(text) {
    const spawners = new Map();
    const seenKeys = new Set();
    const errors = [];

    String(text).replace(/^\uFEFF/, "").split(/\r?\n/).forEach((sourceLine, lineIndex) => {
      const lineNumber = lineIndex + 1;
      const line = stripConfigComment(sourceLine).trim();
      if (!line) return;
      const separator = line.indexOf("=");
      if (separator < 1) {
        errors.push(`Line ${lineNumber}: expected a key followed by = and a value.`);
        return;
      }
      const key = line.slice(0, separator).trim();
      const rawValue = line.slice(separator + 1).trim();
      const rootMatch = key.match(/^spawners\.([A-Za-z0-9_-]{1,32})\.(.+)$/);
      if (!rootMatch) {
        errors.push(`Line ${lineNumber}: “${key}” is not a supported spawner key.`);
        return;
      }
      const duplicateKey = key.toLowerCase();
      if (seenKeys.has(duplicateKey)) {
        errors.push(`Line ${lineNumber}: duplicate key “${key}”.`);
        return;
      }
      seenKeys.add(duplicateKey);

      const [, spawnerId, remainder] = rootMatch;
      if (!spawners.has(spawnerId)) spawners.set(spawnerId, emptySpawner(spawnerId));
      const spawner = spawners.get(spawnerId);
      const value = parseLoadedValue(rawValue, lineNumber, errors);
      const rewardMatch = remainder.match(/^reward\.([1-9][0-9]*)\.([A-Za-z0-9_]+)$/);
      if (rewardMatch) {
        const index = Number(rewardMatch[1]);
        const descriptor = rewardLoadFields[rewardMatch[2]];
        if (index > 64) errors.push(`Line ${lineNumber}: reward index must be between 1 and 64.`);
        else if (!descriptor) errors.push(`Line ${lineNumber}: unsupported reward field “${rewardMatch[2]}”.`);
        else {
          while (spawner.rewards.length < index) spawner.rewards.push({ uid: uid("reward"), kind: "item", item: "", count: 1, chance: 1 });
          assignLoadedField(spawner.rewards[index - 1], descriptor, value, key, lineNumber, errors);
        }
        return;
      }

      const memberMatch = remainder.match(/^([A-Za-z0-9_]+)\.([1-9][0-9]*)$/);
      if (memberMatch) {
        const index = Number(memberMatch[2]);
        const descriptor = memberLoadFields[memberMatch[1]];
        if (index > 16) errors.push(`Line ${lineNumber}: member index must be between 1 and 16.`);
        else if (!descriptor) errors.push(`Line ${lineNumber}: unsupported indexed field “${memberMatch[1]}”.`);
        else {
          while (spawner.members.length < index) spawner.members.push(emptyMember());
          assignLoadedField(spawner.members[index - 1], descriptor, value, key, lineNumber, errors);
        }
        return;
      }

      const descriptor = spawnerLoadFields[remainder];
      if (!descriptor) {
        errors.push(`Line ${lineNumber}: unsupported spawner field “${remainder}”.`);
        return;
      }
      assignLoadedField(spawner, descriptor, value, key, lineNumber, errors);
    });

    const loaded = [...spawners.values()];
    loaded.forEach((spawner) => {
      spawner.members.forEach((member, index) => {
        if (member._alpha === true && member._predator === true) {
          errors.push(`Spawner ${spawner.id}, member ${index + 1}: Alpha and Predator cannot both be true.`);
        }
        member.designation = member._predator === true ? "predator" : member._alpha === true ? "alpha" : "normal";
        delete member._alpha;
        delete member._predator;
      });
      spawner.rewards.forEach((reward, index) => {
        reward.kind = String(reward.kind || "item").toLowerCase();
        if (reward.kind === "currency" && String(reward.item || "").trim()) {
          errors.push(`Spawner ${spawner.id}, reward ${index + 1}: item is not used for currency rewards.`);
        }
      });
      spawner.activeMemberUid = spawner.members[0]?.uid || null;
      spawner.activeRewardUid = spawner.rewards[0]?.uid || null;
    });
    if (!loaded.length) errors.push("The file does not contain any spawners.* properties.");
    return { spawners: loaded, errors };
  }

  function showLoadErrors(errors) {
    validationResults.className = "validation-results errors";
    validationStatus.textContent = "Load failed";
    validationStatus.className = "status-chip status-error";
    validationResults.innerHTML = `<strong>The file was not loaded.</strong><ul>${errors.slice(0, 8).map((error) => `<li>${escapeHtml(error)}</li>`).join("")}</ul>${errors.length > 8 ? `<p>Plus ${errors.length - 8} more errors.</p>` : ""}`;
    showToast("The selected file could not be loaded.");
  }

  async function loadConfigFile(file) {
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      showLoadErrors(["The selected file is larger than the 2 MB import limit."]);
      return;
    }
    let text;
    try {
      text = await file.text();
    } catch (_error) {
      showLoadErrors(["The selected file could not be read as text."]);
      return;
    }
    const loaded = parseSpawnerConfig(text);
    if (loaded.errors.length) {
      showLoadErrors(loaded.errors);
      return;
    }

    state.spawners = loaded.spawners;
    state.selectedUid = state.spawners[0]?.uid || null;
    state.expandedSpawnerUids = new Set(state.selectedUid ? [state.selectedUid] : []);
    state.activeSection = "basics";
    state.generatedText = "";
    state.dirty = true;
    outputElement.value = "";
    downloadButton.disabled = true;
    render();
    const validation = validateAll();
    $("#save-state").classList.remove("current");
    $("#save-state").innerHTML = `<span></span> Loaded, not generated`;
    validationResults.className = `validation-results${validation.errors.length ? " errors" : validation.warnings.length ? " warnings" : ""}`;
    validationStatus.textContent = validation.errors.length ? "Loaded with errors" : validation.warnings.length ? "Loaded with notes" : "Loaded";
    validationStatus.className = `status-chip ${validation.errors.length ? "status-error" : validation.warnings.length ? "status-stale" : "status-valid"}`;
    const notes = [...validation.errors, ...validation.warnings];
    validationResults.innerHTML = `<strong>Loaded ${state.spawners.length} spawner${state.spawners.length === 1 ? "" : "s"} from ${escapeHtml(file.name)}.</strong>${notes.length ? `<ul>${notes.slice(0, 6).map((note) => `<li>${escapeHtml(note)}</li>`).join("")}</ul>${notes.length > 6 ? `<p>Plus ${notes.length - 6} more notices.</p>` : ""}` : "<p>Review the imported values, then generate the configuration.</p>"}`;
    showToast(`Loaded ${state.spawners.length} spawner${state.spawners.length === 1 ? "" : "s"}.`);
  }

  function validateAll() {
    const errors = [];
    const warnings = [];
    const ids = new Map();
    const enabledCount = state.spawners.filter((spawner) => spawner.enabled === true).length;
    if (!state.spawners.length) errors.push("Add at least one spawner.");
    if (state.spawners.length && enabledCount === 0) errors.push("At least one spawner must be enabled.");

    const number = (value, label, min, max, integer = false) => {
      if (String(value ?? "").trim() === "") {
        errors.push(`${label} is required.`);
        return null;
      }
      const parsed = Number(value);
      if (!Number.isFinite(parsed) || parsed < min || parsed > max || (integer && !Number.isInteger(parsed))) {
        errors.push(`${label} must be ${integer ? "a whole number " : ""}between ${formatNumber(min)} and ${formatNumber(max)}.`);
        return null;
      }
      return parsed;
    };

    state.spawners.forEach((spawner, spawnerIndex) => {
      const prefix = `Spawner ${spawnerIndex + 1}`;
      const id = String(spawner.id || "").trim();
      if (!/^[A-Za-z0-9_-]{1,32}$/.test(id)) errors.push(`${prefix}: Spawner ID must contain 1–32 letters, numbers, underscores, or hyphens.`);
      const lowered = id.toLowerCase();
      if (lowered && ids.has(lowered)) errors.push(`${prefix}: Spawner ID duplicates ${ids.get(lowered)} when case is ignored.`);
      else if (lowered) ids.set(lowered, prefix);
      const title = String(spawner.title || "").trim();
      if (!title || new TextEncoder().encode(title).length > 128 || /[\u0000-\u001f\u007f]/.test(title)) errors.push(`${prefix}: Display title must contain 1–128 UTF-8 bytes and no control characters.`);
      const firstTitle = String(spawner.firstDefeatTitle || "").trim();
      if (firstTitle && !/^[A-Za-z0-9_.-]{1,96}$/.test(firstTitle)) errors.push(`${prefix}: First-defeat title ID is invalid.`);
      if (firstTitle) warnings.push(`${prefix}: First-defeat title rewards require PlayerTitleFramework.`);

      number(spawner.queueOrder, `${prefix}: Queue order`, 0, 1000000, true);
      number(spawner.mapX, `${prefix}: Map X`, -10000, 10000);
      number(spawner.mapY, `${prefix}: Map Y`, -10000, 10000);
      number(spawner.groundClearance, `${prefix}: Ground clearance`, 10, 5000);
      number(spawner.rotationPitch, `${prefix}: Rotation pitch`, -360, 360);
      number(spawner.rotationYaw, `${prefix}: Rotation yaw`, -360, 360);
      number(spawner.rotationRoll, `${prefix}: Rotation roll`, -360, 360);
      number(spawner.matchRadius, `${prefix}: Match radius`, 100, 20000);
      const respawnRadius = number(spawner.respawnPlayerRadius, `${prefix}: Respawn player radius`, 1000, 100000);
      const spacing = number(spawner.memberSpacing, `${prefix}: Member spacing`, 100, 10000);
      const arenaRadius = number(spawner.arenaRadius, `${prefix}: Arena radius`, 1000, 100000);
      number(spawner.shopMaxPurchases, `${prefix}: Shop maximum purchases`, 0, 1000000, true);
      number(spawner.shopCooldownSeconds, `${prefix}: Shop cooldown`, 0, 31536000, true);
      if (spawner.shopOfferEnabled) {
        number(spawner.shopCurrencyCost, `${prefix}: Shop currency cost`, 1, 9000000000000, true);
        warnings.push(`${prefix}: Early-summon offers require ServerShopFramework API 1.`);
      } else if (String(spawner.shopCurrencyCost).trim() !== "") {
        number(spawner.shopCurrencyCost, `${prefix}: Shop currency cost`, 1, 9000000000000, true);
      }
      if (spawner.blockBuilding) warnings.push(`${prefix}: Block building is accepted but inactive in WorldBossFramework v0.7.1.`);

      if (!spawner.members.length) errors.push(`${prefix}: At least one member is required.`);
      if (spawner.members.length > 16) errors.push(`${prefix}: No more than 16 members are allowed.`);
      let largestScale = 1;
      spawner.members.forEach((member, memberIndex) => {
        const memberPrefix = `${prefix}, member ${memberIndex + 1}`;
        const palId = String(member.palId || "").trim();
        if (!/^[A-Za-z0-9_.-]{1,64}$/.test(palId)) errors.push(`${memberPrefix}: Pal ID is invalid.`);
        else if (!palIds.has(palId.toLowerCase())) warnings.push(`${memberPrefix}: Character ID was not found in the bundled Pal/NPC database; verify it before use.`);
        const special = specialId(palId);
        if (special.preserved && member.designation !== "normal") warnings.push(`${memberPrefix}: Special IDs ignore Alpha and Predator settings.`);
        if (special.preserveSkills && member.activeSkills.some((skill) => String(skill).trim())) warnings.push(`${memberPrefix}: RAID_ and GYM_ IDs preserve native active skills; configured active skills are ignored.`);
        number(member.level, `${memberPrefix}: Level`, 1, 100, true);
        const scale = number(member.scale, `${memberPrefix}: Scale`, 0.1, 10);
        if (scale !== null) largestScale = Math.max(largestScale, scale);
        number(member.hpMultiplier, `${memberPrefix}: HP multiplier`, 0.01, 1000);
        number(member.attackMultiplier, `${memberPrefix}: Attack multiplier`, 0.01, 1000);
        number(member.defenseMultiplier, `${memberPrefix}: Defense multiplier`, 0.01, 1000);

        member.activeSkills.forEach((rawSkill, slot) => {
          const skill = String(rawSkill || "").trim();
          if (!skill) return;
          if (!/^[A-Za-z0-9_]{1,96}$/.test(skill)) errors.push(`${memberPrefix}: Active skill slot ${slot + 1} is invalid.`);
          else {
            const numericSkill = /^[0-9]+$/.test(skill) ? Number(skill) : null;
            const numericValid = numericSkill !== null && Number.isInteger(numericSkill) && numericSkill >= 0 && numericSkill <= data.activeSkills.length;
            if (!numericValid && !activeSkillIds.has(skill.toLowerCase())) errors.push(`${memberPrefix}: Active skill “${skill}” is not supported by the bundled WorldBossFramework skill table.`);
          }
        });
        member.passiveSkills.forEach((rawSkill, slot) => {
          const skill = String(rawSkill || "").trim();
          if (!skill) return;
          if (!/^[A-Za-z0-9_]{1,96}$/.test(skill)) errors.push(`${memberPrefix}: Passive skill slot ${slot + 1} is invalid.`);
          else if (!passiveSkillIds.has(skill.toLowerCase())) warnings.push(`${memberPrefix}: Passive skill “${skill}” was not found in the bundled database; verify it before use.`);
        });
      });

      if (spacing !== null && arenaRadius !== null && respawnRadius !== null && spawner.members.length) {
        const effectiveSpacing = spacing * largestScale;
        const count = spawner.members.length;
        const radius = count > 1 ? effectiveSpacing / (2 * Math.sin(Math.PI / count)) : 0;
        if (radius + effectiveSpacing * 0.5 > Math.min(arenaRadius, respawnRadius)) {
          errors.push(`${prefix}: Member formation exceeds the arena or respawn radius; reduce spacing/scale or enlarge both radii.`);
        }
      }

      if (spawner.rewards.length > 64) errors.push(`${prefix}: No more than 64 rewards are allowed.`);
      let hasCurrencyReward = false;
      spawner.rewards.forEach((reward, rewardIndex) => {
        const rewardPrefix = `${prefix}, reward ${rewardIndex + 1}`;
        if (reward.kind !== "item" && reward.kind !== "currency") errors.push(`${rewardPrefix}: Reward type must be item or currency.`);
        const countText = String(reward.count ?? "").trim();
        if (!/^[0-9]+$/.test(countText) || BigInt(countText || "0") < 1n) errors.push(`${rewardPrefix}: Count must be a positive whole number.`);
        number(reward.chance, `${rewardPrefix}: Drop chance`, 0, 1);
        if (reward.kind === "item") {
          const item = String(reward.item || "").trim();
          if (!/^[A-Za-z0-9_]{1,128}$/.test(item)) errors.push(`${rewardPrefix}: Item ID is required and must contain only letters, numbers, or underscores.`);
          else if (!itemIds.has(item.toLowerCase())) warnings.push(`${rewardPrefix}: Item ID was not found in the bundled item database; verify it before use.`);
        } else {
          if (String(reward.item || "").trim()) errors.push(`${rewardPrefix}: Item ID is not used for currency rewards.`);
          hasCurrencyReward = true;
        }
      });
      if (hasCurrencyReward) warnings.push(`${prefix}: Currency rewards require ServerShopFramework API 1 when claimed.`);
    });

    return { errors, warnings };
  }

  function formatNumber(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return String(value);
    if (Number.isInteger(number)) return String(number);
    return number.toFixed(9).replace(/0+$/, "").replace(/\.$/, "");
  }

  function formatFloat(value) {
    const normalized = formatNumber(value);
    return normalized.includes(".") ? normalized : `${normalized}.0`;
  }

  function quoteConfig(value) {
    return `"${String(value ?? "")
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\n/g, "\\n")
      .replace(/\r/g, "\\r")
      .replace(/\t/g, "\\t")}"`;
  }

  function renderConfig() {
    const lines = [
      "; WorldBossFramework v0.7.1 spawner definitions",
      "; Generated by World Boss Config Generator",
      "; Changes take effect after a full server restart.",
      ""
    ];
    state.spawners.forEach((spawner, spawnerIndex) => {
      const root = `spawners.${String(spawner.id).trim()}`;
      if (spawnerIndex > 0) lines.push("");
      lines.push(`; ${String(spawner.title).trim()}`);
      lines.push(`${root}.enabled = ${spawner.enabled ? "true" : "false"}`);
      lines.push(`${root}.title = ${quoteConfig(String(spawner.title).trim())}`);
      lines.push(`${root}.auto_enabled = ${spawner.autoEnabled ? "true" : "false"}`);
      lines.push(`${root}.queue_order = ${formatNumber(spawner.queueOrder)}`);
      lines.push(`${root}.map_x = ${formatNumber(spawner.mapX)}`);
      lines.push(`${root}.map_y = ${formatNumber(spawner.mapY)}`);
      lines.push(`${root}.ground_clearance = ${formatNumber(spawner.groundClearance)}`);
      lines.push(`${root}.rotation_pitch = ${formatNumber(spawner.rotationPitch)}`);
      lines.push(`${root}.rotation_yaw = ${formatNumber(spawner.rotationYaw)}`);
      lines.push(`${root}.rotation_roll = ${formatNumber(spawner.rotationRoll)}`);
      lines.push(`${root}.match_radius = ${formatNumber(spawner.matchRadius)}`);
      lines.push(`${root}.respawn_player_radius = ${formatNumber(spawner.respawnPlayerRadius)}`);
      const firstTitle = String(spawner.firstDefeatTitle || "").trim();
      if (firstTitle) lines.push(`${root}.first_defeat_title = ${firstTitle}`);
      lines.push(`${root}.arena_radius = ${formatNumber(spawner.arenaRadius)}`);
      lines.push(`${root}.block_building = ${spawner.blockBuilding ? "true" : "false"}`);
      lines.push(`${root}.member_spacing = ${formatNumber(spawner.memberSpacing)}`);
      lines.push(`${root}.shop_offer_enabled = ${spawner.shopOfferEnabled ? "true" : "false"}`);
      if (String(spawner.shopCurrencyCost).trim()) lines.push(`${root}.shop_currency_cost = ${formatNumber(spawner.shopCurrencyCost)}`);
      lines.push(`${root}.shop_max_purchases = ${formatNumber(spawner.shopMaxPurchases)}`);
      lines.push(`${root}.shop_cooldown_seconds = ${formatNumber(spawner.shopCooldownSeconds)}`);
      lines.push(`${root}.shop_reset_schedule = ${spawner.shopResetSchedule ? "true" : "false"}`);

      spawner.members.forEach((member, index) => {
        const memberIndex = index + 1;
        lines.push("");
        lines.push(`${root}.pal_id.${memberIndex} = ${String(member.palId).trim()}`);
        lines.push(`${root}.level.${memberIndex} = ${formatNumber(member.level)}`);
        lines.push(`${root}.scale.${memberIndex} = ${formatFloat(member.scale)}`);
        lines.push(`${root}.alpha.${memberIndex} = ${member.designation === "alpha" ? "true" : "false"}`);
        lines.push(`${root}.predator.${memberIndex} = ${member.designation === "predator" ? "true" : "false"}`);
        lines.push(`${root}.uncapturable.${memberIndex} = ${member.uncapturable ? "true" : "false"}`);
        lines.push(`${root}.hp_multiplier.${memberIndex} = ${formatFloat(member.hpMultiplier)}`);
        lines.push(`${root}.attack_multiplier.${memberIndex} = ${formatFloat(member.attackMultiplier)}`);
        lines.push(`${root}.defense_multiplier.${memberIndex} = ${formatFloat(member.defenseMultiplier)}`);
        member.activeSkills.forEach((skill, slot) => {
          const value = String(skill || "").trim();
          if (value) lines.push(`${root}.active_skill_${slot + 1}.${memberIndex} = ${value}`);
        });
        member.passiveSkills.forEach((skill, slot) => {
          const value = String(skill || "").trim();
          if (value) lines.push(`${root}.passive_skill_${slot + 1}.${memberIndex} = ${value}`);
        });
      });

      spawner.rewards.forEach((reward, index) => {
        const rewardRoot = `${root}.reward.${index + 1}`;
        lines.push("");
        lines.push(`${rewardRoot}.kind = ${reward.kind}`);
        if (reward.kind === "item") lines.push(`${rewardRoot}.item = ${String(reward.item).trim()}`);
        lines.push(`${rewardRoot}.count = ${BigInt(String(reward.count).trim()).toString()}`);
        lines.push(`${rewardRoot}.chance = ${formatFloat(reward.chance)}`);
      });
    });
    return `${lines.join("\n")}\n`;
  }

  function generateConfig() {
    const result = validateAll();
    validationResults.className = "validation-results";
    if (result.errors.length) {
      state.generatedText = "";
      state.dirty = true;
      outputElement.value = "";
      downloadButton.disabled = true;
      validationStatus.textContent = `${result.errors.length} error${result.errors.length === 1 ? "" : "s"}`;
      validationStatus.className = "status-chip status-error";
      validationResults.classList.add("errors");
      validationResults.innerHTML = `<strong>Configuration not generated.</strong><ul>${result.errors.slice(0, 8).map((error) => `<li>${escapeHtml(error)}</li>`).join("")}</ul>${result.errors.length > 8 ? `<p>Plus ${result.errors.length - 8} more errors.</p>` : ""}`;
      $("#save-state").classList.remove("current");
      $("#save-state").innerHTML = `<span></span> Fix validation errors`;
      showToast("Fix the listed errors before downloading.");
      return;
    }

    state.generatedText = renderConfig();
    state.dirty = false;
    outputElement.value = state.generatedText;
    downloadButton.disabled = false;
    validationStatus.textContent = result.warnings.length ? "Valid with notes" : "Valid";
    validationStatus.className = "status-chip status-valid";
    const enabled = state.spawners.filter((spawner) => spawner.enabled).length;
    if (result.warnings.length) {
      validationResults.classList.add("warnings");
      validationResults.innerHTML = `<strong>Valid: ${enabled} enabled spawner${enabled === 1 ? "" : "s"}.</strong><ul>${result.warnings.slice(0, 5).map((warning) => `<li>${escapeHtml(warning)}</li>`).join("")}</ul>${result.warnings.length > 5 ? `<p>Plus ${result.warnings.length - 5} more notices.</p>` : ""}`;
    } else {
      validationResults.innerHTML = `<p><strong>Valid:</strong> ${enabled} enabled spawner${enabled === 1 ? "" : "s"}, ${state.spawners.reduce((sum, spawner) => sum + spawner.members.length, 0)} members, and ${state.spawners.reduce((sum, spawner) => sum + spawner.rewards.length, 0)} rewards.</p>`;
    }
    $("#save-state").classList.add("current");
    $("#save-state").innerHTML = `<span></span> Generated output is current`;
    showToast("Valid spawners.config generated.");
  }

  function downloadConfig() {
    if (!state.generatedText || state.dirty) return;
    const blob = new Blob([state.generatedText], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "spawners.config";
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function populateList(id, entries) {
    const datalist = document.getElementById(id);
    const fragment = document.createDocumentFragment();
    entries.forEach((entry) => {
      const option = document.createElement("option");
      option.value = entry.id;
      option.label = entry.name ? `${entry.name} — ${entry.id}` : entry.id;
      fragment.appendChild(option);
    });
    datalist.appendChild(fragment);
  }

  function render() {
    renderSidebar();
    renderEditor();
  }

  listElement.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    const action = button.dataset.action;
    if (action === "select-spawner") {
      state.selectedUid = button.dataset.uid;
      state.expandedSpawnerUids.add(button.dataset.uid);
      render();
    } else if (action === "toggle-members") {
      const spawnerUid = button.dataset.uid;
      if (state.expandedSpawnerUids.has(spawnerUid)) state.expandedSpawnerUids.delete(spawnerUid);
      else state.expandedSpawnerUids.add(spawnerUid);
      renderSidebar();
    } else if (action === "remove-spawner") {
      removeSpawner(button.dataset.uid);
    } else if (action === "duplicate-spawner") {
      duplicateSpawner(button.dataset.uid);
    } else if (action === "select-member") {
      selectMember(button.dataset.spawnerUid, button.dataset.memberUid);
    } else if (action === "duplicate-member") {
      duplicateMember(button.dataset.spawnerUid, button.dataset.memberUid);
    } else if (action === "remove-member") {
      removeMember(button.dataset.spawnerUid, button.dataset.memberUid);
    }
  });

  $("#section-tabs").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-section]");
    if (!button) return;
    state.activeSection = button.dataset.section;
    renderEditor();
  });

  formElement.addEventListener("input", (event) => updateValue(event.target));
  formElement.addEventListener("focusin", (event) => {
    const rewardRow = event.target.closest?.('tr[data-action="select-reward"]');
    const spawner = selectedSpawner();
    if (!rewardRow || !spawner) return;
    spawner.activeRewardUid = rewardRow.dataset.rewardUid;
    formElement.querySelectorAll('tr[data-action="select-reward"]').forEach((row) => row.classList.toggle("selected", row === rewardRow));
  });
  formElement.addEventListener("change", (event) => {
    updateValue(event.target);
    if (event.target.dataset.key === "kind" || event.target.dataset.key === "palId") renderEditor();
  });
  formElement.addEventListener("click", (event) => {
    const rewardRow = event.target.closest('tr[data-action="select-reward"]');
    if (rewardRow) {
      const spawner = selectedSpawner();
      if (spawner) {
        spawner.activeRewardUid = rewardRow.dataset.rewardUid;
        formElement.querySelectorAll('tr[data-action="select-reward"]').forEach((row) => row.classList.toggle("selected", row === rewardRow));
        formElement.querySelector('button[data-action="remove-reward"]')?.removeAttribute("disabled");
      }
    }
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    event.preventDefault();
    handleAction(button.dataset.action);
  });

  $("#add-spawner").addEventListener("click", addSpawner);
  $("#add-empty").addEventListener("click", addSpawner);
  $("#load-config").addEventListener("click", () => $("#config-file").click());
  $("#config-file").addEventListener("change", async (event) => {
    const file = event.target.files?.[0] || null;
    event.target.value = "";
    await loadConfigFile(file);
  });
  $("#generate").addEventListener("click", generateConfig);
  $("#generate-top").addEventListener("click", generateConfig);
  downloadButton.addEventListener("click", downloadConfig);

  populateList("pal-options", data.pals);
  populateList("item-options", data.items);
  populateList("active-skill-options", data.activeSkills);
  populateList("passive-skill-options", data.passiveSkills);
  render();
})();
