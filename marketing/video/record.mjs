// Drives the local dev server through a ~60-sec product walkthrough +
// records it as WebM. Convert to MP4 with: ffmpeg -i raw/*.webm -c:v
// libx264 -crf 20 -preset slow -movflags +faststart landing-demo.mp4
//
// Pre-reqs (run from repo root):
//   - bin/dev running on :3000
//   - Local seed via `LEWSNETTER_SKIP_SEEDING=true bin/rails runner /tmp/seed_demo.rb`
//   - User: qa@local.test / password123
//   - Demo team slug: nvoZjB
//
// Run: node marketing/video/record.mjs
import { chromium } from "playwright"
import fs from "fs"
import path from "path"

const BASE = "http://localhost:3000"
const EMAIL = "qa@local.test"
const PASSWORD = "password123"
const DEMO_TEAM = "RegYjK"

// 1440x900 is good for embedding into a landing page or compressing for
// the OG card. The video size matches the viewport size.
const VIEWPORT = { width: 1440, height: 900 }

const RAW_DIR = "marketing/video/raw"

// Tiny helper — wait + move cursor a bit so the recording feels organic
// instead of robotic. Avoids dead-air pauses while letting the UI breathe.
const pause = async (page, ms) => page.waitForTimeout(ms)

;(async () => {
  // Wipe old recordings so we always pick up the newest one cleanly
  if (fs.existsSync(RAW_DIR)) fs.rmSync(RAW_DIR, { recursive: true })
  fs.mkdirSync(RAW_DIR, { recursive: true })

  const browser = await chromium.launch({ headless: true })
  const context = await browser.newContext({
    viewport: VIEWPORT,
    recordVideo: { dir: RAW_DIR, size: VIEWPORT },
    deviceScaleFactor: 2  // crisp screenshots / video on retina
  })
  const page = await context.newPage()

  console.log("→ disable rack-mini-profiler badge")
  // Setting pp=disable once via query param stickies a cookie so the
  // badge stays hidden across subsequent navigations.
  await page.goto(`${BASE}/users/sign_in?pp=disable`)
  await page.waitForLoadState("networkidle")

  console.log("→ signing in")
  await page.goto(`${BASE}/users/sign_in`)
  await page.locator('input[type=email]').fill(EMAIL)
  await page.locator('form').first().evaluate(f => f.requestSubmit())
  await page.waitForLoadState("networkidle")
  await page.locator('input[type=password]').fill(PASSWORD)
  await page.locator('form').first().evaluate(f => f.requestSubmit())
  await page.waitForURL(/\/account/, { timeout: 10000 })

  console.log("→ switch to demo team")
  await page.goto(`${BASE}/account/teams/${DEMO_TEAM}`)
  await page.waitForLoadState("networkidle")
  await pause(page, 4900)  // dashboard hero — let KPI strip land

  console.log("→ segments index")
  await page.goto(`${BASE}/account/teams/${DEMO_TEAM}/segments`)
  await page.waitForLoadState("networkidle")
  await pause(page, 2100)

  console.log("→ new segment")
  await page.goto(`${BASE}/account/teams/${DEMO_TEAM}/segments/new`)
  await page.waitForLoadState("networkidle")
  await pause(page, 2100)

  console.log("→ name the segment")
  await page.locator('input[name="segment[name]"]').fill("US paid customers")
  await pause(page, 1400)

  console.log("→ pick field (mrr)")
  await page.evaluate(() => {
    const el = document.querySelector('.segments-builder__field-select')
    el.tomselect.addItem('custom_attributes.mrr')
  })
  await pause(page, 1400)

  console.log("→ pick operator (greater than)")
  await page.evaluate(() => {
    const op = [...document.querySelectorAll('.segments-builder__operator-select')].filter(e => e.tomselect)[0]
    op.tomselect.addItem('greater_than')
  })
  await pause(page, 1120)

  console.log("→ set value (0)")
  await page.evaluate(() => {
    const numInput = document.querySelector('input[type="number"][placeholder="number"]')
    if (numInput) {
      numInput.value = '0'
      numInput.dispatchEvent(new Event('input', { bubbles: true }))
    }
  })
  await pause(page, 4900)  // viewer reads MATCHING ~30

  console.log("→ add rule (country = US)")
  await page.evaluate(() => {
    const btn = document.querySelector('[data-action*="addRule"]')
    btn?.click()
  })
  await pause(page, 2100)
  await page.evaluate(() => {
    const els = [...document.querySelectorAll('.segments-builder__field-select')].filter(e => e.tomselect)
    els[els.length - 1].tomselect.addItem('custom_attributes.country')
  })
  await pause(page, 1120)
  await page.evaluate(() => {
    const valEls = [...document.querySelectorAll('select[data-segments-builder-enhance="value"]')].filter(e => e.tomselect)
    const lastTs = valEls[valEls.length - 1]
    if (lastTs) {
      lastTs.tomselect.addItem('US')
      return
    }
    const txt = document.querySelectorAll('input[type=text][placeholder="value"]')
    const t = txt[txt.length - 1]
    if (t) {
      t.value = 'US'
      t.dispatchEvent(new Event('input', { bubbles: true }))
    }
  })
  await pause(page, 4900)  // viewer reads narrowed MATCHING (~12)

  console.log("→ scroll down to sample rows")
  await page.evaluate(() => window.scrollTo({ top: 600, behavior: 'smooth' }))
  await pause(page, 5600)  // dwell on the sample list

  console.log("→ back to dashboard")
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'smooth' }))
  await pause(page, 840)
  await page.goto(`${BASE}/account/teams/${DEMO_TEAM}`)
  await page.waitForLoadState("networkidle")
  await pause(page, 2800)

  console.log("→ campaign edit")
  // Find the draft campaign
  const draftHref = await page.locator('a:has-text("heads-up about pricing")').first().getAttribute('href')
  if (draftHref) {
    await page.goto(`${BASE}${draftHref.replace(/\/$/, '')}/edit`)
    await page.waitForLoadState("networkidle")
    await pause(page, 5600)
    await page.evaluate(() => window.scrollTo({ top: 400, behavior: 'smooth' }))
    await pause(page, 4200)
  }

  console.log("→ developer setup (sync token + initializer snippet)")
  await page.goto(`${BASE}/account/teams/${DEMO_TEAM}/developers`)
  await page.waitForLoadState("networkidle")
  await pause(page, 2800)
  await page.evaluate(() => window.scrollTo({ top: 600, behavior: 'smooth' }))
  await pause(page, 5600)

  console.log("→ landing page closer")
  await page.evaluate(async () => {
    // sign out so the landing renders, not the redirect to dashboard
    const csrf = document.querySelector('meta[name=csrf-token]')?.content
    await fetch('/users/sign_out', { method: 'DELETE', headers: { 'X-CSRF-Token': csrf } })
  })
  await page.goto(`${BASE}/`)
  await page.waitForLoadState("networkidle")
  await pause(page, 4900)

  console.log("→ closing — context.close() finalizes the video file")
  await context.close()
  await browser.close()

  // Surface the final video path
  const files = fs.readdirSync(RAW_DIR).filter(f => f.endsWith('.webm'))
  console.log("\n✅ recorded:", path.join(RAW_DIR, files[0]))
  console.log("\nConvert + compress for the landing page:")
  console.log(`  ffmpeg -i ${path.join(RAW_DIR, files[0])} -c:v libx264 -crf 20 -preset slow -movflags +faststart marketing/video/landing-demo.mp4`)
})().catch(e => { console.error(e); process.exit(1) })
