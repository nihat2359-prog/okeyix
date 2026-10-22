BEGIN;
SET LOCAL request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
SELECT public.okeyix_quick_play('50000000-0000-0000-0000-000000000002','standard','start');
SELECT pg_sleep(1);
COMMIT;
