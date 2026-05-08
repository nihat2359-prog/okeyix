-- Masa ayarlari: seyirci ve sohbet kontrolu
-- Güvenli calisma: mevcut satirlari bozmamak icin default true + not null

alter table public.tables
  add column if not exists spectators_enabled boolean default true;

alter table public.tables
  add column if not exists chat_enabled boolean default true;

update public.tables
set
  spectators_enabled = coalesce(spectators_enabled, true),
  chat_enabled = coalesce(chat_enabled, true)
where spectators_enabled is null
   or chat_enabled is null;

alter table public.tables
  alter column spectators_enabled set default true,
  alter column spectators_enabled set not null,
  alter column chat_enabled set default true,
  alter column chat_enabled set not null;

comment on column public.tables.spectators_enabled is 'Masa seyirciye acik mi';
comment on column public.tables.chat_enabled is 'Masa icinde sohbet acik mi';
