# Design System — Lewsnetter

The visual language for the app. Read this before any UI change. If a design decision isn't here, ask before adding it.

Preview / specimen page: `/tmp/lewsnetter-design-preview.html` (a self-contained HTML file that shows every primitive in this doc applied to real Lewsnetter surfaces).

---

## Product context

- **What this is:** AI-native email marketing SaaS on BulletTrain. Replaces Intercom for tenants that want to send broadcasts to their own users.
- **Who it's for:** Marketers + engineering-conscious operators at growth-stage SaaS companies. Today's only tenant: InfluenceKit.
- **Space / category:** Email marketing tools (Mailchimp, Loops, Beehiiv, Resend, Customer.io, Intercom).
- **Project type:** Multi-tenant web app with both authoring surfaces (campaign editor) and operational surfaces (subscriber lists, sending settings, analytics).

## The memorable thing

> *"This is the AI-native version of Intercom" — modern, technical, sharp.*

Every design decision below serves this. Lewsnetter should feel like a tool a developer-conscious marketer would actually want to use, not a CRM dashboard. Restraint over decoration. Real typography over icons. Engineering precision over marketing whimsy.

---

## Aesthetic direction

- **Direction:** Sharp tech product. Vercel / Linear / Resend lineage.
- **Decoration level:** Intentional but quiet. Hairline borders. No gradients, no drop shadows except functional elevation. No bubble border-radius anywhere.
- **Mood:** Composed, not crowded. Trustworthy, not flashy.
- **Anti-patterns (do not ship):**
  - Purple/violet gradients
  - 3-column feature grid with icons-in-colored-circles
  - Centered-everything hero with uniform spacing
  - Bubble border-radius on all elements
  - Gradient buttons as primary CTAs
  - Generic stock-photo-style hero sections
  - `system-ui` / `-apple-system` as the primary display or body font
  - "Built for X" / "Designed for Y" marketing copy patterns
  - Inter / Roboto / Helvetica / Open Sans / Lato / Montserrat / Poppins / Space Grotesk as primary
  - Icons inside buttons or nav items as the primary signifier (text-first only)

---

## Typography

- **Display + Body:** **Geist Sans** (`https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&display=swap`)
- **Metadata / IDs / Timestamps / Status enums / Tabular numerics / Code:** **Geist Mono** (`https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400;500&display=swap`)
- **Why Geist:** Free, distinctive, modern, technical. Same family Vercel + Resend use — the visual signature of modern web tooling. Mono variant handles the heavy metadata load (campaign IDs, recipient counts, segment predicates, ISO timestamps) without switching font families.

### Scale

| Role | Family | Size | Weight | Letter-spacing | Line-height |
|------|--------|------|--------|----------------|-------------|
| Display / H1 | Geist Sans | 32px | 600 | -0.02em | 1.15 |
| H2 / Section | Geist Sans | 24px | 600 | -0.015em | 1.25 |
| H3 / Card | Geist Sans | 18px | 600 | -0.01em | 1.3 |
| Body | Geist Sans | 15px | 400 | 0 | 1.55 |
| UI label | Geist Sans | 13px | 500 | 0 | 1.4 |
| Metadata | Geist Mono | 13px | 400 | 0 | 1.4 |
| Pill / eyebrow | Geist Mono | 11px | 500 | 0.06em uppercase | 1.4 |
| Hero editorial moment | Geist Sans | 38px | 600 | -0.025em | 1.15 |

**Tabular numerics:** any column displaying numbers (recipient counts, KPI values, byte sizes, timestamps as durations) gets `font-variant-numeric: tabular-nums` so digits line up.

---

## Color

Disciplined monochrome + one warm accent. **The accent is rare and meaningful** — used only for primary CTAs, focus rings, active nav state, link color, brand mark.

### Foundation (Zinc neutrals)

| Token | Light | Dark |
|-------|-------|------|
| `--bg` | `#FAFAFA` (Zinc 50) | `#09090B` (Zinc 950) |
| `--surface` | `#FFFFFF` | `#18181B` (Zinc 900) |
| `--text` | `#09090B` | `#FAFAFA` |
| `--text-muted` | `#52525B` (Zinc 600) | `#A1A1AA` (Zinc 400) |
| `--text-faint` | `#71717A` (Zinc 500) | `#71717A` |
| `--border` | `#E4E4E7` (Zinc 200) | `#27272A` (Zinc 800) |
| `--border-strong` | `#D4D4D8` (Zinc 300) | `#3F3F46` (Zinc 700) |

### Accent

- **Primary: `#EA580C` (orange-600)** in light mode, **`#FB923C` (orange-400)** in dark mode for accessibility on dark surfaces.
- Hover: `#C2410C` (orange-700) / `#F97316` (orange-500)
- Accent tint (focus-ring background, callout bg): `#FFF7ED` / `#2D1B0E`
- **Why orange:** uncommon in this space (Mailchimp = yellow, Loops = purple, Beehiiv = sage green, Resend = monochrome, Customer.io = teal, Intercom = purple). Distinct from IK's pink so Lewsnetter chrome and tenant content don't fight. "Sending = warmth = flame" works metaphorically.

### Semantic colors

| State | Color | Tint (bg) |
|-------|-------|-----------|
| Success / sent / verified | `#059669` (emerald-600) | `#ECFDF5` / `#052E1E` |
| Warning / sending / scheduled | `#F59E0B` (amber-500) | `#FFFBEB` / `#2D1F08` |
| Danger / failed / destructive | `#E11D48` (rose-600) | `#FFF1F2` / `#2D0B11` |
| Info / scheduled (blue variant) | `#1D4ED8` (blue-700) | `#EFF6FF` / `#1E3A8A33` |

---

## Spacing

4px base unit. Density: comfortable, leaning compact on data-heavy surfaces.

| Token | Value | Use |
|-------|-------|-----|
| 2xs | 2px | Pill border inset |
| xs | 4px | Tight inline gaps |
| sm | 8px | Form field internal padding |
| md | 12px | Form field horizontal padding, button padding |
| base | 16px | Card padding, list item spacing |
| lg | 24px | Card-to-card gap, section padding |
| xl | 32px | Section header to content |
| 2xl | 48px | Major section breaks, editorial hero padding |
| 3xl | 64px | Page top whitespace, send-hero internal padding |

---

## Layout

- **Max content width:** 1120px. Wider for data tables when needed.
- **Sidebar:** 240px on desktop, collapsible. Resource groupings (Audience / Content / Sending) as nav-section titles in Geist Mono caps.
- **Page padding:** 32px horizontal, 56px top.
- **Section gap:** 64px between top-level sections.

### Border radius

| Token | Value | Use |
|-------|-------|-----|
| sm | 4px | Pills, tags, small chips |
| md | 6px | Buttons, form inputs |
| lg | 8px | Cards, callouts |
| xl | 12px | Mock app shells, editorial hero |
| full | 9999px | Avatars only |

**No bubble radius anywhere.** 12px is the ceiling for non-avatar elements.

---

## Motion

- **Approach:** Intentional, state-transition-only. No scroll-driven animation. No micro-interactions on hover (cursor change is the affordance).
- **Easing:** enter `ease-out`, exit `ease-in`, move `ease-in-out`
- **Duration:** micro 50-100ms (color transitions), short 150ms (entrance fades), medium 250ms (panel slides — sparingly), long 400ms+ (rare; AI drafter type-in)

Where motion appears: AI drafter writing into the editor (200ms type-in), segment translate result fading in (150ms), toast appearance (150ms slide-up + fade).

---

## Components

### Buttons

- **Primary** (`.btn-primary`): orange-600 background, white text. Use for the most consequential action on a page.
- **Secondary** (`.btn-secondary`): transparent background, text-color text, border-strong border. Use for "do this but it's not the main thing."
- **Ghost** (`.btn-ghost`): transparent, text-muted color, no border. Use for tertiary actions.
- **Danger** (`.btn-danger`): transparent, rose-600 text. Use for delete/destroy. Always confirmation-gated.

Sizes: default (8/14 padding, 14px font), `.btn-lg` (12/20, 15px), `.btn-xl` (16/28, 17px, 600 weight). Use `.btn-xl` only on the editorial "Send to N subscribers" moment.

### Status pills

- Word + color, **no icons**.
- Geist Mono, 11px, uppercase, 0.04em letter-spacing.
- 1px solid border in the state color; tinted background.
- States: `Draft` (neutral) · `Scheduled` (blue) · `Sending` (amber) · `Sent` (emerald) · `Failed` (rose)
- Reused for sender-address verification: `Verified` (emerald) · `Pending` (amber) · `Not added to SES` (neutral) · `Verification failed` (rose)

### Form fields

- 8/12 padding. 6px border-radius. 1px border-strong.
- Focus: accent border + 3px accent-tint focus ring.
- Required marker: red asterisk after label (sr-only "(required)" for screen readers).
- Optional marker: gray "(optional)" suffix in Geist Sans 11px after label.
- Help text below: Geist Sans 12px text-faint.

### Cards

- White / Zinc 900 surface.
- 1px border. 8px radius.
- Header / body / footer split: hairline 1px divider between header and body, body and footer.
- Footer takes Zinc 50 / 950 background to demote it visually.

### Tables

- Hairline 1px borders between rows only. No vertical borders.
- Header row: Geist Mono 11px uppercase, text-faint color.
- Body rows: 14/16 padding, 14px Geist Sans.
- Numeric columns: Geist Mono with tabular-nums.

---

## Specific surfaces

### Dashboard

- Top: KPI strip — 4 cells, mono labels in caps, large tabular-num values, mono delta line below. 1px dividers between cells.
- Below: "Recent campaigns" table with status pills + recipient counts.
- Resource navigation in the sidebar, not as tiles on the dashboard.

### Campaign show

- Hero block (the editorial moment): `--surface` background, 48/40 padding, 12px radius. H2 at 38px. Subhead in Geist Mono 13px. Action row with primary `Send to N subscribers` (.btn-xl), secondary `Send test`, ghost `Preview`, plus Preview-as input.
- Below the hero: 0-recipients warning (amber callout) or "About to send to N" confidence cue (orange callout).
- Below that: standard card with attribute details.

### Campaign edit

- Three sectioned cards: **Content** (Brief + Draft-with-AI + subject + preheader + body + raw-MJML disclosure + preview iframe), **Audience** (segment + sender), **Settings** (template + scheduled-for).
- Markdown editor: EasyMDE wrapping a textarea. Variable picker button + "Insert variable" panel beside the body field.
- Live preview iframe below the body with debounced refresh on edit.

### Template edit + show

- Edit: CodeMirror 6 wrapping the MJML source. Line numbers + XML highlighting. Asset upload section at the bottom.
- Show: rendered preview iframe + collapsed "Show MJML source" disclosure. Raw MJML NEVER displayed as flat text on the show page.

### AI segment translate

- Result panel uses the design system primitives: predicate in mono `<pre>`, "Matches N subscribers" as a status pill, sample subscribers in a table, "Use this predicate" primary button.

---

## Applying the system through BulletTrain

Lewsnetter is on BulletTrain 1.45 using `bullet_train-themes-light`. The theme architecture is three-layered (`themes` → `themes-tailwind_css` → `themes-light`) with view-partial inheritance via the `BulletTrain::Themes` resolver.

**Recommended path: extend Light via Method 1 (CSS + Tailwind config), not eject the whole theme.** Eject specific partials only when CSS + config can't get us there.

### Step 1 — Tailwind theme

In `tailwind.config.js`, extend the theme color palette:

```js
theme: {
  extend: {
    colors: {
      primary: {  // Lewsnetter accent
        50:  '#FFF7ED', 100: '#FFEDD5', 200: '#FED7AA', 300: '#FDBA74',
        400: '#FB923C', 500: '#F97316', 600: '#EA580C', 700: '#C2410C',
        800: '#9A3412', 900: '#7C2D12', 950: '#431407'
      },
      // Zinc neutrals are already in Tailwind's default palette — alias them
      // to the BulletTrain "base" scale so theme-light components pick them up.
      base: 'colors.zinc'
    },
    fontFamily: {
      sans: ['Geist', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      mono: ['"Geist Mono"', 'ui-monospace', 'monospace']
    },
    borderRadius: {
      DEFAULT: '6px',
      sm: '4px',
      md: '6px',
      lg: '8px',
      xl: '12px'
    }
  }
}
```

### Step 2 — `config/initializers/theme.rb`

Today this reads:

```ruby
BulletTrain::Themes::Light.color = :blue
```

Change to:

```ruby
BulletTrain::Themes::Light.color = :primary
```

This makes the `text-primary-*` / `bg-primary-*` classes throughout `themes-light` resolve to our orange.

### Step 3 — Load Geist + design tokens in `application.css`

Append to `app/assets/stylesheets/application.css`:

```css
@import url('https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap');

:root {
  --lw-accent: #EA580C;
  --lw-accent-hover: #C2410C;
  --lw-accent-tint: #FFF7ED;
}
[data-theme="dark"], html.dark {
  --lw-accent: #FB923C;
  --lw-accent-hover: #F97316;
  --lw-accent-tint: #2D1B0E;
}
```

### Step 4 — Status pill helper

We already have `app/helpers/status_pill_helper.rb`. Update the badge classes to match the Geist-Mono-uppercase pattern from this doc.

### Step 5 — Eject only when needed

The themed `_field.html.erb` is already ejected (we added required/optional markers earlier). Other ejections to consider:

- `app/views/account/shared/menu/_logo.html.erb` — for a real Lewsnetter wordmark + accent dot
- `app/views/account/shared/_box.html.erb` — only if the default card chrome conflicts with this doc

Avoid ejecting `shared/fields/*` partials — that road leads to drift with future BulletTrain updates.

---

## Decisions log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-14 | Initial design system created | `/design-consultation` based on "AI-native Intercom — modern, technical, sharp" memorable-thing |
| 2026-05-14 | Geist Sans + Geist Mono chosen | Free, distinctive, technical-feeling, matches Vercel/Resend visual signature |
| 2026-05-14 | Orange `#EA580C` as accent | Uncommon in email-marketing space; distinct from IK's pink; "sending = flame" metaphor |
| 2026-05-14 | Text-first buttons + pills (no icons) | More readable, less Material/Bootstrap feel, prevents icon noise |
| 2026-05-14 | Sharp corners (max 12px radius) | Anti-bubble; matches the tech-product baseline of Vercel/Linear/Resend |
| 2026-05-14 | Editorial moment on campaign show send action | Sending is consequential; oversized typography + generous whitespace |
| 2026-05-14 | Apply via Tailwind config + theme.rb tweaks first | BulletTrain doc explicitly recommends extending Light over ejecting whole theme |
