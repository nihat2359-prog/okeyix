# Stage 2: presentation network reads

Local changes only. No live database, schema, RLS, RPC or deployment changes.
Stage 1 visual clocks, turn sounds and narrow HUD rebuilds are preserved.

## Inventory and scope

| Owner | Existing schedule / source | Change |
| --- | --- | --- |
| OkeyGameScreen | tables every 2s + table Realtime | Shared public projection |
| OkeyGameScreen | table_players and users every 2s + player Realtime | Shared seats, cached identities |
| GameAvatarOverlay | tables, leagues, table_players, profiles, users every 2s + Realtime | Same source as screen |
| OkeyGame | table state including deck every 1s | Unchanged |
| OkeyGame | discard tops every 1s + discard Realtime | Unchanged |
| OkeyGame | authoritative local hand check every 6s | Unchanged |
| OkeyGame | waiting/start watchdog, 100ms turn logic, move/table/player Realtime, RPC recovery | Unchanged |
| Game screen | chat, discards, spectators, finish snapshots, recording/storage, coin/RPC actions | Unchanged |
| Lobby and spectator mode | independent queries/channels | Outside this patch |

The screen creates and disposes one GameViewDataSource per game-screen lifetime.
Avatar overlays borrow it. No static cross-table cache and no source in the engine.
The public projection contains no deck or hands. Existing finished-round fields
remain available to the game screen; server authorization remains unchanged.

## Cache and recovery contract

- Table, seats and coin-bearing profile reads have a 200ms sharing window. This
  absorbs near-simultaneous consumers without replacing the existing 2s polling.
- User name/avatar/email rows: 60s; league turn_seconds: 5 minutes. The table's
  explicit turn_seconds still overrides the league value as before.
- Membership changes evict identity/profile caches. Applying an avatar roster
  requires matching the latest known membership. Auth changes invalidate caches;
  old-session/disposed results are rejected. A new game screen gets a new source.
- Both UI layers retain their original 2s polling even when Realtime is healthy.
  Identical events received by both layers invalidate once using commit timestamp.
  An event during a fetch invalidates that response and causes a serial re-read.
- Reconnect/resume clears caches and requests reconciliation. Reads failing due to
  errors are not cached. Continuous event bursts yield to the next polling tick
  after bounded retries; refresh queues do not run overlapping UI pipelines.
- Disposal rejects pending results and cancels the source's auth listener. It
  cannot abort an HTTP request already sent by the SDK; that request may finish,
  but it cannot publish to this disposed source or start a retry afterward.
- Existing UI Realtime channels and polling timers are still owned by their
  original widgets. Disposal removes these channels from the Supabase client,
  rather than only unsubscribing. This patch does not reduce active WebSocket
  subscriptions while the game is open.

## Query counts: model, not device measurements

Assumptions: two stable players, a league, successful normal schema reads, ongoing
game, no Realtime bursts/reconnects, email fallbacks, startup watchdog or recovery.

Before: UI screen 3 reads/2s, avatar 5 reads/2s = 240/minute.
Unchanged engine baseline: 60 table + 60 discard + 10 hand reads = 130/minute.
Total modeled baseline: approximately 370/minute.

Deterministic test: 30 coincident UI polling cycles invoke the fetch callbacks
92 times: table 30, seats 30, profiles 30, users 1, league 1. Compared with the
old call structure's 240 UI reads, this models 222 total reads in that minute
after including the unchanged engine. These are fake-backend invocations, not
captured production HTTP requests.

If the two UI polls consistently fall outside the 200ms sharing window, table
and seat reads can each occur 60 times/minute. The same model becomes about
282 total reads in the first minute. Actual requests can be higher with events,
errors and recovery. Cache warm-up and TTL boundaries also change the count.
There is no measured battery-saving percentage.

## Validation and deferred work

Automated tests cover concurrent consumers, polling after missing Realtime events,
duplicate events, event-during-fetch reconciliation, player replacement, catalog
expiry, session/table isolation, failed reads, disposal and queued refreshes.
Stage 1 visual-clock tests are also run.

Still required on two physical devices: draw/discard/deal, timeouts, join/leave,
finish/reward presentation, network loss/restoration and background/resume. Measure
real requests and bytes per minute on a controlled test account/environment.

The 1s deck fetch feeds deck visuals and turn/hand recovery. Removing its deck
column or weakening engine reconciliation without those tests is deliberately
deferred. Likewise, no engine polling frequency or game authority is changed.
