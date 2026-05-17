import React from "react"
import { Composition } from "remotion"
import { Overlays } from "./Overlays"

// 65 sec @ 30fps = 1950 frames. Matches the screencast (record.mjs
// produces a ~65s WebM that we ffmpeg-convert to MP4 at 25fps; we
// render overlays at 30 for smoother motion and let ffmpeg handle the
// fps reconciliation during composite).
export const RemotionRoot: React.FC = () => (
  <Composition
    id="Overlays"
    component={Overlays}
    durationInFrames={1950}
    fps={30}
    width={1440}
    height={900}
  />
)
