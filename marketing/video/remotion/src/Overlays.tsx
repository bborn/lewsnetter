// Timeline composition — places each Overlay panel onto the timeline
// with its scene timing. Times are in SECONDS (relative to the start of
// the screencast portion of the final video).
//
// The final composition is 65s @ 30fps = 1950 frames, matching the
// screencast we'll composite this onto.
import React from "react"
import { AbsoluteFill, Sequence, useVideoConfig } from "remotion"
import { Overlay, OverlayPos } from "./Overlay"

type Scene = {
  inSec: number
  outSec: number
  pos: OverlayPos
  num: string
  label: string
  headline: string
  sub?: string
}

const SCENES: Scene[] = [
  { inSec:  1.0, outSec:  5.5, pos: "br", num: "01", label: "Dashboard",
    headline: "Last sent. *What's queued.* Who's left.",
    sub: "KPI strip + recent campaigns, all on one screen." },
  { inSec:  7.5, outSec: 12.0, pos: "br", num: "02", label: "Segment builder",
    headline: "Build audiences with a *visual rule tree.*",
    sub: "Nested AND/OR, type-aware operators." },
  { inSec: 14.5, outSec: 21.0, pos: "br", num: "02", label: "Segment builder",
    headline: "*Live match count* as you build.",
    sub: "Sample rows show why each subscriber matched." },
  { inSec: 22.5, outSec: 30.0, pos: "br", num: "02", label: "Segment builder",
    headline: "Number, datetime, *array, CSV-list* operators.",
    sub: "Inferred from your data shape — no schema config." },
  { inSec: 36.0, outSec: 42.0, pos: "br", num: "03", label: "Campaign editor",
    headline: "Markdown or MJML. *Liquid* personalization.",
    sub: "Preview matches what your subscriber receives." },
  { inSec: 48.0, outSec: 54.0, pos: "br", num: "04", label: "Developer setup",
    headline: "One click → *sync token + initializer.*",
    sub: "Paste into your Rails app. Done." },
  { inSec: 56.0, outSec: 63.0, pos: "br", num: "04", label: "Developer setup",
    headline: "Live sync. *Nightly backfill.*",
    sub: "Your app stays source of truth; Lewsnetter mirrors." }
]

export const Overlays: React.FC = () => {
  const { fps } = useVideoConfig()
  return (
    <AbsoluteFill>
      {SCENES.map((s, i) => {
        const from = Math.round(s.inSec * fps)
        const duration = Math.round((s.outSec - s.inSec) * fps)
        return (
          <Sequence key={i} from={from} durationInFrames={duration}>
            <Overlay
              num={s.num}
              label={s.label}
              headline={s.headline}
              sub={s.sub}
              pos={s.pos}
              durationInFrames={duration}
              fps={fps}
            />
          </Sequence>
        )
      })}
    </AbsoluteFill>
  )
}
