# Player update notices

The owner approved the initial copy and voice on October 16, 2026. Every public
release updates scripts/network/release_notes.gd with a new stable release ID,
a short title and a few gameplay-focused bullets. Describe visible changes and
benefits in plain language. Avoid internal architecture, code/build identifiers,
profiling numbers and operational details. Keep the footer about retained cell
progress and the Back to the pond action. Future notices follow this approved
voice as part of normal release preparation; no recurring approval gate.

After authentication, the server sends the current notice only to accounts that
have not dismissed it. The client waits for the first ready world snapshot,
then shows a scrollable modal with a large tap target on portrait/landscape and
desktop. World snapshots keep arriving while it is open; camera/edit shortcuts
are blocked without pausing the pond. Disconnect/reconnect replaces stale notices.

Dismissal validates the current authored ID and saves seen_release in the existing
account checkpoint. Only confirmed saves dismiss the modal. Failure/timeouts
remain retryable; duplicate acknowledgement is harmless. Saved account identity
travels with the existing key, so another browser/device does not replay a seen
notice. Old cached clients can ignore the optional welcome field and will receive
it when they next load a client that supports the notice.


Gameplay and Mechanics are maintained in data/player_guide.json and rendered
by player_help.gd. Gameplay includes only the touch or desktop instructions for
the active interface. Mechanics groups active game rules with curated links
from references.md; historical/retired pathways are omitted. The source action
accepts only explicitly authored HTTPS URLs and opens them outside the game.

Every release review checks both help pages against changed interactions,
organs, chemistry and costs, and updates the player notes together. This is an
ongoing owner requirement, not an optional documentation follow-up. The first
approved notes retain their wording with an extra bullet for the requested
Gameplay/Mechanics addition.
