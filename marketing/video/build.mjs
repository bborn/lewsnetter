// Full video pipeline:
//   1. Records each intro/outro HTML card as a 3-4 sec MP4 (Playwright)
//   2. Reads the screencast (recorded separately via record.mjs)
//   3. Concats: intro + overlay-annotated screencast + outro
//   4. (Wave 2) overlays bottom-third text at scene timings
//   5. (Wave 2) mixes music track from marketing/video/music.mp3 if present
//
// Run: node marketing/video/build.mjs
import { chromium } from "playwright"
import { execSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"

const VIEWPORT = { width: 1440, height: 900 }
const CARDS_DIR = "marketing/video/cards"
const RAW_DIR   = "marketing/video/raw"
const OUT_DIR   = "marketing/video"

// Record one card HTML page as a fixed-duration MP4 by recording its
// animation playback in Playwright, then ffmpeg-converting to MP4.
async function recordCard(name, durationMs) {
  const tmpDir = path.join(RAW_DIR, `card_${name}`)
  if (fs.existsSync(tmpDir)) fs.rmSync(tmpDir, { recursive: true })
  fs.mkdirSync(tmpDir, { recursive: true })

  const browser = await chromium.launch({ headless: true })
  const ctx = await browser.newContext({
    viewport: VIEWPORT,
    recordVideo: { dir: tmpDir, size: VIEWPORT },
    deviceScaleFactor: 2
  })
  const page = await ctx.newPage()
  await page.goto(`file://${path.resolve(CARDS_DIR, `${name}.html`)}`)
  // Let fonts + animations land before we start counting
  await page.waitForLoadState("networkidle")
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(durationMs)
  await ctx.close()
  await browser.close()

  const webm = fs.readdirSync(tmpDir).find(f => f.endsWith('.webm'))
  const inPath  = path.join(tmpDir, webm)
  const outPath = path.join(OUT_DIR, `${name}.mp4`)
  execSync(
    `ffmpeg -y -i "${inPath}" -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -movflags +faststart "${outPath}"`,
    { stdio: "ignore" }
  )
  console.log(`  → ${outPath}`)
  return outPath
}

// Highlight-reel overlays — designed panels (HTML rendered as
// transparent PNGs by Playwright) composited onto the screencast with
// timed fade-in/out. Each scene gets a chapter chip + headline + sub.
//
// pos: tl/tr/bl/br to keep the panel off the part of the UI we're
// highlighting. headline can wrap *…* for accent-orange phrases.
const SCREENCAST_OVERLAYS = [
  { in:  1.0, out:  5.5, pos: "br", num: "01", label: "Dashboard",
    headline: "Last sent. *What's queued.* Who's left.",
    sub: "KPI strip + recent campaigns, all on one screen." },

  { in:  7.5, out: 12.0, pos: "br", num: "02", label: "Segment builder",
    headline: "Build audiences with a *visual rule tree.*",
    sub: "Nested AND/OR, type-aware operators." },

  { in: 14.5, out: 21.0, pos: "br", num: "02", label: "Segment builder",
    headline: "*Live match count* as you build.",
    sub: "Sample rows show why each subscriber matched." },

  { in: 22.5, out: 30.0, pos: "br", num: "02", label: "Segment builder",
    headline: "Number, datetime, *array, CSV-list* operators.",
    sub: "Inferred from your data shape — no schema config." },

  { in: 36.0, out: 42.0, pos: "br", num: "03", label: "Campaign editor",
    headline: "Markdown or MJML. *Liquid* personalization.",
    sub: "Preview matches what your subscriber receives." },

  { in: 48.0, out: 54.0, pos: "br", num: "04", label: "Developer setup",
    headline: "One click → *sync token + initializer.*",
    sub: "Paste into your Rails app. Done." },

  { in: 56.0, out: 63.0, pos: "br", num: "04", label: "Developer setup",
    headline: "Live sync. *Nightly backfill.*",
    sub: "Your app stays source of truth; Lewsnetter mirrors." }
]

// Render the overlay timeline via Remotion. Scene timings + copy live
// in marketing/video/remotion/src/Overlays.tsx — edit there to iterate.
// Output is a ProRes 4444 MOV with full alpha channel.
function renderRemotionOverlays() {
  const out = path.join(OUT_DIR, "remotion", "out", "overlays.mov")
  execSync(
    `cd ${path.join(OUT_DIR, "remotion")} && npx remotion render src/index.ts Overlays out/overlays.mov --pixel-format=yuva444p10le --codec=prores --prores-profile=4444 --image-format=png --log=warn`,
    { stdio: "inherit" }
  )
  return out
}

;(async () => {
  console.log("Building intro card (4 sec)…")
  const intro = await recordCard("intro", 4000)

  console.log("Building MCP-chat card (6 sec — staggered animation)…")
  const mcp = await recordCard("mcp", 6000)

  console.log("Building outro card (5 sec)…")
  const outro = await recordCard("outro", 5000)

  const screencast = path.join(OUT_DIR, "landing-demo.mp4")
  if (!fs.existsSync(screencast)) {
    console.error(`ERROR: ${screencast} not found. Run record.mjs first + ffmpeg-convert.`)
    process.exit(1)
  }

  console.log("Rendering Remotion overlay timeline (ProRes 4444 w/ alpha)…")
  const overlayMov = renderRemotionOverlays()

  console.log("Compositing Remotion overlays onto screencast…")
  const screencastWithText = path.join(OUT_DIR, "landing-demo-overlaid.mp4")
  // Single overlay filter — the Remotion MOV already has timing baked in
  // (transparent everywhere except during active scenes), so we just
  // alpha-composite it onto the base. format=auto preserves the 10-bit
  // alpha channel from the ProRes source.
  execSync(
    `ffmpeg -y -i "${screencast}" -i "${overlayMov}" -filter_complex "[0:v][1:v]overlay=0:0:format=auto[vout]" -map "[vout]" -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -movflags +faststart "${screencastWithText}"`,
    { stdio: "inherit" }
  )

  console.log("Concatenating intro + screencast(overlaid) + mcp + outro…")
  const concatList = path.join(OUT_DIR, "concat.txt")
  fs.writeFileSync(concatList, [
    `file '${path.basename(intro)}'`,
    `file '${path.basename(screencastWithText)}'`,
    `file '${path.basename(mcp)}'`,
    `file '${path.basename(outro)}'`
  ].join("\n"))

  const finalNoAudio = path.join(OUT_DIR, "landing-demo-final.mp4")
  execSync(
    `cd ${OUT_DIR} && ffmpeg -y -f concat -safe 0 -i concat.txt -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -movflags +faststart "${path.basename(finalNoAudio)}"`,
    { stdio: "inherit" }
  )

  // Mix in the music track if one's present (drop into marketing/video/music.mp3).
  const music = path.join(OUT_DIR, "music.mp3")
  if (fs.existsSync(music)) {
    console.log("Mixing in music.mp3…")
    const withAudio = path.join(OUT_DIR, "landing-demo-final-audio.mp4")
    execSync(
      `ffmpeg -y -i "${finalNoAudio}" -i "${music}" -c:v copy -c:a aac -b:a 128k -shortest -af "afade=t=in:st=0:d=0.5,afade=t=out:st=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 ${finalNoAudio} | awk '{print $1 - 1.5}'):d=1.5,volume=0.35" -movflags +faststart "${withAudio}"`,
      { stdio: "inherit" }
    )
    console.log(`✅ ${withAudio}`)
  } else {
    console.log("⊝ No music.mp3 — final has no soundtrack")
    console.log(`✅ ${finalNoAudio}`)
    console.log("\nDrop a track at marketing/video/music.mp3 + re-run to add audio.")
  }
})().catch(e => { console.error(e); process.exit(1) })
