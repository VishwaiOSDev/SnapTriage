# Onboarding Design QA

## Comparison Target

- Source visual truth: `/var/folders/8g/0z1j30cd1yxc188j0x56fy040000gn/T/codex-clipboard-beaa0d02-e14f-48d6-858f-be285571bdd8.png`
- Final implementation capture: `/tmp/snaptriage-onboarding-final.png`
- Combined comparison: `/tmp/snaptriage-onboarding-final-comparison.png`
- State: dark appearance, first launch, Photos authorization not determined
- Simulator: iPhone Air, iOS 27.0

## Viewport And Normalization

- Source pixels: 1086 x 2410, including a photographed/rendered device frame and perspective.
- Implementation pixels: 1260 x 2736 at a 420 x 912 point viewport and 3x density.
- Comparison normalization: both complete images were proportionally scaled to 1600 px high and placed side by side. Device bezel, status bar, Dynamic Island, and home-indicator differences were treated as system/template chrome rather than app-owned fidelity issues.

## Full-View Comparison Evidence

The final capture preserves the reference hierarchy and visual rhythm: branded lockup, protected-photo hero, two-line privacy headline, supporting copy, a three-row privacy card, a single prominent access action, and a restrained helper note. The app-owned content remains readable and complete at the tested viewport, with the action anchored inside the bottom safe area.

No actionable P0, P1, or P2 differences remain. The final implementation intentionally uses the production app-icon artwork instead of the simplified mock icon and native status-bar chrome instead of reproducing the reference device frame.

## Focused Region Evidence

- Brand and hero: the real app-icon artwork is sharp at 46 pt; the hero uses an SF Symbol with a separate lock badge and matches the reference's blue-on-dark protected-library motif.
- Typography and copy: title weight, two-line wrapping, supporting-copy width, section heading, row labels, CTA copy, and two-line helper copy match the selected source structure.
- Privacy card and action: the final custom dark surface is materially closer to the source than the initial system-glass rendering, row dividers and icons remain crisp, and the capsule CTA stays fully visible above the bottom safe area.

## Required Fidelity Surfaces

- Fonts and typography: system San Francisco typography, semantic text styles, matching bold/regular hierarchy, stable wrapping, and Dynamic Type-compatible labels. No truncation is visible at the tested size.
- Spacing and layout rhythm: consistent 24 pt horizontal margins, balanced hero/title/section gaps, 72 pt trust rows, 24 pt continuous card radius, and a bottom-safe CTA. The layout scrolls when content needs more room.
- Colors and visual tokens: project background and accent tokens are used; white/secondary/tertiary semantic foregrounds retain contrast; the trust card uses a subtle dark fill and hairline stroke matching the source.
- Image quality and asset fidelity: the actual 1024 px Icon Composer artwork is reused from the project and compiled through the asset catalog. Standard UI iconography uses SF Symbols; no placeholder or handcrafted vector asset remains.
- Copy and content: all visible reference copy is localized, including the privacy section heading and access guidance.

## Interaction And Accessibility Evidence

- Activated `Choose Photo Access` in the running simulator.
- Confirmed that it presents the native Photos authorization sheet with Select Photos, Allow Full Access, and Don't Allow choices.
- Confirmed the brand, headline, supporting copy, privacy promises, CTA, and helper note appear as named accessibility elements.
- The app returned to the Photos-not-determined state after interaction testing; no access choice was persisted.

## Comparison History

1. Initial implementation capture: `/tmp/snaptriage-onboarding-pass-2.png`.
   - P2: the iOS glass card rendered substantially brighter than the source.
   - P2: the helper note remained on one line while the reference uses a narrower two-line measure.
   - Fixes: replaced the glass treatment with a token-driven dark surface and stroke; constrained the helper note to 300 pt.
2. Short-screen refinement.
   - P2: an intermediate capture revealed the scroll view could adopt its content's ideal height, allowing the fixed action region to fall outside the visible proposal.
   - Fixes: constrained the root scroll container to the available screen height and tightened only the vertical gaps needed to keep the privacy card complete.
3. Final evidence: `/tmp/snaptriage-onboarding-final.png` and `/tmp/snaptriage-onboarding-final-comparison.png`.
   - Post-fix result: the card, CTA, and helper note are all visible; the darker surface and two-line helper now match the reference treatment.

## Findings

No actionable P0/P1/P2 findings remain.

## Follow-up Polish

- P3: the production app icon is more detailed than the simplified icon in the mock. This is intentional brand fidelity rather than an implementation mismatch.

final result: passed
