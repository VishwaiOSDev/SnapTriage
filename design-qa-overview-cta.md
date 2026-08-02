# Design QA — Overview “Start triage” CTA

- Source visual truth: `/Users/vishweshwaran/.codex/visualizations/2026/07/15/019f6369-8c83-7940-8ec3-ff2028324a3b/figma-start-triage-reference-normalized.png`
- Implementation screenshot: `/Users/vishweshwaran/.codex/visualizations/2026/07/15/019f6369-8c83-7940-8ec3-ff2028324a3b/snaptriage-overview-icons-v3.png`
- Focused comparison: `/Users/vishweshwaran/.codex/visualizations/2026/07/15/019f6369-8c83-7940-8ec3-ff2028324a3b/snaptriage-overview-icons-comparison-v3.png`
- Viewport: iPhone 17, iOS 26.4, 402 × 874 points at 3×
- State: dark appearance, Overview loaded with stable sample summary data

## Full-view comparison evidence

The full simulator capture confirms that the CTA remains centered within the existing summary card, preserves the card’s horizontal insets, does not collide with the statistics or helper copy, and maintains the overview’s visual hierarchy. The source is a component crop rather than a full-screen design, so the surrounding app layout is treated as an existing product constraint rather than a comparison target.

## Focused region comparison evidence

The combined comparison normalizes both captures to the same pixel width. It confirms the sampled blue transition, capsule silhouette, bright edge rim, centered label, trailing chevron, and restrained elevation. The implementation retains the source’s native 56-point control height while responding to the narrower width inside the existing summary card.

## Required fidelity surfaces

- Fonts and typography: SF Pro through SwiftUI’s semantic `.body` style with medium weight; the label is centered, single-line, Dynamic Type-aware, and visually consistent with the reference.
- Spacing and layout rhythm: 56-point minimum height, capsule boundary, 22-point horizontal content inset, centered title, and independently trailing chevron. The button remains responsive instead of using screenshot-derived absolute positioning.
- Colors and visual tokens: reference samples range from approximately `#2874EB` at the brighter leading region to `#2269DE` at the deeper trailing region. `#2874EB` is now the shared asset-catalog accent for overview symbols and selected navigation, while the CTA maps the sampled range to a diagonal SwiftUI gradient with a subtle top sheen and blue rim.
- Image quality and asset fidelity: the design contains no raster artwork. The chevron uses the native `chevron.right` SF Symbol for sharp rendering, RTL behavior, and accessibility.
- Copy and content: “Start triage” matches the reference and the app’s localized string.
- Interaction and accessibility: the existing navigation action is preserved; the custom button style adds pressed brightness/scale feedback, and the decorative chevron is hidden from accessibility while the text remains the button label.

## Comparison history

### Pass 1

- [P2] The top highlight rendered brighter than the source sample.
- [P2] The blue shadow created a broader neon halo than the reference’s restrained elevation.
- Fixes: reduced the white sheen from 10% to 2.5%; reduced the blue shadow opacity from 30% to 10%, its radius from 11 to 8 points, and its vertical offset from 4 to 2 points.

### Pass 2

- Post-fix evidence: the normalized focused comparison shows the blue fill, rim, text, chevron, and surrounding shadow tracking the source without the earlier over-bright top or broad halo.
- No actionable P0, P1, or P2 differences remain.

### Pass 3

- [P2] Overview symbols and the selected tab still inherited the brighter system blue, visibly separating them from the Figma-derived CTA palette.
- Fixes: defined the sampled `#2874EB` as the asset-catalog `AccentColor`, routed overview accents and root navigation tint through that token, and reused it as the CTA's leading gradient stop.
- Post-fix evidence: the combined reference-and-simulator comparison shows the lock, statistic symbols, feature symbols, app mark, selected tab, and primary action reading as one coherent royal-blue family. Icon shapes, contrast, spacing, and hierarchy remain unchanged.

## Findings

No actionable P0, P1, or P2 findings remain.

## Follow-up polish

No P3 follow-up is necessary for the requested color-style match.

final result: passed
