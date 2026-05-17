// Generates background music via Replicate's Stable Audio Open
// (Stability AI). Better punch + production clarity than MusicGen for
// EDM / energetic instrumentals. Writes a 28-sec seed clip to
// marketing/video/music_seed.mp3 which the loop step in build.mjs
// fans out to 80 sec.
//
// Run: REPLICATE_API_TOKEN=r8_xxx node marketing/video/music.mjs
import fs from "node:fs"
import path from "node:path"

const TOKEN = process.env.REPLICATE_API_TOKEN
if (!TOKEN) {
  console.error("ERROR: set REPLICATE_API_TOKEN env var")
  process.exit(1)
}

// Stable Audio Open by Stability AI — better than MusicGen at
// rhythmic/punchy instrumentals; trained on production-quality samples.
const MODEL_VERSION = "9aff84a639f96d0f7e6081cdea002d15133d0043727f849c40abdd166b7c75a8"
const PROMPT = "high-energy upbeat electronic dance music, driving four-on-the-floor kick drum, bright melodic synth lead, punchy bass, fast arpeggio, crisp hi-hats, optimistic tech startup launch trailer, 124 BPM, full energy throughout, no vocals"
const NEGATIVE = "ambient, slow, sleepy, lo-fi, downtempo, vocals, breakdown, drop"
// Stable Audio's hard ceiling is 47 sec per call. We generate ~28 sec
// and loop in build.mjs to fill the 80-sec timeline.
const SECONDS = 28
const OUT = "marketing/video/music_seed.mp3"

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  })
  if (!res.ok) throw new Error(`${method} ${url} → ${res.status}: ${await res.text()}`)
  return res.json()
}

;(async () => {
  console.log(`→ creating Stable Audio Open prediction (${SECONDS}s)…`)
  const prediction = await api("POST", "https://api.replicate.com/v1/predictions", {
    version: MODEL_VERSION,
    input: {
      prompt: PROMPT,
      negative_prompt: NEGATIVE,
      seconds_total: SECONDS,
      seconds_start: 0,
      steps: 100,
      cfg_scale: 6.0,
      sampler_type: "dpmpp-3m-sde"
    }
  })

  console.log(`  prediction id: ${prediction.id}`)
  let p = prediction
  while (p.status === "starting" || p.status === "processing") {
    await new Promise(r => setTimeout(r, 4000))
    p = await api("GET", `https://api.replicate.com/v1/predictions/${prediction.id}`)
    console.log(`  ${p.status}…`)
  }
  if (p.status !== "succeeded") {
    console.error(`prediction failed: ${p.status} — ${JSON.stringify(p.error)}`)
    process.exit(1)
  }

  // Output is WAV. Pipe through ffmpeg to MP3 so build.mjs's loop step
  // (which expects MP3) keeps working.
  console.log(`→ downloading WAV from ${p.output}`)
  const audio = await fetch(p.output)
  if (!audio.ok) throw new Error(`download → ${audio.status}`)
  const wavBuf = Buffer.from(await audio.arrayBuffer())
  const wavPath = "marketing/video/music_seed.wav"
  fs.writeFileSync(wavPath, wavBuf)

  const { execSync } = await import("node:child_process")
  execSync(`ffmpeg -y -i "${wavPath}" -codec:a libmp3lame -qscale:a 2 "${OUT}"`, { stdio: "ignore" })
  fs.unlinkSync(wavPath)
  const finalBuf = fs.readFileSync(OUT)
  console.log(`✅ wrote ${OUT} (${(finalBuf.length / 1024 / 1024).toFixed(2)} MB)`)
  console.log(`\nNext: node marketing/video/build.mjs`)
})().catch(e => { console.error(e); process.exit(1) })
