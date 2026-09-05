# World Boss Framework Config Generator

A browser-based editor for creating validated `spawners.config` files for **World Boss Framework v0.7.1**.

The generator provides a guided interface for configuring world boss encounters without manually writing every config key. Everything runs locally in the browser, and a valid configuration can be downloaded directly as `spawners.config`.

## Download World Boss Framework

[**Download World Boss Framework v0.7.1**](./World Boss Framework/)

The linked archive contains the World Boss Framework v0.7.1 mod files. Extract it into the Palworld server's `Pal/Binaries/Win64/ue4ss/Mods/` directory and restart the server.

## About World Boss Framework

World Boss Framework adds configurable server-wide world boss encounters to Palworld dedicated servers running UE4SS. Server owners can build single- or multi-member encounters from Pal and NPC character IDs, customize their combat properties and skills, place them with in-game map coordinates, and schedule them through an automatic encounter queue.

The framework also provides:

- Persistent automatic scheduling, lifecycle tracking, and guarded respawning.
- Item and virtual-currency rewards with persistent per-player claims.
- Server-wide defeat announcements naming eligible players and their optional titles.
- **Player Title Framework** support for first-defeat titles and **Server Shop Framework** support for currency rewards and early summons.
- Runtime terrain placement, multi-member formations, configurable arena distances, and administrative encounter controls.

### Required Dependencies

World Boss Framework requires the following server-side components to be installed and enabled:

- **UE4SS** — provides the Lua runtime and native game access used by the framework. Use the Okaetsu RE-UE4SS build compatible with the current Palworld dedicated-server version.
- **Palladium** — loads World Boss Framework, supplies its event and command framework, manages settings and persistent data, and controls permissions.
- **Pixel's Palmod Core** — provides the shared Palworld server APIs consumed by World Boss Framework. It must load before World Boss Framework in Palladium's `mods.list`.
- **PalSchema** — creates and manages the native Pal and NPC spawners generated from `spawners.config`. Its `enabled.txt` file must be present so UE4SS starts it.

All four dependencies must load successfully before World Boss Framework can create encounters. 

**Player Title Framework** and **Server Shop Framework** are optional integrations and are only needed for the related title, currency-reward, and early-summon features described below.

## Spawner Config Generator Features

- Add, edit, and remove multiple world boss spawners.
- Configure every spawner property supported by World Boss Framework v0.7.1.
- Add up to 16 Pal or NPC members to each encounter.
- Configure levels, scale, Alpha or Predator designation, capture restrictions, stat multipliers, active skills, and passive skills for every member.
- Add up to 64 item or Server Shop Framework currency rewards to each spawner.
- Configure automatic queue order, map location, placement rotation, encounter ranges, formation spacing, first-defeat titles, and early-summon shop offers.
- Search bundled Pal, NPC, item, active-skill, and passive-skill reference data while editing.
- Validate identifiers, required values, numeric ranges, duplicate spawner IDs, member formations, rewards, and optional framework dependencies.
- Generate a clean configuration preview and download it directly as `spawners.config`.
- Work entirely in the browser without accounts, uploads, or a backend server.

## Using the Spawner Config Generator

1. Open the hosted generator in a modern browser.
2. Choose **Load spawners.config** to edit an existing file, select the included example spawner, or choose **Add Spawner** to create another encounter.
3. Use the editor tabs to configure the spawner:
   - **Basics** — ID, display title, first-defeat title, queue order, and availability.
   - **Location** — map coordinates, ground clearance, and rotation.
   - **Arena** — reward range, respawn range, arena size, and member spacing.
   - **Members** — encounter characters, stats, designations, and skills.
   - **Rewards** — item drops and virtual-currency rewards.
   - **Shop** — optional ServerShopFramework early-summon offer.
4. Choose **Generate Config**.
5. Correct any validation errors shown beside the output. Warnings identify settings that may require another framework or an ID that should be verified.
6. Review the generated text and choose **Download spawners.config**.

The download button is disabled whenever the form has changed since the last successful generation. Generate the config again to ensure the downloaded file matches the current form.

## Installing the Generated Configuration

1. Back up any existing World Boss Framework configuration.
2. Copy the downloaded file to:

   ```text
   ue4ss/Mods/World Boss Framework/spawners.config
   ```

3. Replace the existing file when prompted.
4. Fully restart the Palworld server. Reloading only the Lua mods is not sufficient for applying spawner configuration changes.

The generator creates a complete file from the spawners currently shown on the page. It does not import or merge an existing `spawners.config` file. Form contents are also reset when the page is reloaded, so download the configuration before leaving the page.

## Validation Behavior

Errors prevent configuration generation. These include missing required fields, invalid IDs, out-of-range values, duplicate spawner IDs, unsupported active skills, invalid rewards, and member formations that do not fit inside the configured arena and respawn radii.

Warnings do not prevent generation. They call attention to optional framework requirements, currently inactive settings, or character, item, and passive-skill IDs that were not found in the bundled reference data.

Special character IDs such as `BOSS_`, `RAID_`, `GYM_`, and other preserved designations retain their native behavior. Alpha and Predator settings are ignored for these IDs. `RAID_` and `GYM_` members also preserve their native active skills.

## Optional Framework Integrations

- **Player Title Framework** is required to grant the configured first-defeat title.
- **Server Shop Framework** is required for virtual-currency rewards and early-summon shop offers.

World Boss Framework can still use spawners that do not enable these optional integration features.

## Privacy and Offline Use

All editing, validation, and file generation happen locally in the browser. No configuration data is transmitted or stored remotely by the generator. Once the site files have been loaded, the tool has no external runtime dependencies.

## Hosting with GitHub Pages

This repository is a dependency-free static site. To publish a copy:

1. Place `index.html`, `styles.css`, `app.js`, `data.js`, and `.nojekyll` in the repository root.
2. Open **Settings → Pages** in the GitHub repository.
3. Choose **Deploy from a branch**.
4. Select the publishing branch, normally `main`, and the `/(root)` folder.
5. Save the settings and wait for GitHub to provide the Pages URL.

No build command, package installation, environment variables, or server-side services are required. Relative asset paths allow the site to work from both account-level and repository-level GitHub Pages URLs.

## Reference Data

Character, item, active-skill, and passive-skill suggestions are bundled into the site for convenience. The World Boss Framework active-skill table is used for strict active-skill validation. Other bundled databases are used as editing aids and may not include every ID supported by a newer Palworld release.