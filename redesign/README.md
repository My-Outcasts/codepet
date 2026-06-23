# CodePet — UI Redesign Prototype

A browser-viewable redesign of the CodePet macOS app. Direction: **evolve current (polish)** — same
cream + pixel-meets-modern identity as production, executed tighter (8pt spacing rhythm, deliberate type
scale, unified components, calmer accent usage). It mirrors the real app's information architecture and
uses the actual CodePet art (`../design-assets/`) and bundled fonts (`../codepet/Resources/Fonts/`).

This is a **standalone visual prototype** — nothing under `codepet/` is touched. Porting screens back into
SwiftUI is a separate follow-up.

## View it

```bash
open redesign/index.html        # full app shell: left rail + HUD, click the rail to switch screens
open redesign/styleguide.html   # the design system on one page (colors, type, components)
```

Open in a browser (Chrome/Safari). Each screen also opens standalone, e.g. `open redesign/screens/home.html`.

> Note: the mockups load fonts/art via relative paths, so keep the `redesign/` folder inside the repo
> (it references `../codepet/Resources/Fonts/` and `../design-assets/`). Some browsers block `file://`
> font loading; if titles don't render in the pixel font, serve locally instead:
> `python3 -m http.server` from the repo root, then visit `http://localhost:8000/redesign/`.

## What's inside

```
redesign/
├── index.html            App shell — 72px rail + persistent HUD + screen switcher (iframe)
├── styleguide.html       Living style guide (sign-off view for the direction)
├── styles/
│   ├── tokens.css        Design tokens (CSS variables) — single source of truth
│   └── components.css     Shared component library every screen consumes
├── assets/fonts.css      @font-face for the app's bundled Minecraft + Inter
├── screens/              One file per screen (content fragments; render in the shell or standalone)
│   ├── home.html         World map · stat tiles · pet scene · kingdoms · achievements
│   ├── sessions.html     Quests — kingdom selector + vertical challenge trail + detail panel
│   ├── insights.html     Progress dashboard — streak calendar, coding summary, skill tree, stats
│   ├── learn.html        Expert hero · build-along case studies · Ask-Astro Q&A
│   ├── reflection.html   Session sidebar + chat-style coding-narrative log
│   ├── profile.html      Hero card · stats bento · companion switcher · preferences
│   ├── dictionary.html   Searchable, topic-color-coded glossary + term detail
│   ├── splash.html       Bouncing starters + wordmark + CTA
│   └── onboarding.html   Wizard — questions · interests · companion select
└── design-tokens.json    Figma export (Tokens Studio format)
```

## The design system

All visual decisions live in `styles/tokens.css` as CSS variables, carried verbatim from
`codepet/Views/CodepetTheme.swift` and extended with the scale that makes it feel polished:

- **Surfaces** cream `#F8F7F3` / white / sunken `#F1EFE9` / hairline `#ECE9E2`
- **Accents** purple `#7C3AED`, pink `#FF6B9D`, gold `#FDB022`, teal `#2DD4BF`, orange `#FF8C42`,
  blue `#2563EB` — each now with a **tint** (chips/bars) and **deep** (text-on-tint, pressed)
- **Kingdoms** Molten Forge `#FF8040`, Frozen Spire `#88D0F0`, Eternal Garden `#F0A8D0`, Mystic Grove `#90D870`
- **Type** Minecraft for titles ≥18px, Inter below — exact production rule
- **Spacing** 8pt scale (4/8/12/16/24/32/48/64) · **Radius** card 14 / pill 24 / input 12
- **PixelCard** staircase-cut corners + 4px ink outline + hard offset shadow, reproduced in CSS

To change the look globally, edit `tokens.css` — every screen updates.

## Importing tokens into Figma

`design-tokens.json` is in **Tokens Studio** format (the standard bridge from code tokens to Figma styles).

1. In Figma, install the free plugin **"Tokens Studio for Figma"** (Plugins → find more plugins).
2. Open it → **Import** (or the `{}` menu → *Import* → *File / JSON*) → choose `redesign/design-tokens.json`.
3. The `codepet` token set loads: colors, typography, spacing, radius, shadows. Use **Styles → Create
   styles** in the plugin to materialize them as native Figma color/text/effect styles.
4. Fonts: install **Minecraft.ttf** (`codepet/Resources/Fonts/`) and **Inter** locally so the typography
   tokens resolve to the right faces in Figma.

> Once you authenticate the Figma MCP (run `/mcp` → "claude.ai Figma"), I can additionally pull any
> existing CodePet frames for reference, or attempt to push frames if your account exposes write tooling —
> but tokens-via-Tokens-Studio is the reliable path and works today.

## Fidelity notes

- The HUD is shown persistently in the shell as a global player-status bar. In production it only appears
  on Home/Skills/Sessions — kept global here for a consistent prototype.
- Sprites/art/fonts are the **real** CodePet assets, referenced in place (no new art generated).
- Data shown (levels, streaks, kingdoms, economy numbers) follows the values in `CLAUDE.md`'s game economy.
