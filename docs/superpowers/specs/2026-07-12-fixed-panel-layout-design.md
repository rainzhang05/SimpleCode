# Fixed Panel Layout Design

## Goal

Keep the liquid-glass file sidebar and terminal visually fixed in size while they slide fully into and out of the workspace, and reserve enough editor space that the sidebar never covers code.

## Layout

The workspace keeps its current layered `ZStack` so both glass panels remain mounted and the terminal process is not recreated. When the sidebar is visible, the editor receives a leading reservation equal to the sidebar width plus the two surrounding panel insets. When hidden, that reservation becomes zero. The sidebar remains a fixed-width overlay in the reserved lane.

The sidebar keeps constant top and bottom insets regardless of terminal visibility. This removes the existing height change during terminal transitions. The terminal remains a fixed-height bottom overlay.

## Motion

Both panels use offset-only motion with no opacity or scale animation:

- The sidebar moves from zero to a negative offset equal to its width plus its surrounding insets.
- The terminal moves from zero to a positive offset equal to its height plus its bottom inset.
- Normal motion uses a non-spring `easeInOut` animation lasting 0.20 seconds.
- Reduce Motion disables the animation but still applies the correct visible or hidden offset immediately.

The views remain mounted and keep their configured frames throughout the transition.

## Verification

Pure layout helpers will define editor reservation and hidden offsets. Unit tests will prove that hidden panels travel their complete dimensions, visible panels use zero offset, and visibility does not alter configured panel width or height. The existing terminal identity and geometry tests will guard against lifecycle regressions. A full unit run and macOS build will precede the push.

## Git and Xcode

All implementation commits are made directly on `main` with short messages, no commit bodies, and no coauthor trailers. The obsolete repair worktree and branch are removed after verification. The main Xcode project at `/Users/rainzhang/SimpleCode/SimpleCode.xcodeproj` is opened explicitly after `main` is pushed.
