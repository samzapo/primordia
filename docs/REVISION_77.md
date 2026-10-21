# Revision77 — one interface for mobile and desktop

Mobile is the design reference. One GameControls component builds the shared
Pause/Follow/Internal/music/zoom controls; one CellInterface builds the action
tray, resources, held-organ cancel and descriptions. They use viewport bounds
and CSS/native UI density, independent of touch capability. Family/investment
panels and particle descriptions follow the same layout. Old desktop radial
menus, five-choice paging, separate tissue comparison and keyboard prose are
removed. Existing accessibility keys still dispatch the common actions.

World clicks and taps share _tap then _activate_at: the same inspection,
family double-selection, merge, overlap-picker and optimistic placement paths.
Mouse press waits for release or an8CSS-pixel drag, so panning cannot install
an organ or activate a factory. Desktop left/middle drag and wheel adapt the
camera; touch retains its two-finger fixed-anchor pan/twist/pinch. GUI buttons
and scrolling panels keep priority. Family lists normalize mouse dragging to
the existing captured list gesture; release, focus loss and resize clear capture.
No server physics, chemistry, anatomy, resources or snapshots are changed.

Gameplay help has one common interaction list and only camera-specific input
sections. The same authored scripts build native and web clients; browsers load
one deployed game rather than independent mobile/desktop feature versions.
Native offline boot semantics remain unchanged.

The previous desktop/AP/resize interface fixtures are replaced by a smaller
paired contract over real current controls, menus and queued placement actions
at393x740and1280x720. Shared UI source cannot branch on input capability. Both
stable and experimental release builders run tools/check_interface.py after
resource import and before export/cutover, using isolated fixture preferences.
This is a bounded correctness check, not a rendering-speed test or phone FPS
claim. Keep its context/action coverage current when adding features. Native
and browser event fixtures additionally cover camera anchors and real input.

Experimental retains its pond and starts a fresh post-main cumulative preview.
Main remains on its accepted release until owner review/promotion.
