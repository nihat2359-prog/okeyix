# Rating progression

Prepared migration: `supabase/migrations/20261023000200_rating_progression.sql`.
Not applied remotely. Changes only the reward expression in the supplied live
`okeyix_stat_private.source_game_finish(uuid,uuid,jsonb,jsonb)` definition.

| Winner's rating before the hand finishes | Table league | Award |
| --- | --- | --- |
| Below 3000 | standard / bronze / silver / gold | +60 |
| 3000 or above | Any league | +5 |
| Any | elite | +5 |
| Below 3000 | Unknown league (existing fallback) | +8 |

Normal losses still award/deduct no rating. No participation points, historical
rating conversion, coin changes, league-threshold changes, or new public RPC.
Bot and human wins use the existing finish path. Okey/double wins receive the
same rating award as normal wins.

From 1200, wins 29/30/31 in standard reach 2940/3000/3005. Coin eligibility still
applies: reaching 3000 does not itself provide the 3 million coins for elite.
Existing players at 3000 or above immediately use +5 on subsequent wins.

## Validation and rollout

Run the local checks with the original supplied function-definition JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/test_rating_progression.ps1 -SourceDefinitionPath <original-json-path>
```

The runner uses a fresh local PostgreSQL 16 cluster, verifies its data directory,
applies the migration twice, evaluates the actual patched reward expression, and
checks existing function grants, owner and security mode. It does not run a full
Supabase match or contact a remote database.

Stage the migration first and test real player/bot finishes, normal/okey/pairs
finishes, unchanged loser rating and coin payments, and statistics receipt deltas.
Then deploy the same migration explicitly. No Flutter release is required for
the server award change. The source fingerprint guard deliberately rejects a
different live function; review and regenerate against that version rather than
removing the guard. Reapplying the identical patched version is a no-op.
