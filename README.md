# World Boss Config Generator

A browser-based editor for creating and validating `WorldBossFramework` `spawners.config` files. The generator is fully client-side and can be opened directly from the extracted source folder.

## Use

1. Open `index.html` in a modern browser.
2. In-game, stand at each encounter location and run `!pos` or `!p` to read its Map X, Map Y, and World Z values.
3. Add a new spawner or load an existing `spawners.config` file, then enter all three position values.
4. Edit the remaining spawner, member, reward, and shop settings.
5. Select **Generate Config** to validate the configuration.
6. Select **Copy Config Text** or **Download spawners.config**.
7. Install the resulting file at `ue4ss/Mods/WorldBossFramework/spawners.config` and fully restart the server.

Every spawner requires a numeric `world_z` value. The generator will load older files so they can be migrated, but it will refuse to generate output until every spawner has a valid World Z value. `ground_clearance` is retired because the framework now uses the configured World Z directly and performs no runtime terrain-height scan.

## Large-config editing tools

- On wide screens, drag either divider to resize the spawner list, editor, and output panels. The focused divider can also be moved with the left and right arrow keys.
- Search filters spawner cards by spawner ID, title, member Pal ID, or resolved Pal name.
- Drag the handle at the bottom of a spawner card to reorder definitions. A focused handle can also be moved with the up and down arrow keys.
- Card order controls only the order of sections in the generated file. Every automatic spawner runs independently using its own `spawn_timer`.
- **Copy Rewards List** and **Paste Rewards List** transfer the complete reward list between spawners. Pasting replaces the destination list after confirmation when it is not empty.
- Reward copying uses the browser clipboard when available and retains an in-app copy for browsers that block clipboard access on local files.
- Member summaries show the Pal's display name while preserving the exact Pal ID used by the generated configuration.

## Files

- `index.html` — application markup
- `styles.css` — layout and presentation
- `app.js` — editor behavior, validation, import, and generation
- `data.js` — Pal, item, and skill lookup data
- `.nojekyll` — preserves the static file layout when hosted on GitHub Pages

No server process, package installation, or build step is required.

## Scheduling and shop routes

- `spawn_timer` is required on every spawner and is the cooldown, in seconds, that begins after that spawner's boss is killed or captured.
- Automatic spawners are immediately due the first time the framework activates; their first spawn has no countdown.
- `auto_enabled` and `shop_offer_enabled` are mutually exclusive. Shop-only spawners never receive an automatic timer, and automatic spawners are never registered as shop offers.
- The generator accepts retired `queue_order` and `shop_reset_schedule` keys when importing older files, but discards them and never writes them to generated output.

## Server Shop page — 2026-09-08

Select **Server Shop** in the top navigation. Both pages use the same loaded Palworld reference database and application utilities. Switching pages retains both editors' in-memory edits; export your files before closing or refreshing the browser.

This page targets the preserved **ServerShopFramework v1.0.0** configuration schema, not the older v0.2.1 standalone archive. It adds:

- Shop settings for Credits display name, starting balance, chat page size, free offers, and optional currency-admin UIDs.
- Searchable offers with add, duplicate, remove, enable/disable, category, purchase limit, and cooldown controls.
- Currency, item, and active-party Pal costs; currency, item, Pal, title, and registered custom-provider rewards.
- Item and Pal ID suggestions from the same database used by the World Boss editor. Use `Money` for Gold Coins and `DogCoin` for Dog Coins; Credits use `kind = currency`.
- Load, validate, generate, copy, and download `settings.config`. Invalid known settings block generation. Unknown item/Pal IDs produce warnings because mods can add IDs. Custom provider availability must be checked on the server.

New offers start disabled. Imported missing `enabled` values use the runtime's enabled-by-default behavior. An intentionally empty offer list exports `offers =` to override bundled default offers; it does not remove offers contributed by other frameworks.

Boss summon offers remain on the **World Boss → Shop** panel. They are contributed to ServerShopFramework by WorldBossFramework and must not be re-created as static Shop offers. Shop settings now include configurable action-trigger Credits. These settings require the accompanying ServerShopFramework Action Rewards patch. Leaderboards remain excluded.

### Configuration compatibility

Palladium's inspected `parse_settings` function interprets plain dotted assignments, booleans and numbers, with all settings before the first section header. It **does not unquote strings or remove inline comments**. The Shop exporter therefore emits plain single-line values. Do not add quotation marks around names or append inline comments to numbers. Offer IDs use letters, digits and underscores, starting with a letter or underscore: this avoids dot nesting, unsupported hyphens in settings keys, and numeric-key coercion.

The importer preserves additional settings and permission sections, including `[nodes]`; it does not silently replace your permissions. It rejects duplicate or conflicting scalar/nested assignments. Known cost/reward aliases (`count`, `item`, `species`, `title`) are normalized to `amount` and `id` using the runtime's precedence. Comments and original formatting are not retained. Additional unknown settings are retained with a review notice, not validated against future runtime schemas. Numeric-only admin UIDs cannot round-trip through Palladium's numeric coercion; use its permission grants instead.

Install the generated file over **ServerShopFramework's active settings.config**, commonly `ue4ss/Mods/Palladium/mods/ServerShopFramework/settings.config`; installations using the flat fallback keep it beside the mod. Confirm the active location in your installed Palladium logs. The target code reads settings as they are used; changing starting balance affects newly created balances, not existing balances.

### Preserved editor styling

`styles.css` and `data.js` are byte-for-byte unchanged from the preserved independent-spawner generator. New styling is isolated in `shop.css`; the original World Boss buttons, member lists and layout rules are retained. `app.js` uses the shared HTML escaping utility and skips resize calculations while its page is hidden, preserving the user's panel widths across navigation.

New source files: `generator-core.js` (shared navigation/utilities), `shop.js` (Shop editor), `shop.css` (additive styling). No deployed site, build dependency or server process is included. JavaScript syntax and source compatibility were reviewed; browser interaction and live server imports remain to be verified.

## Action reward settings

Open Server Shop → Shop settings. Enable action rewards, choose Credits for each action (0 disables it), and choose whether to announce grants. Export to the live ServerShopFramework settings.config. Existing server settings are not automatically overwritten by an example file update.

Alpha/Predator kills use the native boss classifiers and WorldBossFramework membership exclusion. Tower/raid rewards use native battle completion paths. First-capture rewards use the native capture callback and per-species capture record. Main and side quests pay once per player and quest. Capture completion uses the game's capture-relic notification; it does not invent a reward at every multiple of five. Dedicated-server callback visibility still needs live validation.

Dungeon completion has no verified hook in the inspected SDK. Importing a nonzero dungeon action rate blocks generation. See ACTION_REWARDS.md in the server source package for exact hooks, attribution, duplicate protection and live limitations.

The existing World Boss editor, shared reference database, buttons, member lists and styles are retained. No deployment is included.
