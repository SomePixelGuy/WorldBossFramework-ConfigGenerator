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

  const defaultReward = (kind = "item") => ({
    uid: uid("reward"),
    kind,
    item: kind === "item" ? "AncientCivilizationParts" : "",
    count: kind === "item" ? "5" : "250",
    chance: 1
  });

  const defaultSpawner = (number = 1) => ({
    uid: uid("spawner"),
    id: number === 1 ? "test_arena" : `world_boss_${number}`,
    enabled: true,
    title: number === 1 ? "The Woolen Calamity" : `World Boss ${number}`,
    firstDefeatTitle: "",
    autoEnabled: true,
    queueOrder: number * 10,
    mapX: number === 1 ? 95 : 0,
    mapY: number === 1 ? -520 : 0,
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
    shopCurrencyCost: 1000,
    shopMaxPurchases: 0,
    shopCooldownSeconds: 0,
    shopResetSchedule: false,
    members: [defaultMember()],
    rewards: [defaultReward("item"), defaultReward("currency")]
  });

  const firstSpawner = defaultSpawner();
  const state = {
    spawners: [firstSpawner],
    selectedUid: firstSpawner.uid,
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
    listElement.innerHTML = state.spawners.map((spawner) => `
      <div class="spawner-row${spawner.uid === state.selectedUid ? " selected" : ""}">
        <button class="spawner-select" type="button" data-action="select-spawner" data-uid="${spawner.uid}">
          <strong>${escapeHtml(spawner.title || "Untitled spawner")}</strong>
          <small>${escapeHtml(spawner.id || "missing_id")}</small>
          <span class="spawner-meta">
            <span>${spawner.members.length} pal${spawner.members.length === 1 ? "" : "s"}</span>
            <span>${spawner.rewards.length} reward${spawner.rewards.length === 1 ? "" : "s"}</span>
            ${spawner.enabled ? "" : `<span class="off">disabled</span>`}
          </span>
        </button>
        <button class="remove-button" type="button" data-action="remove-spawner" data-uid="${spawner.uid}" aria-label="Remove ${escapeHtml(spawner.title || spawner.id || "spawner")}" title="Remove spawner">×</button>
      </div>`).join("");
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
          ${inputField("Pitch", "rotationPitch", spawner.rotationPitch, { type: "number", min: -360, max: 360, step: "any" })}
          ${inputField("Yaw", "rotationYaw", spawner.rotationYaw, { type: "number", min: -360, max: 360, step: "any", help: "Also rotates multi-member placement." })}
          ${inputField("Roll", "rotationRoll", spawner.rotationRoll, { type: "number", min: -360, max: 360, step: "any" })}
        </div>`)
    ].join("");
  }

  function renderArena(spawner) {
    return [
      sectionCard("Encounter ranges", "Distances are measured in Unreal centimeters.", `
        <div class="field-grid">
          ${inputField("Reward match radius", "matchRadius", spawner.matchRadius, { type: "number", min: 100, max: 20000, step: "any", help: "Players within this radius receive natural-defeat reward claims; 100–20,000." })}
          ${inputField("Respawn player radius", "respawnPlayerRadius", spawner.respawnPlayerRadius, { type: "number", min: 1000, max: 100000, step: "any", help: "Players within this radius keep active bosses eligible for respawn checks; 1,000–100,000." })}
          ${inputField("Arena radius", "arenaRadius", spawner.arenaRadius, { type: "number", min: 1000, max: 100000, step: "any", help: "Available radius for the encounter formation; 1,000–100,000." })}
          ${inputField("Member spacing", "memberSpacing", spawner.memberSpacing, { type: "number", min: 100, max: 10000, step: "any", help: "Base spacing multiplied by the largest member scale; 100–10,000." })}
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
    const cards = spawner.members.map((member, index) => `
      <details class="member-card"${index === 0 ? " open" : ""}>
        <summary class="member-summary">
          <div class="summary-title"><strong>Member ${index + 1}</strong><span data-member-summary="${index}">${escapeHtml(member.palId || "Pal ID required")} · Level ${escapeHtml(member.level)}</span></div>
        </summary>
        <div class="detail-body">
          <div class="field-grid">
            ${inputField("Pal / NPC ID", "palId", member.palId, { scope: "member", index, list: "pal-options", help: "Exact character ID written to pal_id; 1–64 letters, numbers, underscores, dots, or hyphens." })}
            ${inputField("Level", "level", member.level, { scope: "member", index, type: "number", min: 1, max: 100, step: 1 })}
            ${selectField("Designation", "designation", member.designation, [["normal", "Normal"], ["alpha", "Alpha"], ["predator", "Predator"]], { scope: "member", index, help: "Alpha and Predator are mutually exclusive." })}
            ${inputField("Scale", "scale", member.scale, { scope: "member", index, type: "number", min: 0.1, max: 10, step: "any", help: "Model scale multiplier from 0.1 to 10." })}
          </div>
          ${toggleRow("Uncapturable", "uncapturable", member.uncapturable, "Prevents this member from being captured.", { scope: "member", index })}
          ${memberNotice(member)}
          <div class="field-grid three">
            ${inputField("HP multiplier", "hpMultiplier", member.hpMultiplier, { scope: "member", index, type: "number", min: 0.01, max: 1000, step: "any" })}
            ${inputField("Attack multiplier", "attackMultiplier", member.attackMultiplier, { scope: "member", index, type: "number", min: 0.01, max: 1000, step: "any" })}
            ${inputField("Defense multiplier", "defenseMultiplier", member.defenseMultiplier, { scope: "member", index, type: "number", min: 0.01, max: 1000, step: "any", help: "2.0 means half incoming damage." })}
          </div>
          <div class="field-label">Active skills</div>
          <div class="field-grid three">
            ${member.activeSkills.map((skill, slot) => inputField(`Slot ${slot + 1}`, `activeSkill${slot}`, skill, { scope: "member", index, list: "active-skill-options", placeholder: "Optional" })).join("")}
          </div>
          <div class="field-label">Passive skills</div>
          <div class="field-grid">
            ${member.passiveSkills.map((skill, slot) => inputField(`Slot ${slot + 1}`, `passiveSkill${slot}`, skill, { scope: "member", index, list: "passive-skill-options", placeholder: "Optional" })).join("")}
          </div>
          <div class="detail-actions"><button class="button button-danger button-small" type="button" data-action="remove-member" data-index="${index}">Remove Member</button></div>
        </div>
      </details>`).join("");
    return `<div class="collection-toolbar">
      <p>Members generate contiguous indices from 1 to ${spawner.members.length || 0}. Maximum 16.</p>
      <button class="button button-secondary button-small" type="button" data-action="add-member">Add Member</button>
    </div>
    ${cards || `<div class="empty-collection">At least one member is required for an enabled spawner.</div>`}`;
  }

  function renderRewards(spawner) {
    const cards = spawner.rewards.map((reward, index) => `
      <details class="reward-card"${index === 0 ? " open" : ""}>
        <summary class="reward-summary">
          <div class="summary-title"><strong>Reward ${index + 1}</strong><span data-reward-summary="${index}">${escapeHtml(reward.kind === "currency" ? `${reward.count} shop currency` : `${reward.count} × ${reward.item || "Item ID required"}`)}</span></div>
        </summary>
        <div class="detail-body">
          <div class="field-grid">
            ${selectField("Reward type", "kind", reward.kind, [["item", "Item"], ["currency", "Server shop currency"]], { scope: "reward", index })}
            ${inputField("Count", "count", reward.count, { scope: "reward", index, type: "text", inputMode: "numeric", help: "Positive whole number." })}
            ${reward.kind === "item" ? inputField("Item ID", "item", reward.item, { scope: "reward", index, list: "item-options", help: "Exact Palworld item spawn ID." }) : `<div class="field"><span class="field-label">Currency provider</span><div class="notice">Delivered through ServerShopFramework API 1 when the player claims rewards.</div></div>`}
            ${inputField("Drop chance", "chance", reward.chance, { scope: "reward", index, type: "number", min: 0, max: 1, step: "any", help: "0 never awards; 1 always awards. Rolled once per eligible player." })}
          </div>
          <div class="detail-actions"><button class="button button-danger button-small" type="button" data-action="remove-reward" data-index="${index}">Remove Reward</button></div>
        </div>
      </details>`).join("");
    return `<div class="collection-toolbar">
      <p>Rewards generate contiguous indices from 1 to ${spawner.rewards.length}. Maximum 64.</p>
      <button class="button button-secondary button-small" type="button" data-action="add-reward">Add Reward</button>
    </div>
    ${cards || `<div class="empty-collection">No defeat rewards configured. This is valid.</div>`}`;
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
      spawner.rewards[index][target.dataset.key] = value;
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
    if (state.selectedUid === spawnerUid) {
      state.selectedUid = state.spawners[Math.min(oldIndex, state.spawners.length - 1)]?.uid || null;
    }
    markDirty();
    render();
  }

  function handleAction(action, index) {
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
    } else if (action === "remove-member") {
      spawner.members.splice(index, 1);
    } else if (action === "add-reward") {
      if (spawner.rewards.length >= 64) return showToast("A spawner can contain at most 64 rewards.");
      spawner.rewards.push(defaultReward("item"));
    } else if (action === "remove-reward") {
      spawner.rewards.splice(index, 1);
    }
    markDirty();
    renderEditor();
    renderSidebar();
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
    if (button.dataset.action === "select-spawner") {
      state.selectedUid = button.dataset.uid;
      render();
    } else if (button.dataset.action === "remove-spawner") {
      removeSpawner(button.dataset.uid);
    }
  });

  $("#section-tabs").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-section]");
    if (!button) return;
    state.activeSection = button.dataset.section;
    renderEditor();
  });

  formElement.addEventListener("input", (event) => updateValue(event.target));
  formElement.addEventListener("change", (event) => {
    updateValue(event.target);
    if (event.target.dataset.key === "kind" || event.target.dataset.key === "palId") renderEditor();
  });
  formElement.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    event.preventDefault();
    handleAction(button.dataset.action, Number(button.dataset.index));
  });

  $("#add-spawner").addEventListener("click", addSpawner);
  $("#add-empty").addEventListener("click", addSpawner);
  $("#generate").addEventListener("click", generateConfig);
  $("#generate-top").addEventListener("click", generateConfig);
  downloadButton.addEventListener("click", downloadConfig);

  populateList("pal-options", data.pals);
  populateList("item-options", data.items);
  populateList("active-skill-options", data.activeSkills);
  populateList("passive-skill-options", data.passiveSkills);
  render();
})();
