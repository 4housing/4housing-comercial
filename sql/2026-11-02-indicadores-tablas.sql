-- ============================================================================
-- Integración de la app de Indicadores al CRM — PASO 1: estructura
--
-- Crea las 11 tablas de la app de indicadores dentro del Supabase del CRM
-- (wcpkpwxhqdcdljfwzcmy), con el prefijo `ind_` decidido con Ignacio.
--
-- CORRER MANUALMENTE en el SQL Editor de Supabase, ANTES de desplegar
-- cualquier index.html que las use (regla 2: primero el SQL, después el HTML).
--
-- Es 100% ADITIVO: solo crea objetos nuevos con prefijo `ind_`. No toca,
-- renombra ni borra ninguna tabla, política ni función existente del CRM.
-- Si algo sale mal, el rollback es el bloque comentado del final.
--
-- El proyecto viejo (zziktktjsnkmtaqwghha) NO se toca y sigue funcionando.
-- Los datos se migran en un paso 2 aparte, una vez verificada la estructura.
--
-- Origen de los tipos: se bajó el esquema real de producción
-- (information_schema.columns + pg_indexes del proyecto viejo, 2/11/2026).
-- NO están deducidos del código, salvo ind_stock_snapshots — ver nota abajo.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. TABLAS
-- ----------------------------------------------------------------------------
-- Nota sobre foreign keys: NO se define ninguna FK, igual que en producción.
-- En particular NO va ind_stock_movimientos.serie -> ind_stock_items.serie:
-- la importación de stock (`subirStock`) borra ind_stock_items entero pero
-- conserva los movimientos cargados a mano. Con FK ese borrado falla; con
-- ON DELETE CASCADE se lleva puesto todo el historial de movimientos.

-- 1.1 Datos de rental (la base contable del dashboard)
create table if not exists public.ind_rental_data (
  id               bigint generated always as identity primary key,
  serie            text,
  cliente          text,
  tipologia        text,
  modelo_negocio   text,
  anio             integer,
  mes              text,
  mes_anio         text,
  moneda           text,
  importe_mensual  numeric,
  estado_serie     text,
  tipo_cambio      numeric,
  importe_pesos    numeric,
  created_at       timestamptz default now()
);

-- 1.2 Fotos de los meses cerrados desde el stock.
-- Viven en tabla propia a propósito: subir el Excel reemplaza ind_rental_data
-- entero y se las llevaría puestas. Si un mes está en las dos, manda
-- ind_rental_data, que es la verdad contable.
--
-- ATENCIÓN: esta es la ÚNICA tabla cuya estructura NO se pudo bajar de
-- producción, porque NO EXISTE en el proyecto zziktktjsnkmtaqwghha (ver el
-- informe que acompaña esta migración). Las columnas se derivaron de
-- `filasDeMes()` en el código, que arma filas con exactamente la misma forma
-- que ind_rental_data — por eso se fusionan en una sola lista en el dashboard.
create table if not exists public.ind_stock_snapshots (
  id               bigint generated always as identity primary key,
  serie            text,
  cliente          text,
  tipologia        text,
  modelo_negocio   text,
  anio             integer,
  mes              text,
  mes_anio         text,
  moneda           text,
  importe_mensual  numeric,
  estado_serie     text,
  tipo_cambio      numeric,
  importe_pesos    numeric,
  created_at       timestamptz default now()
);

-- 1.3 IPC (índice de precios, para los ajustes)
create table if not exists public.ind_ipc_data (
  id             bigint generated always as identity primary key,
  anio           integer,
  mes            text,
  mes_anio       text,
  ipc_mensual    numeric,
  ipc_acumulado  numeric,
  created_at     timestamptz default now()
);

-- 1.4 DTM (costos y facturación de servicios)
create table if not exists public.ind_dtm_data (
  id               bigint generated always as identity primary key,
  anio             integer,
  mes              text,
  mes_anio         text,
  serie            text,
  modelo_negocio   text,
  tipo_servicio    text,
  descripcion      text,
  costo            numeric,
  facturacion_dtm  numeric,
  created_at       timestamptz default now()
);

-- 1.5 Facturación consolidada por mes y modelo de negocio
create table if not exists public.ind_facturacion_data (
  id              bigint generated always as identity primary key,
  mes_anio        text not null,
  modelo_negocio  text,
  importe_pesos   numeric,
  created_at      timestamptz default now()
);

-- 1.6 Resumen mensual de clientes (altas/bajas/activos)
-- OJO: no confundir con la tabla `clientes` del CRM, que son los clientes
-- comerciales. Esta es el resumen mensual de rental. Por eso el prefijo.
create table if not exists public.ind_clientes_data (
  id          bigint generated always as identity primary key,
  tipo        text not null,
  mes         text not null,
  activos     integer,
  nuevos      integer,
  altas       integer,
  bajas       integer,
  serie       text,
  tipologia   text,
  cliente     text,
  created_at  timestamptz default now()
);

-- 1.7 Stock de contenedores (el maestro actual)
create table if not exists public.ind_stock_items (
  id                bigint generated always as identity primary key,
  serie             text not null,
  if_codigo         text,
  tipo              text,
  medida            text,
  modulo            text,
  tipologia         text,
  modelo_negocio    text,
  estado            text not null default 'STOCK',
  sucursal          text,
  ubicacion         text,
  cliente           text,
  cliente_codigo    text,
  contacto          text,
  fecha_entrega     date,
  fecha_devolucion  date,
  vto_oc            date,
  propiedad         text,
  detalle           text,
  moneda            text,
  tarifa_lista      numeric default 0,
  importe_mensual   numeric default 0,
  actualizado_en    timestamptz default now(),
  actualizado_por   text,
  constraint ind_stock_items_serie_key unique (serie)
);

-- 1.8 Historial de movimientos de cada contenedor
create table if not exists public.ind_stock_movimientos (
  id             bigint generated always as identity primary key,
  serie          text not null,
  fecha          timestamptz default now(),
  tipo           text not null,
  estado_ant     text,
  estado_nuevo   text,
  cliente_ant    text,
  cliente_nuevo  text,
  importe_ant    numeric,
  importe_nuevo  numeric,
  nota           text,
  usuario        text,
  orden          integer
);

-- 1.9 Cierres de mes auditados
create table if not exists public.ind_stock_cierres (
  id          bigint generated always as identity primary key,
  mes_anio    text not null,
  cerrado_en  timestamptz default now(),
  cerrado_por text,
  alquilados  integer,
  activos     integer,
  valorizado  numeric,
  nota        text,
  constraint ind_stock_cierres_mes_anio_key unique (mes_anio)
);

-- 1.10 Chat interno
create table if not exists public.ind_chat_messages (
  id          bigint generated always as identity primary key,
  user_email  text not null,
  user_name   text,
  message     text not null,
  created_at  timestamptz default now()
);

-- 1.11 Notificaciones
-- PENDIENTE DE DEFINICIÓN: hoy son GLOBALES, no por usuario. `read` es una
-- sola bandera compartida y el botón de limpiar borra todas las filas. En el
-- CRM, donde entran 8+ personas, uno limpia y se las borra a todos. Se deja
-- igual que en producción para no cambiar comportamiento en la mudanza; si se
-- quiere por usuario hace falta una tabla puente y se hace en otra migración.
create table if not exists public.ind_notifications (
  id          bigint generated always as identity primary key,
  title       text not null,
  body        text not null,
  read        boolean default false,
  created_at  timestamptz default now()
);


-- ----------------------------------------------------------------------------
-- 2. ÍNDICES (mismos que producción, renombrados con el prefijo)
-- ----------------------------------------------------------------------------
create index if not exists idx_ind_rental_modelo   on public.ind_rental_data(modelo_negocio);
create index if not exists idx_ind_rental_mes      on public.ind_rental_data(mes_anio);
create index if not exists idx_ind_rental_estado   on public.ind_rental_data(estado_serie);
create index if not exists idx_ind_snap_mes        on public.ind_stock_snapshots(mes_anio);
create index if not exists idx_ind_dtm_mes_anio    on public.ind_dtm_data(mes_anio);
create index if not exists idx_ind_fact_mes        on public.ind_facturacion_data(mes_anio);
create index if not exists idx_ind_clientes_tipo   on public.ind_clientes_data(tipo);
create index if not exists idx_ind_stock_estado    on public.ind_stock_items(estado);
create index if not exists idx_ind_mov_serie       on public.ind_stock_movimientos(serie);

-- Estos dos NO están en producción. Se agregan porque el código los necesita:
-- loadChat() ordena por created_at, y las notificaciones se ordenan por fecha.
create index if not exists idx_ind_chat_fecha      on public.ind_chat_messages(created_at);
create index if not exists idx_ind_notif_fecha     on public.ind_notifications(created_at desc);


-- ----------------------------------------------------------------------------
-- 3. QUIÉN PUEDE ESCRIBIR
-- ----------------------------------------------------------------------------
-- El tab "Datos" de la app hace `delete()` de la tabla entera y reinserta.
-- Eso NO puede quedar al alcance de cualquier usuario autenticado: con una
-- política `to authenticated using (true)` cualquiera del equipo comercial
-- borraría todo el histórico de rental con un click.
--
-- Esta función se apoya en la infraestructura de permisos que el CRM YA tiene
-- (`perfiles` + `perfiles_sector.permisos`, ver cargarPerfilComercial() en
-- index.html). Da true si el usuario es de Dirección, o si tiene 'indicadores'
-- dentro de permisos->'editar' en el sector fhcomercial.
--
-- DIFERENCIA DELIBERADA CON LA UI: el JS del CRM trata "sin permisos
-- configurados" como acceso total (retrocompatible). Acá es al revés: sin
-- permiso explícito NO se escribe. Es intencional — es la diferencia entre
-- ocultar un botón y proteger los datos. Ver el punto 5 para habilitarte.
create or replace function public.ind_puede_editar()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from public.perfiles p
      where p.id = auth.uid()
        and coalesce(p.activo, true)
        and p.es_direccion
    )
    or exists (
      select 1 from public.perfiles_sector ps
      where ps.perfil_id = auth.uid()
        and ps.sector = 'fhcomercial'
        and (ps.permisos::jsonb -> 'editar') ? 'indicadores'
    );
$$;

revoke all on function public.ind_puede_editar() from public, anon;
grant execute on function public.ind_puede_editar() to authenticated;


-- ----------------------------------------------------------------------------
-- 4. RLS — solo `authenticated`, nunca `anon` (regla 7)
-- ----------------------------------------------------------------------------
-- Lectura: todo el sector comercial, con la misma función que ya usa el resto
--          del CRM.
-- Escritura: solo quien pase ind_puede_editar().
--
-- Excepción: el chat. Cualquiera del sector puede escribir su propio mensaje
-- (sería absurdo pedir permiso de edición para chatear), pero nadie puede
-- editar ni borrar mensajes, ni los propios: el chat es un registro.

do $$
declare
  t text;
begin
  foreach t in array array[
    'ind_rental_data','ind_stock_snapshots','ind_ipc_data','ind_dtm_data',
    'ind_facturacion_data','ind_clientes_data','ind_stock_items',
    'ind_stock_movimientos','ind_stock_cierres','ind_chat_messages',
    'ind_notifications'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format($f$
      drop policy if exists "%1$s_leer" on public.%1$I;
      create policy "%1$s_leer" on public.%1$I
        for select to authenticated
        using (public.tiene_sector('fhcomercial'));
    $f$, t);
  end loop;
end $$;

-- Escritura restringida para las 9 tablas de datos
do $$
declare
  t text;
begin
  foreach t in array array[
    'ind_rental_data','ind_stock_snapshots','ind_ipc_data','ind_dtm_data',
    'ind_facturacion_data','ind_clientes_data','ind_stock_items',
    'ind_stock_movimientos','ind_stock_cierres'
  ]
  loop
    execute format($f$
      drop policy if exists "%1$s_escribir" on public.%1$I;
      create policy "%1$s_escribir" on public.%1$I
        for insert to authenticated
        with check (public.tiene_sector('fhcomercial') and public.ind_puede_editar());

      drop policy if exists "%1$s_actualizar" on public.%1$I;
      create policy "%1$s_actualizar" on public.%1$I
        for update to authenticated
        using (public.tiene_sector('fhcomercial') and public.ind_puede_editar())
        with check (public.tiene_sector('fhcomercial') and public.ind_puede_editar());

      drop policy if exists "%1$s_borrar" on public.%1$I;
      create policy "%1$s_borrar" on public.%1$I
        for delete to authenticated
        using (public.tiene_sector('fhcomercial') and public.ind_puede_editar());
    $f$, t);
  end loop;
end $$;

-- Chat: escribe cualquiera del sector, pero solo su propio mensaje.
-- Sin update ni delete: el chat no se edita ni se borra.
drop policy if exists "ind_chat_messages_escribir" on public.ind_chat_messages;
create policy "ind_chat_messages_escribir" on public.ind_chat_messages
  for insert to authenticated
  with check (
    public.tiene_sector('fhcomercial')
    and user_email = auth.jwt() ->> 'email'
  );

-- Notificaciones: las crea el que carga datos; marcarlas como leídas lo puede
-- hacer cualquiera del sector (es una bandera de UI, no un dato sensible).
-- El borrado sí queda restringido, porque borra para todos.
drop policy if exists "ind_notifications_escribir" on public.ind_notifications;
create policy "ind_notifications_escribir" on public.ind_notifications
  for insert to authenticated
  with check (public.tiene_sector('fhcomercial') and public.ind_puede_editar());

drop policy if exists "ind_notifications_actualizar" on public.ind_notifications;
create policy "ind_notifications_actualizar" on public.ind_notifications
  for update to authenticated
  using (public.tiene_sector('fhcomercial'))
  with check (public.tiene_sector('fhcomercial'));

drop policy if exists "ind_notifications_borrar" on public.ind_notifications;
create policy "ind_notifications_borrar" on public.ind_notifications
  for delete to authenticated
  using (public.tiene_sector('fhcomercial') and public.ind_puede_editar());


-- ----------------------------------------------------------------------------
-- 4 bis. GRANTS — explícitos, para no depender de los default privileges
-- ----------------------------------------------------------------------------
-- Supabase normalmente otorga permisos sobre las tablas nuevas de `public`
-- automáticamente, pero eso depende de la configuración del proyecto. Si los
-- grants faltan, el RLS no llega ni a evaluarse: falla antes, con un
-- "permission denied for table" que despista. Se dejan explícitos.
--
-- Y se revocan de `anon` a propósito (regla 7): aunque ninguna política
-- contempla a `anon`, sin grant no hay ni siquiera intento de lectura.

do $$
declare
  t text;
begin
  foreach t in array array[
    'ind_rental_data','ind_stock_snapshots','ind_ipc_data','ind_dtm_data',
    'ind_facturacion_data','ind_clientes_data','ind_stock_items',
    'ind_stock_movimientos','ind_stock_cierres','ind_chat_messages',
    'ind_notifications'
  ]
  loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;


-- ----------------------------------------------------------------------------
-- 5. PERMISOS DE LA SECCIÓN NUEVA — son DOS cosas distintas
-- ----------------------------------------------------------------------------
-- 'indicadores' es una sección más del CRM, así que entra en el mismo esquema
-- de permisos que el resto (`perfiles_sector.permisos`, con sus arrays `ver` y
-- `editar`). Hay que tocar los dos, y son independientes:
--
--   ver    -> si NO está, el botón del menú se OCULTA (index.html, en el
--             forEach que hace `b.style.display = comPuedeVer(sec) ? '' : 'none'`).
--             Va para todo el que deba mirar los indicadores.
--   editar -> si NO está, se ve la vista pero no se puede subir el Excel.
--             Va SOLO para quien cargue datos: ese botón borra tablas enteras.
--
-- OJO con la asimetría: quien NO tiene `permisos` configurados ve y edita todo
-- (el JS es retrocompatible) y no necesita nada de esto. Los updates de abajo
-- solo tocan a quien SÍ tiene el array configurado. Dirección tampoco lo
-- necesita: pasa por `es_direccion`.
--
-- Ver cómo está parado el equipo antes de tocar nada:
--
-- select u.email, p.es_direccion, ps.cargo,
--        ps.permisos -> 'ver'    as ve_hoy,
--        ps.permisos -> 'editar' as edita_hoy
--   from public.perfiles_sector ps
--   join auth.users u on u.id = ps.perfil_id
--   left join public.perfiles p on p.id = ps.perfil_id
--  where ps.sector = 'fhcomercial'
--  order by u.email;

-- 5.a  VER — para todo el equipo comercial con permisos configurados.
--      Para acotarlo a algunas personas, agregar:  and u.email in ('a@...','b@...')
--
-- update public.perfiles_sector ps
--    set permisos = jsonb_set(ps.permisos::jsonb, '{ver}',
--          (ps.permisos::jsonb -> 'ver') || '["indicadores"]'::jsonb, true)
--   from auth.users u
--  where u.id = ps.perfil_id
--    and ps.sector = 'fhcomercial'
--    and jsonb_typeof(ps.permisos::jsonb -> 'ver') = 'array'
--    and not (ps.permisos::jsonb -> 'ver') ? 'indicadores';

-- 5.b  EDITAR — SOLO para quien cargue los datos. Una vez por persona.
--
-- update public.perfiles_sector ps
--    set permisos = jsonb_set(
--          coalesce(ps.permisos::jsonb, '{}'::jsonb),
--          '{editar}',
--          coalesce(ps.permisos::jsonb -> 'editar', '[]'::jsonb) || '["indicadores"]'::jsonb,
--          true)
--   from auth.users u
--  where u.id = ps.perfil_id
--    and ps.sector = 'fhcomercial'
--    and u.email = 'ignaciosanchez@4housing.com.ar'
--    and not coalesce((ps.permisos::jsonb -> 'editar') ? 'indicadores', false);

-- 5.c  VERIFICAR
--
-- select u.email,
--        (ps.permisos::jsonb -> 'ver')    ? 'indicadores' as ve_indicadores,
--        (ps.permisos::jsonb -> 'editar') ? 'indicadores' as carga_datos
--   from public.perfiles_sector ps
--   join auth.users u on u.id = ps.perfil_id
--  where ps.sector = 'fhcomercial'
--  order by u.email;


-- ----------------------------------------------------------------------------
-- 6. REALTIME — NO CORRER SIN DECIDIRLO
-- ----------------------------------------------------------------------------
-- El chat y las notificaciones usan `postgres_changes`. Las tablas nuevas no
-- entran solas a la publicación. Esto modifica un objeto GLOBAL del proyecto
-- (supabase_realtime), así que queda comentado para que lo corra Pablo
-- a conciencia. No rompe nada existente, pero no es para ejecutar de taquito.
--
-- alter publication supabase_realtime add table public.ind_chat_messages;
-- alter publication supabase_realtime add table public.ind_notifications;


-- ----------------------------------------------------------------------------
-- 7. VERIFICACIÓN — correr después y revisar que dé 11 filas con rls_activo=true
-- ----------------------------------------------------------------------------
-- select c.relname as tabla,
--        c.relrowsecurity as rls_activo,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename=c.relname) as politicas
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relkind='r' and c.relname like 'ind\_%'
--  order by c.relname;


-- ----------------------------------------------------------------------------
-- 8. ROLLBACK — deshace TODO lo de esta migración, sin tocar nada del CRM
-- ----------------------------------------------------------------------------
-- drop table if exists public.ind_rental_data, public.ind_stock_snapshots,
--   public.ind_ipc_data, public.ind_dtm_data, public.ind_facturacion_data,
--   public.ind_clientes_data, public.ind_stock_items,
--   public.ind_stock_movimientos, public.ind_stock_cierres,
--   public.ind_chat_messages, public.ind_notifications cascade;
-- drop function if exists public.ind_puede_editar();
