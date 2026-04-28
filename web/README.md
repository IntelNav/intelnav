# intelnav.net

Static site for `intelnav.net`. Next.js 15 (App Router) + TypeScript +
Tailwind. `output: 'export'` produces a plain `out/` of HTML/JS that
drops onto seed1's nginx — no node runtime in production.

## Dev

```bash
cd web
npm install
npm run dev          # localhost:3000
```

Pages live under `src/app/`:

- `/` — hero, install one-liner, feature grid
- `/how-it-works/`
- `/install/`
- `/docs/` — index + links to authoritative repo docs
- `/community/` — GitHub, status, contribute

Shared layout in `src/app/layout.tsx`. `src/components/{Nav,Footer,Code}.tsx`.

## Build + deploy

```bash
npm run build        # produces out/
./scripts/deploy.sh  # builds + rsyncs out/ to seed1
```

Deploy uses `~/.ssh/intelnav_seed1` and writes to
`/var/www/intelnav` on seed1. Override with `DEPLOY_HOST=...` /
`DEPLOY_PATH=...` env vars.

## Why no shadcn

The site is marketing + docs — no forms, no dialogs, no command
palettes. shadcn would dump 50+ component files into the repo as dead
weight. Tailwind alone covers what we need. If we hit a real interactive
need later (e.g. a docs sidebar with collapsible sections), we'll add
it lazily with `npx shadcn add <component>`.

## Why Tailwind v3 not v4

Tailwind v3 has more battle-tested patterns + clearer config story.
v3 → v4 migration is a small lift when we want it. Not worth the
"it's the latest" tax for a five-page static site.
