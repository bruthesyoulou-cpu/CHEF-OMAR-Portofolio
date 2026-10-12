-- ATTENTION : supprime DEFINITIVEMENT toutes les tables et fonctions du schéma public.
-- Ne touche ni aux comptes (Authentication) ni aux fichiers déjà envoyés (Storage).
-- À exécuter AVANT schema.sql si votre base contient d'anciennes tables.
do $$
declare r record;
begin
  for r in (select tablename from pg_tables where schemaname = 'public') loop
    execute format('drop table if exists public.%I cascade', r.tablename);
  end loop;
  for r in (select p.oid::regprocedure as f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f'
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')) loop
    execute 'drop function if exists ' || r.f || ' cascade';
  end loop;
end $$;
