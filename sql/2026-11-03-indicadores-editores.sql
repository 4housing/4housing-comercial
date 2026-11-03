-- ============================================================================
-- Indicadores — quién puede cargar datos, SIN tocar los permisos del CRM
--
-- CORRER en el SQL Editor del proyecto del CRM (wcpkpwxhqdcdljfwzcmy),
-- DESPUÉS de 2026-11-02-indicadores-tablas.sql.
--
-- POR QUÉ EXISTE ESTE ARCHIVO
-- --------------------------
-- La primera versión de `ind_puede_editar()` leía `perfiles_sector.permisos`.
-- Funcionaba, pero tenía un costo inaceptable: para dar de alta a alguien
-- había que ESCRIBIR en `perfiles_sector`, que es una tabla del CRM con los
-- permisos ya configurados de todo el equipo. Se decidió no tocar nada de eso.
--
-- Ahora Indicadores maneja su propia lista, en su propia tabla `ind_editores`.
-- Resultado: dar o quitar permiso de carga es un insert/delete en una tabla
-- nueva. Los permisos del CRM quedan exactamente como están, y el resto de la
-- app sigue funcionando igual que hoy.
--
-- La visión (ver el ítem en el menú) ya no depende de la base: se resolvió en
-- index.html exceptuando 'indicadores' del array `ver`, porque es una sección
-- que se agregó después de que se configuraran los permisos y no figura en el
-- `ver` de nadie. Leer no es un riesgo: el RLS de las tablas ind_ ya deja leer
-- a todo el sector comercial.
--
-- Es ADITIVO: crea una tabla nueva y reemplaza una función propia
-- (`ind_puede_editar`, creada por la migración anterior). No toca ninguna
-- tabla, función ni política del CRM.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. LA LISTA
-- ----------------------------------------------------------------------------
-- Se identifica por mail y no por uuid a propósito: es lo que se lee del JWT
-- de Azure, y así dar de alta a alguien no obliga a buscarle el id primero.
create table if not exists public.ind_editores (
  email       text primary key,
  nota        text,
  created_at  timestamptz default now()
);

comment on table public.ind_editores is
  'Quién puede cargar datos en Indicadores (el tab "Datos", que borra las '
  'tablas enteras y reinserta). Se administra SOLO desde el SQL Editor: la '
  'API no tiene permisos de escritura sobre esta tabla a propósito.';


-- ----------------------------------------------------------------------------
-- 2. QUIÉN ENTRA
-- ----------------------------------------------------------------------------
-- Agregar o quitar gente es un insert/delete acá, nada más.
insert into public.ind_editores (email, nota) values
  ('ignaciosanchez@4housing.com.ar', 'Carga el Excel de rental, stock, DTM y facturación')
on conflict (email) do nothing;

-- Para sumar a alguien más, por ejemplo:
-- insert into public.ind_editores (email, nota)
-- values ('pablospinetto@4housing.com.ar', 'Dirección')
-- on conflict (email) do nothing;
--
-- Para dar de baja:
-- delete from public.ind_editores where email = 'alguien@4housing.com.ar';


-- ----------------------------------------------------------------------------
-- 3. LA FUNCIÓN QUE USA EL RLS
-- ----------------------------------------------------------------------------
-- Reemplaza la versión anterior, que leía perfiles/perfiles_sector. Las
-- políticas creadas en la migración del 2/11 la llaman por nombre, así que
-- toman el cuerpo nuevo solas: no hay que recrear ninguna política.
--
-- `security definer` para que pueda leer ind_editores aunque el usuario no
-- tenga permiso de lectura sobre esa tabla (ver punto 4).
--
-- Ya NO consulta es_direccion: si se quiere que Dirección cargue datos, se
-- agrega el mail arriba. Explícito antes que implícito.
create or replace function public.ind_puede_editar()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ind_editores e
    where lower(e.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.ind_puede_editar() from public, anon;
grant execute on function public.ind_puede_editar() to authenticated;


-- ----------------------------------------------------------------------------
-- 4. LA LISTA NO SE TOCA DESDE LA APP
-- ----------------------------------------------------------------------------
-- RLS activo y CERO políticas: con RLS prendido y sin políticas, nadie lee ni
-- escribe por la API. La función del punto 3 igual puede leerla porque es
-- `security definer`.
--
-- Esto cierra un agujero obvio: si la app pudiera escribir esta tabla,
-- cualquiera se daría permiso a sí mismo para borrar el histórico.
alter table public.ind_editores enable row level security;

revoke all on public.ind_editores from anon, authenticated;


-- ----------------------------------------------------------------------------
-- 5. VERIFICACIÓN
-- ----------------------------------------------------------------------------
-- 5.a — quién está habilitado (debería devolver solo a Ignacio)
-- select email, nota, created_at from public.ind_editores order by email;
--
-- 5.b — la tabla no debe tener ninguna política y sí RLS activo
-- select c.relrowsecurity as rls_activo,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename='ind_editores') as politicas
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relname='ind_editores';
--
-- 5.c — la función ya no debe mencionar perfiles_sector
-- select prosrc like '%perfiles%' as todavia_lee_perfiles
--   from pg_proc where proname = 'ind_puede_editar';


-- ----------------------------------------------------------------------------
-- 6. ROLLBACK
-- ----------------------------------------------------------------------------
-- Vuelve a la versión anterior de la función y borra la tabla. Las políticas
-- de las tablas ind_ no hace falta tocarlas.
--
-- drop table if exists public.ind_editores;
-- create or replace function public.ind_puede_editar()
-- returns boolean language sql stable security definer set search_path = public
-- as $$ select false $$;
