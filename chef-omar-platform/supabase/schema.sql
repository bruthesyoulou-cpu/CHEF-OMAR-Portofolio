-- ============================================================================
-- CHEF OMAR — base Supabase v2 (rôles chef / admin, calendrier, livre d'or, messages, paiements, journaux)
-- Collez tout dans SQL Editor > Run. Comptes à créer ensuite dans Authentication > Users :
--   admin : bruthesyoulou@gmail.com      chef : Omarngalladiop604@gmail.com
-- ============================================================================

-- 0) RÔLES -------------------------------------------------------------------
create table if not exists public.staff (email text primary key, role text not null check (role in ('admin','chef')));
insert into public.staff values ('bruthesyoulou@gmail.com','admin'),('omarngalladiop604@gmail.com','chef')
  on conflict (email) do update set role = excluded.role;
alter table public.staff enable row level security;   -- aucune policy : lecture uniquement via staff_role()
create or replace function public.staff_role() returns text language sql stable security definer set search_path = public as $$
  select role from public.staff where lower(email) = lower(coalesce(auth.jwt() ->> 'email','')) limit 1 $$;

-- 1) CONTENU DU SITE : lignes 'chef' (profil, plats, formules, masterclasses), 'admin' (marque, paiement, options, textes légaux), 'meta' (versions)
create table if not exists public.site_content (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
insert into public.site_content (id,data) values
 ('chef','{"socials":{"email":"Omarngalladiop604@gmail.com"}}'),('admin','{}'),('meta','{"v":1,"sections":{}}') on conflict (id) do nothing;
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists site_content_touch on public.site_content;
create trigger site_content_touch before update on public.site_content for each row execute function public.touch_updated_at();

-- 2) TABLES MÉTIER -----------------------------------------------------------
create table if not exists public.events (id uuid primary key default gen_random_uuid(), titre text not null, date date not null, lieu text, note text, capacite int, actif boolean not null default true, created_at timestamptz not null default now());
create table if not exists public.registrations (id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events on delete cascade, nom text not null, tel text not null, email text, telegram text, ticket text unique not null, statut text not null default 'confirme' check (statut in ('confirme','annule')), device text not null, created_at timestamptz not null default now());
create table if not exists public.reels (id uuid primary key default gen_random_uuid(), titre text not null, type text not null check (type in ('image','video','texte')), url text, texte text, story boolean not null default false, views int not null default 0, auteur text, created_at timestamptz not null default now());
create table if not exists public.announcements (id uuid primary key default gen_random_uuid(), titre text not null, texte text, media_url text, media_type text, actif boolean not null default true, created_at timestamptz not null default now());
create table if not exists public.reviews (id uuid primary key default gen_random_uuid(), nom text not null default 'Anonyme', anonyme boolean not null default false, note int not null check (note between 1 and 5), texte text not null, likes int not null default 0, visible boolean not null default true, created_at timestamptz not null default now());
create table if not exists public.review_comments (id uuid primary key default gen_random_uuid(), review_id uuid not null references public.reviews on delete cascade, nom text not null default 'Anonyme', texte text not null, created_at timestamptz not null default now());
create table if not exists public.review_likes (review_id uuid references public.reviews on delete cascade, device text, primary key (review_id, device));
create table if not exists public.messages (id uuid primary key default gen_random_uuid(), device text not null, direction text not null check (direction in ('staff','user')), corps text not null, auteur text, created_at timestamptz not null default now());
create table if not exists public.inscriptions (id uuid primary key default gen_random_uuid(), ref text, contact text, formation text, fid text, methode text, montant text, montant_num numeric not null default 0, recu_path text, device text, statut text not null default 'en_attente' check (statut in ('en_attente','valide','annule')), motif text, valide_par text, valide_at timestamptz, created_at timestamptz not null default now());
create table if not exists public.visits (id uuid primary key default gen_random_uuid(), device text, page text, ref text, ua text, lang text, tz text, lat numeric, lon numeric, created_at timestamptz not null default now());
create table if not exists public.audit_logs (id uuid primary key default gen_random_uuid(), actor text not null, role text, action text not null, details text, created_at timestamptz not null default now());

-- 3) SÉCURITÉ (RLS) ----------------------------------------------------------
do $$ declare t text; begin
 foreach t in array array['site_content','events','registrations','reels','announcements','reviews','review_comments','review_likes','messages','inscriptions','visits','audit_logs'] loop
  execute format('alter table public.%I enable row level security', t); end loop; end $$;

drop policy if exists sc_read on public.site_content;  create policy sc_read on public.site_content for select using (true);
drop policy if exists sc_write on public.site_content; create policy sc_write on public.site_content for all to authenticated
 using ((public.staff_role()='admin' and id in ('admin','meta')) or (public.staff_role()='chef' and id in ('chef','meta')))
 with check ((public.staff_role()='admin' and id in ('admin','meta')) or (public.staff_role()='chef' and id in ('chef','meta')));

drop policy if exists ev_read on public.events;  create policy ev_read on public.events for select using (actif or public.staff_role() is not null);
drop policy if exists ev_write on public.events; create policy ev_write on public.events for all to authenticated using (public.staff_role()='chef') with check (public.staff_role()='chef');

drop policy if exists reg_read on public.registrations; create policy reg_read on public.registrations for select to authenticated using (public.staff_role() is not null);
drop policy if exists reg_upd on public.registrations;  create policy reg_upd on public.registrations for update to authenticated using (public.staff_role()='chef') with check (public.staff_role()='chef');

drop policy if exists rl_read on public.reels;  create policy rl_read on public.reels for select using (true);
drop policy if exists rl_write on public.reels; create policy rl_write on public.reels for all to authenticated using (public.staff_role() is not null) with check (public.staff_role() is not null);

drop policy if exists an_read on public.announcements;  create policy an_read on public.announcements for select using (actif or public.staff_role() is not null);
drop policy if exists an_write on public.announcements; create policy an_write on public.announcements for all to authenticated using (public.staff_role()='admin') with check (public.staff_role()='admin');

drop policy if exists rv_read on public.reviews;   create policy rv_read on public.reviews for select using (visible or public.staff_role() is not null);
drop policy if exists rv_ins on public.reviews;    create policy rv_ins on public.reviews for insert to anon, authenticated
 with check (likes=0 and visible and char_length(texte) between 3 and 1000 and char_length(nom)<=60);
drop policy if exists rv_mod on public.reviews;    create policy rv_mod on public.reviews for update to authenticated using (public.staff_role() is not null) with check (public.staff_role() is not null);
drop policy if exists rv_del on public.reviews;    create policy rv_del on public.reviews for delete to authenticated using (public.staff_role() is not null);
drop policy if exists rc_read on public.review_comments; create policy rc_read on public.review_comments for select using (true);
drop policy if exists rc_ins on public.review_comments;  create policy rc_ins on public.review_comments for insert to anon, authenticated with check (char_length(texte) between 2 and 600 and char_length(nom)<=60);
drop policy if exists rc_del on public.review_comments;  create policy rc_del on public.review_comments for delete to authenticated using (public.staff_role() is not null);

drop policy if exists msg_read on public.messages; create policy msg_read on public.messages for select to authenticated using (public.staff_role() is not null);
drop policy if exists msg_ins on public.messages;  create policy msg_ins on public.messages for insert to authenticated with check (public.staff_role()='chef' and direction='staff');

drop policy if exists ins_read on public.inscriptions; create policy ins_read on public.inscriptions for select to authenticated using (public.staff_role() is not null);
drop policy if exists ins_upd on public.inscriptions;  create policy ins_upd on public.inscriptions for update to authenticated using (public.staff_role()='chef') with check (public.staff_role()='chef');

drop policy if exists v_ins on public.visits;  create policy v_ins on public.visits for insert to anon, authenticated with check (char_length(coalesce(page,''))<=120);
drop policy if exists v_read on public.visits; create policy v_read on public.visits for select to authenticated using (public.staff_role() is not null);

drop policy if exists a_ins on public.audit_logs;  create policy a_ins on public.audit_logs for insert to authenticated with check (public.staff_role() is not null and lower(actor)=lower(auth.jwt() ->> 'email'));
drop policy if exists a_read on public.audit_logs; create policy a_read on public.audit_logs for select to authenticated using (public.staff_role()='admin');
-- review_likes et staff : aucune policy (RPC uniquement)

-- 4) FONCTIONS PUBLIQUES (le visiteur n'accède jamais directement aux données privées) ----
create or replace function public.like_review(p_id uuid, p_device text) returns int language plpgsql security definer set search_path = public as $$
declare n int; begin
  if length(coalesce(p_device,'')) < 8 then raise exception 'device'; end if;
  insert into review_likes(review_id, device) values (p_id, p_device) on conflict do nothing;
  if found then update reviews set likes = likes + 1 where id = p_id; end if;
  select likes into n from reviews where id = p_id; return coalesce(n,0); end $$;

create or replace function public.register_event(p_event uuid, p_nom text, p_tel text, p_email text, p_tg text, p_device text) returns json language plpgsql security definer set search_path = public as $$
declare e events%rowtype; r registrations%rowtype; c int; begin
  select * into e from events where id = p_event and actif; if not found then raise exception 'evenement'; end if;
  if length(trim(coalesce(p_nom,''))) < 2 or length(trim(coalesce(p_tel,''))) < 6 or length(coalesce(p_device,'')) < 8 then raise exception 'donnees'; end if;
  select * into r from registrations where event_id = p_event and device = p_device and statut = 'confirme' limit 1;
  if not found then
    select count(*) into c from registrations where event_id = p_event and statut = 'confirme';
    if coalesce(e.capacite,0) > 0 and c >= e.capacite then raise exception 'complet'; end if;
    insert into registrations(event_id,nom,tel,email,telegram,ticket,device)
      values (p_event, left(trim(p_nom),80), left(trim(p_tel),30), nullif(left(trim(coalesce(p_email,'')),120),''), nullif(left(trim(coalesce(p_tg,'')),60),''), 'CO-'||upper(substr(md5(random()::text||clock_timestamp()::text||p_device),1,8)), p_device) returning * into r;
  end if;
  return json_build_object('event_id',e.id,'event',e.titre,'date',e.date,'lieu',e.lieu,'nom',r.nom,'ticket',r.ticket,'statut',r.statut); end $$;

create or replace function public.my_data(p_device text) returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
   'tickets', coalesce((select json_agg(json_build_object('event_id',e.id,'event',e.titre,'date',e.date,'lieu',e.lieu,'nom',r.nom,'ticket',r.ticket,'statut',r.statut) order by r.created_at desc) from registrations r join events e on e.id = r.event_id where r.device = p_device),'[]'::json),
   'messages', coalesce((select json_agg(json_build_object('direction',m.direction,'corps',m.corps,'at',m.created_at) order by m.created_at) from messages m where m.device = p_device),'[]'::json)) $$;

create or replace function public.user_reply(p_device text, p_body text) returns void language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_device,'')) < 8 or length(trim(coalesce(p_body,''))) < 1 or length(p_body) > 1000 then raise exception 'donnees'; end if;
  if not exists (select 1 from registrations where device = p_device union all select 1 from inscriptions where device = p_device union all select 1 from messages where device = p_device) then raise exception 'inconnu'; end if;
  insert into messages(device, direction, corps) values (p_device, 'user', trim(p_body)); end $$;

create or replace function public.bump_view(p_reel uuid) returns void language sql security definer set search_path = public as $$ update reels set views = views + 1 where id = p_reel $$;

grant execute on function public.like_review(uuid,text), public.register_event(uuid,text,text,text,text,text), public.my_data(text), public.user_reply(text,text), public.bump_view(uuid) to anon, authenticated;
grant execute on function public.staff_role() to authenticated;

-- 5) STOCKAGE (cloud) : media = public (photos, vidéos 30 s) · recus = privé (captures de paiement) · lecons = privé (formations)
insert into storage.buckets (id,name,public,file_size_limit) values ('media','media',true,52428800),('recus','recus',false,10485760),('lecons','lecons',false,52428800) on conflict (id) do nothing;
drop policy if exists st_media on storage.objects;  create policy st_media on storage.objects for all to authenticated using (bucket_id='media' and public.staff_role() is not null) with check (bucket_id='media' and public.staff_role() is not null);
drop policy if exists st_recus on storage.objects;  create policy st_recus on storage.objects for select to authenticated using (bucket_id='recus' and public.staff_role() is not null);
drop policy if exists st_lecons_r on storage.objects; create policy st_lecons_r on storage.objects for select to authenticated using (bucket_id='lecons' and public.staff_role() is not null);
drop policy if exists st_lecons_w on storage.objects; create policy st_lecons_w on storage.objects for all to authenticated using (bucket_id='lecons' and public.staff_role()='chef') with check (bucket_id='lecons' and public.staff_role()='chef');
