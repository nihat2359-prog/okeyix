# Supabase Kurulum: Zorunlu Adımlar

Bu dosya, mevcut Flutter kodunun (`Lobby`, `OkeyGame`, `GameAvatarOverlay`) sorunsuz çalışması için gereken minimum Supabase adımlarını içerir.

## 1) SQL Editor'da once kontrol (zorunlu)

```sql
-- users kolonlari
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'users'
order by ordinal_position;

| column_name       | data_type                   |
| ----------------- | --------------------------- |
| id                | uuid                        |
| username          | text                        |
| email             | text                        |
| avatar_url        | text                        |
| rating            | integer                     |
| elite_status      | boolean                     |
| is_banned         | boolean                     |
| ban_reason        | text                        |
| ban_until         | timestamp without time zone |
| is_suspended      | boolean                     |
| suspension_reason | text                        |
| suspension_until  | timestamp without time zone |
| created_at        | timestamp without time zone |
| auth_user_id      | uuid                        |

-- profiles kolonlari
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'profiles'
order by ordinal_position;

| column_name | data_type                   |
| ----------- | --------------------------- |
| id          | uuid                        |
| username    | text                        |
| rating      | integer                     |
| coins       | integer                     |
| avatar      | text                        |
| created_at  | timestamp without time zone |

-- tables kolonlari
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'tables'
order by ordinal_position;

| column_name   | data_type                |
| ------------- | ------------------------ |
| id            | uuid                     |
| league_id     | text                     |
| created_by    | uuid                     |
| created_at    | timestamp with time zone |
| status        | text                     |
| max_players   | integer                  |
| entry_coin    | integer                  |
| min_rounds    | integer                  |
| current_round | integer                  |
| current_turn  | integer                  |
| deck          | jsonb                    |
| shuffle_seed  | text                     |

-- table_players kolonlari
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'table_players'
order by ordinal_position;

| column_name | data_type                |
| ----------- | ------------------------ |
| id          | uuid                     |
| table_id    | uuid                     |
| user_id     | uuid                     |
| seat_index  | integer                  |
| hand        | jsonb                    |
| is_ready    | boolean                  |
| joined_at   | timestamp with time zone |
```

Kodun beklentisi (minimum):
- `users`: `id`, `email`, `username`, `avatar_url`, `rating`
- `profiles`: `id`, `coins`, `username`, `avatar_url`, `rating`
- `tables`: `id`, `league_id`, `status`, `max_players`, `entry_coin`, `min_rounds`, `created_by`, `current_turn`, `deck`
- `table_players`: `table_id`, `user_id`, `seat_index`, `hand`
- `wallet_transactions`: `user_id`, `amount`

## 2) Kritik constraint/fk (zorunlu)

```sql
-- Ayni masada ayni koltuga iki oyuncu oturmasin
create unique index if not exists table_seat_unique
  on public.table_players (table_id, seat_index);

-- tables.created_by -> auth.users(id)
alter table public.tables
  drop constraint if exists tables_created_by_fkey;

alter table public.tables
  add constraint tables_created_by_fkey
  foreign key (created_by) references auth.users(id)
  on delete cascade;

-- table_players.user_id -> auth.users(id)
alter table public.table_players
  drop constraint if exists table_players_user_id_fkey;

alter table public.table_players
  add constraint table_players_user_id_fkey
  foreign key (user_id) references auth.users(id)
  on delete cascade;

-- table_players.table_id -> tables(id)
alter table public.table_players
  drop constraint if exists table_players_table_id_fkey;

alter table public.table_players
  add constraint table_players_table_id_fkey
  foreign key (table_id) references public.tables(id)
  on delete cascade;
```

## 3) users kaydini garanti altina al (onerilen)

```sql
-- users tablosu auth user id ile birebir calissin
insert into public.users (id, email)
select au.id, au.email
from auth.users au
left join public.users u on u.id = au.id
where u.id is null;
```

Not: `username` onboardingde uygulama tarafinda zorunlu dolduruluyor.

## 4) Edge Function: start-game (zorunlu)

Kod masa dolunca su fonksiyonu cagiriyor:
- `supabase.functions.invoke('start-game', body: {'tableId': ..., 'table_id': ...})`
- Fallback olarak RPC `start_game(table_id uuid)` cagiriyor.

Yapilacaklar:
1. Supabase Dashboard -> Edge Functions -> `start-game` adinda function olustur.
2. Deploy et.
3. Function icinde hem `tableId` hem `table_id` payload'ini destekle.
4. Oyuncu sayisi `players.length == tables.max_players` degilse baslatma.
5. Basarili olunca:
   - `tables.status = 'playing'`
   - `tables.current_turn = 0`
   - `tables.deck` yaz
   - `table_players.hand` dagit

## 5) RPC fallback: start_game (zorunlu)

Eger Edge Function fail olursa client su RPC'yi deniyor: `start_game`.

```sql
create or replace function public.start_game(table_id uuid)
returns jsonb
language plpgsql
security definer
as $$
begin
  -- Basit fallback: Edge Function yoksa en azindan status gecebilsin.
  update public.tables
  set status = 'playing', current_turn = coalesce(current_turn, 0)
  where id = table_id and status = 'waiting';

  return jsonb_build_object('ok', true, 'table_id', table_id);
end;
$$;

grant execute on function public.start_game(uuid) to anon, authenticated, service_role;
```

Not: Bu fallback sadece acil durum icindir. Gercek dagitim/oyun state'i Edge Function'da olmalidir.

## 6) Welcome coin (gelistirme/test icin gerekli)

Uygulamada yerel coin floor var (`50000`), ama production'da DB tarafindan coin verilmesi daha dogru.

```sql
-- Ornek: tek seferlik hos geldin coin'i
insert into public.wallet_transactions (user_id, amount, type, note)
select u.id, 50000, 'welcome_bonus', 'one-time welcome coin'
from auth.users u
where not exists (
  select 1
  from public.wallet_transactions wt
  where wt.user_id = u.id and wt.type = 'welcome_bonus'
);
```

## 7) RLS (simdilik secenek)

Sende su an RLS kapaliydi (`rls_enabled = false`).
- Gelistirme hizli gitsin istiyorsan su an boyle kalabilir.
- Production'a cikmadan once RLS acilip policy yazilmali.

Minimum production policy kapsamı:
- `users`: kendi satirini `select/update`
- `table_players`: masadaki oyuncular `select`, sadece ilgili oyuncu `insert/delete`
- `tables`: waiting/playing listesi `select`, sadece olusturan `delete`
- `wallet_transactions`: sadece kendi islemlerini `select`

## 8) RPC Duzeltme Patch (zorunlu)

Asagidaki patch'i SQL Editor'da calistir:
- `game_discard` icinde joker kontrolu sadece `p_finish = false` iken ve otomatik timeout akisinda uygulanmali.
- Duz mantikta manuel atista joker engeli olursa oyuncu bazi taslari atamiyor gibi gorunur.

```sql
create or replace function public.game_discard(
  p_table_id uuid,
  p_user_id uuid,
  p_tile jsonb,
  p_finish boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_table record;
  v_player record;
  v_hand jsonb;
  v_next_turn int;
  v_before int;
  v_after int;
begin
  select id, status, current_turn, max_players
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then
    raise exception 'TABLE_NOT_FOUND';
  end if;
  if v_table.status <> 'playing' then
    raise exception 'TABLE_NOT_PLAYING';
  end if;

  select id, seat_index, hand
    into v_player
  from public.table_players
  where table_id = p_table_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'PLAYER_NOT_IN_TABLE';
  end if;
  if v_player.seat_index <> v_table.current_turn then
    raise exception 'NOT_YOUR_TURN';
  end if;

  v_hand := coalesce(v_player.hand, '[]'::jsonb);
  v_before := jsonb_array_length(v_hand);
  if v_before <> 15 then
    raise exception 'DISCARD_REQUIRES_15';
  end if;

  v_hand := public._hand_remove_first(v_hand, p_tile);
  v_after := jsonb_array_length(v_hand);
  if v_after <> v_before - 1 then
    raise exception 'TILE_NOT_IN_HAND';
  end if;

  insert into public.table_discards(
    table_id, seat_index, discarded_by_user_id, tile
  ) values (
    p_table_id, v_player.seat_index, p_user_id, p_tile
  );

  update public.table_players
    set hand = v_hand
  where id = v_player.id;

  v_next_turn := (v_table.current_turn + 1) % v_table.max_players;

  update public.tables
    set current_turn = v_next_turn,
        turn_started_at = now()
  where id = p_table_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'discard',
    'table_id', p_table_id,
    'seat_index', v_player.seat_index,
    'next_turn', v_next_turn,
    'turn_started_at', now(),
    'hand', v_hand
  );
end;
$$;

grant execute on function public.game_discard(uuid, uuid, jsonb, boolean)
  to authenticated, service_role;
```

## 9) start_game icin kritik not (zorunlu)

`start_game` fonksiyonunu sade bir `status='playing'` update'ine dusurme.
Bu, dagitim/deck state'ini bozup oyunu kilitler.

Dogru yontem:
- `docs/supabase_game_rpc.sql` dosyasinin TAMAMINI tekrar calistir.
- Bu dosya `start_game` dahil olmak uzere server-authoritative dagitimi iceriyor.

---

## Senden isteyecegim net cikti
Bu dosyadaki 1-5 adimlarini uyguladiktan sonra bana su 3 bilgiyi gonder:
1. `start-game` deploy edildi mi?
2. `start_game` RPC olustu mu?
3. SQL hatasi varsa tam hata metni.

Buna gore draw/discard RPC entegrasyonuna gecip client'i tamamen server-authoritative moda alacagim.

##start-game
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req) => {
  const { tableId } = await req.json();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // 1️⃣ Oyuncuları çek
  const { data: players, error } = await supabase
    .from("table_players")
    .select("*")
    .eq("table_id", tableId)
    .order("seat_index");

  if (error) {
    return new Response(JSON.stringify({ error }), { status: 400 });
  }

  if (!players || players.length === 0) {
    return new Response(JSON.stringify({ error: "No players" }), { status: 400 });
  }

  const playerCount = players.length;

  // 2️⃣ Full deck üret
  const fullDeck = generateFullDeck();

  // 3️⃣ Secure shuffle
  const shuffled = shuffle(fullDeck);

  // 4️⃣ Deal
  const hands: any[] = [];
  let index = 0;

  for (let i = 0; i < playerCount; i++) {
    hands.push(shuffled.slice(index, index + 14));
    index += 14;
  }

  const remainingDeck = shuffled.slice(index);

  // 5️⃣ Oyuncuların ellerini kaydet
  for (let i = 0; i < players.length; i++) {
    await supabase
      .from("table_players")
      .update({ hand: hands[i] })
      .eq("id", players[i].id);
  }

  // 6️⃣ Table update
  await supabase
    .from("tables")
    .update({
      deck: remainingDeck,
      status: "playing",
      current_turn: 0,
      shuffle_seed: crypto.randomUUID(),
    })
    .eq("id", tableId);

  return new Response(JSON.stringify({ success: true }), { status: 200 });
});


function generateFullDeck() {
  const colors = ["red", "blue", "black", "yellow"];
  const deck: any[] = [];

  for (let c of colors) {
    for (let n = 1; n <= 13; n++) {
      deck.push({ color: c, number: n });
      deck.push({ color: c, number: n });
    }
  }

  deck.push({ joker: true });
  deck.push({ joker: true });

  return deck;
}

function shuffle(array: any[]) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}


##validate-okey
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

type Tile = {
  color: "red" | "blue" | "black" | "yellow"
  number: number
  isJoker?: boolean
}

serve(async (req) => {
  const { tiles } = await req.json()
  const result = canFinish(tiles)

  return new Response(JSON.stringify({ valid: result }), {
    headers: { "Content-Type": "application/json" },
  })
})

function canFinish(tiles: Tile[]): boolean {
  if (tiles.length === 0) return true

  tiles = [...tiles].sort(tileSort)

  const first = tiles[0]

  const jokers = tiles.filter(t => t.isJoker)
  const nonJokers = tiles.filter(t => !t.isJoker)

  const sameNumber = nonJokers.filter(t => t.number === first.number)
  const uniqueColors = [...new Map(sameNumber.map(t => [t.color, t])).values()]

  if (uniqueColors.length >= 3) {
    const combos = combinations(uniqueColors, 3)
    for (const combo of combos) {
      const remaining = removeTiles(tiles, combo)
      if (canFinish(remaining)) return true
    }
  }

  if (uniqueColors.length === 4) {
    const remaining = removeTiles(tiles, uniqueColors)
    if (canFinish(remaining)) return true
  }

  if (uniqueColors.length === 2 && jokers.length >= 1) {
    const combo = [...uniqueColors, jokers[0]]
    const remaining = removeTiles(tiles, combo)
    if (canFinish(remaining)) return true
  }

  const sameColor = nonJokers
    .filter(t => t.color === first.color)
    .sort((a, b) => a.number - b.number)

  let run: Tile[] = [first]
  let neededJokers = 0

  for (let i = 1; i < sameColor.length; i++) {
    const diff = sameColor[i].number - run[run.length - 1].number

    if (diff === 1) {
      run.push(sameColor[i])
    } else if (diff > 1 && diff - 1 <= jokers.length - neededJokers) {
      neededJokers += diff - 1
      run.push(sameColor[i])
    } else {
      break
    }

    if (run.length + neededJokers >= 3) {
      const usedJokers = jokers.slice(0, neededJokers)
      const combo = [...run, ...usedJokers]
      const remaining = removeTiles(tiles, combo)
      if (canFinish(remaining)) return true
    }
  }

  return false
}

function tileSort(a: Tile, b: Tile) {
  if (a.color === b.color) return a.number - b.number
  return a.color.localeCompare(b.color)
}

function removeTiles(all: Tile[], used: Tile[]): Tile[] {
  const copy = [...all]

  for (const u of used) {
    const index = copy.findIndex(t =>
      t.number === u.number &&
      t.color === u.color &&
      !!t.isJoker === !!u.isJoker
    )
    if (index >= 0) copy.splice(index, 1)
  }

  return copy
}

function combinations(arr: Tile[], size: number): Tile[][] {
  const result: Tile[][] = []

  function helper(start: number, combo: Tile[]) {
    if (combo.length === size) {
      result.push([...combo])
      return
    }
    for (let i = start; i < arr.length; i++) {
      combo.push(arr[i])
      helper(i + 1, combo)
      combo.pop()
    }
  }

  helper(0, [])
  return result
}

## Ek SQL: Timeout ve Masa Sohbeti (2026-03-05)

Asagidaki SQL'i SQL Editor'da calistir:

```sql
-- 1) game_timeout_move fix: zorunlu draw sonrasi hand DB'ye yazilsin
create or replace function public.game_timeout_move(
  p_table_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_player record;
  v_table record;
  v_hand jsonb;
  v_pick jsonb;
  v_deck jsonb;
  v_deck_count int;
begin
  select id, status, current_turn, max_players, deck, turn_seconds, turn_started_at
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then raise exception 'TABLE_NOT_FOUND'; end if;
  if v_table.status <> 'playing' then raise exception 'TABLE_NOT_PLAYING'; end if;

  select id, seat_index, hand
    into v_player
  from public.table_players
  where table_id = p_table_id and user_id = p_user_id
  for update;

  if not found then raise exception 'PLAYER_NOT_IN_TABLE'; end if;
  if v_player.seat_index <> v_table.current_turn then raise exception 'NOT_YOUR_TURN'; end if;

  if now() < coalesce(v_table.turn_started_at, now())
      + make_interval(secs => coalesce(v_table.turn_seconds,15)) then
    raise exception 'TURN_NOT_EXPIRED';
  end if;

  v_hand := coalesce(v_player.hand, '[]'::jsonb);

  if jsonb_array_length(v_hand) = 14 then
    v_deck := coalesce(v_table.deck, '[]'::jsonb);
    v_deck_count := jsonb_array_length(v_deck);
    if v_deck_count <= 1 then raise exception 'DECK_EMPTY'; end if; -- deck[0]=gosterge

    v_pick := v_deck -> (v_deck_count - 1);
    v_deck := v_deck #- array[(v_deck_count - 1)::text];
    v_hand := v_hand || jsonb_build_array(v_pick);

    update public.tables set deck = v_deck where id = p_table_id;
    update public.table_players set hand = v_hand where id = v_player.id; -- kritik satir
  end if;

  select value into v_pick
  from jsonb_array_elements(v_hand)
  where not public._tile_is_joker(value)
  order by 1 desc
  limit 1;

  if v_pick is null then v_pick := v_hand->0; end if;

  return public.game_discard(p_table_id, p_user_id, v_pick, false);
end;
$$;

grant execute on function public.game_timeout_move(uuid, uuid) to authenticated, service_role;

-- 2) Masa sohbeti tablosu (ekran icin gerekli)
create table if not exists public.table_chat_messages (
  id uuid primary key default gen_random_uuid(),
  table_id uuid not null references public.tables(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(trim(message)) > 0 and char_length(message) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_table_chat_messages_table_created
  on public.table_chat_messages (table_id, created_at);

alter table public.table_chat_messages disable row level security;
```

## Masa Sohbeti (Oyuncular + Arkadaslari) SQL

Uygulamadaki sohbet paneli `table_chat_messages` tablosunu kullanir. Asagidaki paket:
- Mesaj tablosu
- Katilimci tablosu
- Oyuncular + oyuncularin arkadaslarini katilimciya ekleyen helper RPC

```sql
create extension if not exists pgcrypto;

create table if not exists public.table_chat_messages (
  id uuid primary key default gen_random_uuid(),
  table_id uuid not null references public.tables(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(trim(message)) > 0 and char_length(message) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_table_chat_messages_table_created
  on public.table_chat_messages(table_id, created_at);

create table if not exists public.table_chat_participants (
  table_id uuid not null references public.tables(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  added_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (table_id, user_id)
);

create index if not exists idx_table_chat_participants_user
  on public.table_chat_participants(user_id);

create or replace function public.refresh_table_chat_participants(p_table_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_count int := 0;
begin
  insert into public.table_chat_participants(table_id, user_id, added_by)
  select p_table_id, tp.user_id, tp.user_id
  from public.table_players tp
  where tp.table_id = p_table_id
  on conflict do nothing;

  -- friends tablosunda accepted iliskileri ekler (opsiyonel)
  begin
    insert into public.table_chat_participants(table_id, user_id, added_by)
    select distinct
      p_table_id,
      case when f.user_id = tp.user_id then f.friend_id else f.user_id end as friend_user_id,
      tp.user_id
    from public.table_players tp
    join public.friends f
      on (f.user_id = tp.user_id or f.friend_id = tp.user_id)
    where tp.table_id = p_table_id
      and coalesce(f.status, 'pending') = 'accepted'
    on conflict do nothing;
  exception when others then
    null;
  end;

  select count(*) into v_count
  from public.table_chat_participants
  where table_id = p_table_id;

  return jsonb_build_object('ok', true, 'table_id', p_table_id, 'participants', v_count);
end;
$$;

grant execute on function public.refresh_table_chat_participants(uuid)
  to authenticated, service_role;

-- Gelistirme asamasinda RLS kapali:
alter table public.table_chat_messages disable row level security;
alter table public.table_chat_participants disable row level security;
```

Kullanim:
1. Masa olusunca / oyuncu girince `select public.refresh_table_chat_participants('<table_id>');`
2. Sohbete sadece katilimciya dusenler dahil edilir.
