// Single highlight-reel overlay panel. Driven by props from the
// Composition timeline. Animations:
//   - Panel: slide in + fade in via spring; slide-out + fade out at tail
//   - Chip: scale-pop from 0.6 → 1 just after panel arrives
//   - Headline + sub: single fade-in, slight stagger
import React from "react"
import { interpolate, spring, useCurrentFrame } from "remotion"

export type OverlayPos = "tl" | "tr" | "bl" | "br"

export type OverlayProps = {
  num: string
  label: string
  // headline supports *…* for orange accent (can span multiple words)
  headline: string
  sub?: string
  pos: OverlayPos
  // Frames within the parent Sequence — 0 = panel enters
  durationInFrames: number
  fps: number
}

// Hard-constrained panel width so the headline always wraps inside the
// panel border instead of bleeding past it.
const PANEL_WIDTH = 480

const POSITION_STYLES: Record<OverlayPos, React.CSSProperties> = {
  tl: { top: 50,    left: 50 },
  tr: { top: 50,    right: 50 },
  bl: { bottom: 80, left: 50 },
  br: { bottom: 80, right: 50 }
}

const ENTER_OFFSETS: Record<OverlayPos, { x: number; y: number }> = {
  tl: { x: -24, y: 0 },
  tr: { x:  24, y: 0 },
  bl: { x: -24, y: 0 },
  br: { x:  24, y: 0 }
}

// Parse a headline string with *…* accent markers into a list of segments.
// Multi-word accents like "*What's queued.*" work correctly (the previous
// per-word approach broke because *What's and queued.* are separate tokens).
type Segment = { text: string; accent: boolean }
function parseHeadline(s: string): Segment[] {
  const out: Segment[] = []
  let rest = s
  while (rest.length > 0) {
    const m = rest.match(/^\*([^*]+)\*/)
    if (m) {
      out.push({ text: m[1], accent: true })
      rest = rest.slice(m[0].length)
      continue
    }
    const next = rest.indexOf("*")
    if (next === -1) {
      out.push({ text: rest, accent: false })
      break
    }
    out.push({ text: rest.slice(0, next), accent: false })
    rest = rest.slice(next)
  }
  return out
}

export const Overlay: React.FC<OverlayProps> = ({
  num, label, headline, sub, pos, durationInFrames, fps
}) => {
  const frame = useCurrentFrame()

  const enterProgress = spring({
    frame, fps,
    config: { damping: 18, mass: 0.7, stiffness: 110 }
  })
  const exitStart = durationInFrames - 12
  const exitProgress = interpolate(
    frame, [exitStart, durationInFrames], [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  )

  const offset = ENTER_OFFSETS[pos]
  const tx = interpolate(enterProgress, [0, 1], [offset.x, 0])
  const ty = interpolate(enterProgress, [0, 1], [offset.y, 0]) + (exitProgress * 16)
  const opacity = enterProgress * (1 - exitProgress)

  const chipProgress = spring({
    frame: frame - 4, fps,
    config: { damping: 12, mass: 0.5, stiffness: 200 }
  })
  const chipScale = interpolate(chipProgress, [0, 1], [0.6, 1])

  const headlineOpacity = interpolate(frame, [6, 16], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp"
  })
  const subOpacity = interpolate(frame, [12, 22], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp"
  })

  const segments = parseHeadline(headline)

  return (
    <div
      style={{
        position: "absolute",
        ...POSITION_STYLES[pos],
        width: PANEL_WIDTH,
        boxSizing: "border-box",
        padding: "22px 26px",
        background: "rgba(15, 15, 17, 0.94)",
        backdropFilter: "blur(12px)",
        WebkitBackdropFilter: "blur(12px)",
        border: "1px solid rgba(255, 255, 255, 0.08)",
        borderLeft: "3px solid #ea580c",
        borderRadius: 14,
        color: "#fafafa",
        fontFamily: "'Geist', system-ui, sans-serif",
        WebkitFontSmoothing: "antialiased",
        boxShadow: "0 18px 50px rgba(0, 0, 0, 0.4)",
        transform: `translate(${tx}px, ${ty}px)`,
        opacity,
        // Defensive: ensure normal wrapping regardless of inherited styles
        whiteSpace: "normal",
        wordBreak: "normal",
        overflowWrap: "anywhere"
      }}
    >
      {/* Chapter label row */}
      <div style={{
        display: "flex", alignItems: "center", gap: 10,
        fontFamily: "'Geist Mono', monospace",
        fontSize: 12, fontWeight: 500,
        letterSpacing: "0.14em",
        textTransform: "uppercase",
        color: "#fb923c",
        marginBottom: 14
      }}>
        <span style={{
          display: "inline-flex", alignItems: "center", justifyContent: "center",
          width: 26, height: 26,
          background: "#ea580c", color: "#fff",
          borderRadius: 6,
          fontSize: 12, fontWeight: 600, letterSpacing: 0,
          transform: `scale(${chipScale})`,
          transformOrigin: "center"
        }}>{num}</span>
        <span>{label}</span>
      </div>

      {/* Headline — single fade, multi-word accent support */}
      <div style={{
        fontSize: 26, fontWeight: 600,
        letterSpacing: "-0.01em",
        lineHeight: 1.2,
        marginBottom: sub ? 10 : 0,
        color: "#fafafa",
        opacity: headlineOpacity
      }}>
        {segments.map((seg, i) => (
          <span key={i} style={{ color: seg.accent ? "#fb923c" : undefined }}>
            {seg.text}
          </span>
        ))}
      </div>

      {sub && (
        <div style={{
          fontSize: 14, lineHeight: 1.5, color: "#a1a1aa",
          opacity: subOpacity
        }}>{sub}</div>
      )}
    </div>
  )
}
