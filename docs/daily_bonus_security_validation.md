# Daily bonus security validation

This change is local only. No migration has been applied to any database.

## Compatibility and permissions

- RPC signature remains `claim_daily_bonus(uuid, integer, text) -> boolean`.
- The authenticated JWT subject must match `p_user_id`; amount/day inputs are ignored.
- The server grants 2500 coins per Europe/Istanbul calendar day.
- The previous daily-bonus unique index is required and is reused.
- PUBLIC and anon privileges are revoked; authenticated receives EXECUTE.
- CREATE OR REPLACE retains the owner and any other existing role grants. Audit
  all effective grants and role memberships before deployment; these cannot be
  established from repository files. No RLS or table privileges are changed.
- SECURITY DEFINER remains necessary for the controlled credit. Check its owner
  and ensure clients cannot directly update profile coins or create/edit/delete
  credit ledger entries. Review other wallet flows before changing table grants.
- Legacy clients still use device dates for dialog availability/local caching.
  The server is authoritative, but a device timezone mismatch may hide an eligible
  claim or show a dialog for an already-claimed day. Review timezone rollover and
  historical day keys before rollout; this migration does not rewrite history.

## Required isolated database tests before deployment

Use a disposable local/staging schema with the actual profile/ledger constraints
and triggers, and real authenticated role/JWT contexts. Do not run these credit
tests on production accounts. SQL integration tests were not run here because
no local PostgreSQL runtime was available.

1. Signed-out calls fail, including calls using another user's ID.
2. User A cannot claim for user B; neither balance nor ledger changes.
3. A first claim with altered amount and day inputs credits exactly 2500 and
   stores the server-generated Istanbul day key.
4. Repeating with different client day/amount inputs returns false, with no
   second credit.
5. Two independent concurrent sessions for the same user/day produce exactly
   one true result, one ledger credit and a balance increase of exactly 2500.
6. An authenticated user without a profile receives an error and no ledger row
   survives (including when foreign keys reject the insert first).
7. Injected ledger/profile failures roll back all effects. Verify existing
   triggers do not independently add another 2500 to the balance.
8. Test just before/after Istanbul midnight with a controlled database clock
   harness, plus clients using other timezones and older app versions.
9. Verify actual function definition, unique-index validity, owner, all overloads,
   effective EXECUTE grants, RLS policies and direct column/table write access.

## Flutter checks

Run `flutter test --no-pub`. The dialog tests cover rapid repeated taps, pending
progress, error/retry, and completion after disposal. The RPC call and other
wallet, purchase and game operations are unchanged.
