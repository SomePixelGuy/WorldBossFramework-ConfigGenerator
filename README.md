# Palworld Config Generator

A browser-based editor for creating and validating World Boss, Server Shop, Player Title, and Level Up Announcements & Rewards configs. The generator is fully client-side and can be opened directly from the extracted source folder.

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
- `generator-core.js` — shared navigation, clipboard, downloads, and ID lookup
- `shop.js` and `shop.css` — Server Shop editor
- `progression.js` and `progression.css` — Player Titles and Level Up editors

No server process, package installation, or build step is required.

## Scheduling and shop routes

- `spawn_timer` is required on every spawner and is the cooldown, in seconds, that begins after that spawner's boss is killed or captured.
- Automatic spawners are immediately due the first time the framework activates; their first spawn has no countdown.
- `auto_enabled` and `shop_offer_enabled` are mutually exclusive. Shop-only spawners never receive an automatic timer, and automatic spawners are never registered as shop offers.
- The generator accepts retired `queue_order` and `shop_reset_schedule` keys when importing older files, but discards them and never writes them to generated output.

## Server Shop page — 2026-09-08

Select **Server Shop** in the top navigation. All pages use the same loaded Palworld reference database and application utilities. Switching pages retains each editor's in-memory edits; export your files before closing or refreshing the browser.

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

## Shop refactor settings

Shop settings now include Credit acquisition announcements, Credit transfers, all action rates including dungeon Alpha defeats, and a separate Core reminder interval control. The latter copies a setting to merge into **PixelsPalmodCore/settings.config**; it is deliberately not written into the Shop settings file.

World Boss purchase numbers have no input field. ServerShopFramework enumerates configured WorldBossFramework summon offers in deterministic internal-key order and assigns 1 through N. Use `!shop worldboss` to see the numbers. Changing the configured catalogue can change numbers; temporary boss availability does not.

First-capture handling uses the server Paldex-registration event and bounded record reconciliation. The five-capture route pays once per player and species when the authoritative capture count crosses from below five to five or more. No relic notification is required. Dungeon clear means defeat of the dungeon’s Alpha boss and uses the dungeon rate instead of the ordinary Alpha rate.

Source validation is complete; live game validation is still required. Existing World Boss editor code, styles, buttons, member lists and reference data are preserved. No site deployment is included.

## Corrective-3 controls

Use **Server Shop → Action Rewards** to open action settings directly from any selected offer. **Defeat dungeon Alpha / clear dungeon — Credits** exports `action_rewards.dungeon.credits`; zero disables the reward. Existing styles and World Boss controls are preserved.


## Player Titles and Level Up pages

Select **Player Titles** or **Level Up & Rewards** in the top navigation. These pages target the v1.0.0 parsers from the supplied server snapshot. The older standalone LevelUpAnnouncements v0.1.0 archive has no level reward support; install the v1.0.0 mod to use generated reward settings.

Each page has independent settings, a searchable list, add/duplicate/remove controls, reward row duplication, and load/generate/copy/download controls. Edits stay in memory while switching pages; download before closing or refreshing. Both pages export a file named `settings.config`, so install each download into its corresponding mod directory.

### Player Titles

Edit announcement settings, the online-title broadcast cooldown (0–3600 seconds), and the untitled label. Add titles with a unique ID, display name, optional announcement, and item/owned-Pal rewards. A blank announcement exports no override and uses the runtime default. Display names support 64 characters. Title IDs use a leading letter/underscore and up to 96 letters, digits, or underscores.

The exporter uses the actual title schema:

```ini
titles.founder.name = Founder
titles.founder.items.1.item = Money
titles.founder.items.1.count = 1000
titles.founder.pals.1.species = SheepBall
titles.founder.pals.1.level = 5
titles.founder.pals.1.count = 1
```

Title reward kinds are limited to items and Pals because the title parser supports those two collections. Credits are available on the Level Up page, not as an invented title reward field. Titles do not grant themselves merely by being configured; the runtime's title grant/provider behavior is unchanged.

### Level Up Announcements & Rewards

Edit public announcements, polling (1–60 minutes), the default message, crossed milestone messages, reward enablement, and private reward notices. Each milestone uses a unique player level from 1–1000 (the parser range, not a claim about the game's current level cap). A milestone may override a message, contain rewards, or do both. With the message override disabled, the default announcement applies.

```ini
messages.10 = [Player Name] has reached double digits!
level_rewards.10.1.kind = currency
level_rewards.10.1.amount = 500
level_rewards.10.2.kind = pal
level_rewards.10.2.id = SheepBall
level_rewards.10.2.amount = 1
level_rewards.10.2.level = 10
```

The currency kind means ServerShopFramework Credits and has no ID field. Item rewards use `Money` for Gold Coins and `DogCoin` for Dog Coins. Reward Pal levels are 1–100. Quantities must be whole numbers from 1–1,000,000,000; both pages allow at most 128 combined reward rows per title/milestone. Runtime provider availability and delivery must be confirmed on the server.

### Import and validation

Both new pages reject invalid assignment syntax, duplicate keys, conflicting scalar/nested paths, and ambiguous reward aliases. They preserve permission sections and additional imported keys; unsupported additional keys are explicitly reported for review. Comments/formatting outside permission sections are not preserved. Supported item/Pal aliases are normalized to each mod's canonical fields. Unknown custom Pal/item IDs are warnings rather than errors. Known invalid fields block generation, copying, and downloading. Editing clears previously generated output to prevent copying a stale config.

Permissions are editable under **Settings**, using section headers and `node = allow` / `node = deny` assignments. Keep all ordinary settings before the first section header. New configs start with each mod's default permissions; imports retain their own sections. No string quoting or inline comments are added to settings values because Palladium treats them literally.

Install the generated files at:

- `ue4ss/Mods/Palladium/mods/PlayerTitleFramework/settings.config`
- `ue4ss/Mods/Palladium/mods/LevelUpAnnouncements/settings.config`

If the installed Palladium uses a fallback location, use the active settings path shown by that installation. Both mods queue rewards through PixelsPalmodCore for `!claimrewards`.

This editor update leaves `app.js`, `shop.js`, `styles.css`, `shop.css`, and `data.js` unchanged. New layout rules are scoped to `progression.css`. No deployment or backend mod patch is included. JavaScript syntax and parser compatibility were reviewed; browser interaction and live config imports remain to be checked in your environment.
