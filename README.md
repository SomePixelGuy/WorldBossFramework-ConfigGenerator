# World Boss Config Generator

A static, browser-only generator for validated WorldBossFramework v0.7.1 `spawners.config` files.

## Publish with GitHub Pages

1. Extract this ZIP.
2. Upload all extracted files to the root of your GitHub repository.
3. Open the repository's **Settings → Pages** page.
4. Under **Build and deployment**, choose **Deploy from a branch**.
5. Select your publishing branch (normally `main`) and the `/(root)` folder, then save.
6. GitHub will show the public site URL after deployment finishes.

No build command, package installation, server, or environment variables are required. All assets use relative paths, so the generator works from both account-level and repository-level GitHub Pages URLs.

## Included files

- `index.html` — page structure
- `styles.css` — responsive interface styling
- `app.js` — editor, validation, config generation, and download behavior
- `data.js` — bundled Pal/NPC, item, active-skill, and passive-skill suggestions
- `.nojekyll` — tells GitHub Pages to serve the static files directly

The page processes configuration entirely in the visitor's browser. Generated files are not uploaded anywhere.
