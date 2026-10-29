# Interfere design system: reference for our UIs

Source: <https://design.interfere.com> ("Interfere Design System: components, styles and guidelines for building Interfere products"). Studied 18 Oct 2026 by curling the HTML/CSS and reading computed styles in headless Chrome at desktop (1440×900) and mobile (390×844) sizes, in dark and light themes. Screenshots of the reference are in `shots/`, and raw extracts are in `extract.json` and `light.json`.

**This is the default look for every new UI we build** unless a project says otherwise. Start from `tokens.css`, which you can drop into any vanilla or Tailwind project, and follow the component specs below.

## What it is
- A product design system for Interfere, a developer/observability tool. The stack is **Tailwind CSS v4**, **Radix Colors** (gray, blue, green, orange, tomato, all with alpha scales), **Base UI** primitives (dialog, popover, tabs, menu) and Inter.
- The site itself is a Vite/React SPA. It has a sidebar of foundations (Brand, Colors, Radius, Shadows), typography (Font Families, Headings, Text, Caption, Code) and about 35 primitives: Accordion, Avatar, Badge, Breadcrumb, Button, Card, Checkbox, Code Card, Collapsible, Combobox, Command, Context Menu, Dialog, Divider, Drawer, Input, Input OTP, Kbd, Label, Menu, Popover, Radio Group, Reaction, Scroll Area, Select, Skeleton, Spinner, Switch, Table, Tabs, Textarea, Toast, Tooltip.
- There's a theme switcher (System / Light / Dark), and dark is the showcase theme.
- **Licence:** no licence is published for the design system, and no public npm package exists. The CSS comment only carries Tailwind's MIT notice. So we **restate the values** (colours, sizes, radii) and write our own CSS. We do not copy their stylesheet, logo, or font files.
- **Fonts:**
  - **Inter Variable** (SIL OFL) is free, and we bundle it from rsms/inter (`fonts/InterVariable.woff2` + `OFL.txt`).
  - **Berkeley Mono** (their code font, a custom "Interfere" cut) and **Heldane Text** (Klim, serif accent) are commercial. Use the system monospace (SF Mono / Menlo) and serif instead.
  - **Departure Mono** (OFL) is used decoratively. Skip it.

## Personality / tone
- Quiet, dense, tool-like: black frame, near-black panel, white text at 93% opacity, and grey hierarchy made only from **white alpha layers**. Colour appears only as intent (blue brand, green positive, orange warning, tomato danger).
- No visible borders. Edges are **0.5px inset hairlines** (`box-shadow: 0 0 0 .5px #ffffff12 inset`) and small surface steps (bg alpha 0.035 → 0.07 → 0.106).
- Small type (13px UI text) with medium weight for controls and semibold only for page titles. Sentence case everywhere: "Kill switch", not "KILL SWITCH". No emoji in chrome.
- The primary button is **inverted** (white bg, black text). Blue ("brand") is for emphasis, links, focus rings and selection, not for every primary action.
- Motion is short and calm: 75–200ms, ease-out, `scale(.98)` on button press, and dialogs fade and scale from 0.97.

## Layout pattern (app shell)
```
┌ shell #000 ───────────────────────────────────────────────────────────┐
│ sidebar 280px (p 12)    ┌ panel #111, r16, .5px border, m 4px ───────┐ │
│  logo 20px              │ header: page title 20/24 semibold · stats  │ │
│  [Search ⌘K]            │ ────────────────────────── (.5px hairline) │ │
│  group label (fg-3)     │ content: px 32–40, py 24–60, max-w ~1480   │ │
│  nav item 28px r6       │   cards r12 / sections r16 on the panel    │ │
│  …                      │                                            │ │
│  bottom: theme seg, CTA │                                            │ │
└─────────────────────────└────────────────────────────────────────────┘─┘
```
- On mobile (<768px) the sidebar collapses to a top bar (logo plus a hamburger), the panel goes edge to edge with a 4px gutter, and cards stack.
- Docs pages centre a ~540px column (`max-w-xl`) with 60px top padding. App pages use the full panel width.

## Tokens (dark, the default)
| Role | Value |
|---|---|
| shell (frame, sidebar) | `#000` |
| container (main panel) | `#111` (gray-1) |
| page | `oklch(15% 0 0)` |
| card on container: subtle / strong | `#ffffff09` / `#ffffff12` |
| component (button bg, segmented track) | `#ffffff12`; hover `#ffffff1b`; active `#ffffff22` |
| sunken (table/code well) | `#00000066` |
| modal | `oklch(25.2% 0 0)` (≈ #232323) |
| backdrop | `#000000cc` (black a8) |
| fg primary / secondary / tertiary / disabled | `#ffffffed` / `#ffffffaf` / `#ffffff64` / `#ffffff55` |
| border subtle / default / strong | `#ffffff09` / `#ffffff12` / `#ffffff2c` |
| brand solid / hover / subtle bg / on-subtle fg | `#0090ff` / `#3b9eff` / `#0077ff3a` / `#70b8ff` |
| positive | `#30a46c` / subtle `#22ff991e` / on-subtle `#46fea5d4` |
| warning | `#f76b15` / subtle `#fb6a0025` / on-subtle `#ffa057` |
| danger | `#e54d2e` / hover `#ec6142` / subtle `#ff55330f` (badge `#ff35232b`) / on-subtle `#ff977d` / fg `#ff6847eb` |
| inverted (primary button) | bg `#fffffff2`, hover `#fffc`, fg `#000` |
| focus ring | 1px `#0090ff` |

Gray scale (Radix gray dark): 1 `#111` · 2 `#191919` · 3 `#222` · 4 `#2a2a2a` · 5 `#313131` · 6 `#3a3a3a` · 7 `#484848` · 8 `#606060` · 9 `#6e6e6e` · 10 `#7b7b7b` · 11 `#b4b4b4` · 12 `#eee`.
The light theme is in `tokens.css` (`[data-theme="light"]`): shell `oklch(97.3% 0 0)`, container `#fcfcfc`, fg `#000000df`, and cards are white with a soft drop shadow.

### Typography
- Family: Inter Variable with `font-feature-settings: "ss03"`. Mono: Berkeley Mono, falling back to the system mono.
- Weights: 400 normal, 450 "semimedium", 500 medium (all controls), 600 semibold (titles).

| Token | Size / line | Use |
|---|---|---|
| caption-sm / base / lg | 10/16 · 11/16 · 12/16 | badge sm, meta, table headers, small inputs |
| body-sm | 13/20 | **default UI text**, buttons, inputs, tabs, nav, table cells |
| body-base | 15/24 | docs body, dialog title (500), section titles (500) |
| body-lg | 18/24 | lead text |
| heading-6…1 | 20/24 · 24/32 · 28/36 · 36/44 · 44/56 · 56/56 | tracking −0.01em; page title is heading-6 semibold |

### Radius
xs 2 · sm 4 (badges) · md 6 (buttons, tabs, nav items) · lg 8 (inputs, selects, wells) · xl 10 · 2xl 12 (cards, dialogs, toasts) · 3xl 16 (main panel, section frames) · 4xl 20 · 5xl 24 · full (switches, avatars).

### Spacing and sizes
- 4px base. Control heights: xs 20 · sm 24 · **md 28 (default button/tab)** · lg 32 (default input/select) · xl 40.
- Card padding is 16. Section frames use p 4 with gap 4 around inner cards. Table cells are 10×12 and headers 8×12 (36px tall).

### Shadows
- **default**: `0 0 0 .5px #ffffff12 inset` in dark. In light it's a 0.5px outline plus a 1–2px soft drop.
- **large** (popovers/menus): `0 0 0 1px mix(gray-a3, gray-6 25%), 0 2px 3px -2px #00000026, 0 3px 8px -2px #00000066, 0 4px 12px -4px #00000080`.
- **extra-large** (toasts): hairline plus `0 8px 40px #0000000d, 0 12px 32px -16px #00000026`.

### Motion
- Buttons: colour/bg/border at 150ms `cubic-bezier(0,0,.2,1)`; transform at 200ms with `scale(.98)` on press.
- Inputs and selects: 75ms ease-out.
- Tabs: sliding indicator, translate/width at 200ms ease-in-out.
- Dialog: opacity and scale at 200ms ease-in-out; backdrop opacity at 200ms.
- Respect `prefers-reduced-motion`.

## Components (measured)
- **Button** (`int-btn`): 13px/500, gap 6, r6.
  - Sizes: sm 24px (px 8), **md 28px (px 10)**, lg 32px, xl 40px.
  - Variants:
    - **primary**: inverted white, black text.
    - **secondary**: `#ffffff12` plus hairline, fg-1.
    - **tertiary**: `#ffffff12`, fg-2.
    - **brand**: `#0090ff`, white.
    - **danger**: `#e54d2e`, white.
    - **danger-subtle**: `#ff55330f`, fg `#ff6847eb`.
    - **transparent**: no bg, fg-2, hover `#ffffff1b`.
  - Disabled: bg `#ffffff09`, fg `#ffffff55`. Icon-only buttons are square (24/28).
- **Badge**: 20px tall, px 6, r4, 12px/400, gap 4.
  - Variants:
    - default: `#ffffff12` / fg-2
    - transparent
    - inverted: white / black
    - outline: 0.5px strong ring
    - danger: `#ff35232b` / `#ff977d`
    - brand: `#0077ff3a` / `#70b8ff`
    - positive and warning follow the same subtle/on-subtle pattern.
  - Sizes: sm 16px/11px, lg 24px/13px. Shapes: rounded (r4) or pill.
- **Input / Select / Textarea**: bg `#ffffff12`, 0.5px inset hairline, no border.
  - Sizes: sm 24px r6 12px; md 28px r8; **lg 32px r8 13px** (padding 0 8 0 10).
  - Focus: 1px brand ring. Placeholder: fg-3. Select chevron is a 16px stroke icon in fg-2.
- **Label**: 13px/500 fg-1, 6px above the field.
- **Tabs**: two styles.
  - **Segmented**: track `#ffffff12` r6, 28px tall; triggers 13px/500 fg-2 px 10. The active trigger gets a sliding indicator (`#ffffff12` plus hairline) and fg-1.
  - **Underline**: 1px bottom border, active trigger underlined in fg-1, gap 16.
- **Card**: subtle `#ffffff09` or strong `#ffffff12` on the container, r12, p16, default shadow. A section frame is r16 p4 gap4 containing inner cards and a "Show code" bar (`#2a2a2a`, r12).
- **Table**: sits in a sunken well (r8).
  - Header: 36px tall, 12px/500 fg-2.
  - Cells: 13px fg-1, padding 10×12, separated by 0.5px `#ffffff12` lines. Tabular numbers.
  - Optional footer row in bold.
- **Dialog**: modal bg `oklch(25.2% 0 0)`, r12, padding 12 16 16, default plus large shadow, max width about 448px (ours go wider for content).
  - Title: 15/24 medium. Description: 13/20 fg-2.
  - Close: 24px transparent icon button at top-right 12/12.
  - Backdrop: black 80%.
- **Toast**: modal surface, r12, extra-large shadow, bottom-right.
- **Switch**: pill 16px tall, p2; off `#ffffff12`, on brand.
- **Sidebar nav item**: 28px, px 8, r6, 13px/500 fg-2. Hover/active bg `#ffffff1b` with fg-1. Group labels are 13px/500 fg-3 with about 14px above.
- **Kbd**: small r4 chip, `#ffffff12`, 11–12px. Used in the search field (⌘ K).

## How to apply (checklist for new UIs)
1. Link `tokens.css` and set `<html data-theme="dark">`. Bundle Inter (OFL) locally, with no font CDN for local-first apps.
2. Use the shell: black frame, 280px sidebar with grouped nav, and a rounded `#111` panel with a sticky header (title on the left, status chips and actions on the right).
3. Build controls at 13px. Buttons are 28px (24 inside dense cards), inputs 32px, badges 20px.
4. Use the inverted white button for the main action, transparent or secondary buttons for the rest, and danger only for destructive actions.
5. Status = badge with a 6px dot plus a subtle intent tint. Never a solid saturated block except for danger CTAs.
6. Use hairlines instead of borders, and alpha surfaces instead of new greys.
7. Write copy in sentence case and keep it short. Use mono for IDs, hashes and IPs.
8. Mobile: collapse the sidebar into a top bar with a menu toggle; content becomes single column.

Files: `tokens.css` (dark + light variables, Inter @font-face), `fonts/` (Inter + OFL), `shots/` (reference captures), `compare.png` (reference vs Phone Farm), and `shoot.mjs` / `extract*.mjs` (re-run the capture with `node shoot.mjs out.png URL 1440 900 dark`).
