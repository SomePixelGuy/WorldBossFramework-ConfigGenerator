# World Boss Config Generator

A browser-based editor for creating and validating `WorldBossFramework` `spawners.config` files. The generator is fully client-side and can be opened directly from the extracted source folder.

## Use

1. Open `index.html` in a modern browser.
2. In-game, stand at each encounter location and run `!worldboss pos` to read its Map X, Map Y, and World Z values.
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
- Card order controls the order of sections in the generated file. It does not change a spawner's `queue_order` value or automatic-selection priority.
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
