-- ============================================================================
-- Integración de Indicadores al CRM — PASO 2: los datos
--
-- Mueve las filas del proyecto viejo (zziktktjsnkmtaqwghha) a las tablas ind_*
-- del proyecto del CRM (wcpkpwxhqdcdljfwzcmy).
--
-- Armado con los conteos REALES de producción (3/11/2026): 2733 filas en total,
-- repartidas en 9 tablas. Ninguna necesita CSV.
--
-- Son DOS proyectos Supabase distintos, así que no hay `insert..select` que los
-- cruce. Para cada tabla hay dos consultas:
--
--   (A) en el proyecto VIEJO  -> devuelve UNA celda con un JSON. Copiarla entera.
--   (B) en el proyecto NUEVO  -> pegar ese JSON entre los $json$ y ejecutar.
--
-- Se usa JSON y no INSERTs armados a mano a propósito: el escapado de comillas,
-- los NULL y los tipos los resuelve Postgres en las dos puntas, no nosotros.
--
-- EL `id` NO SE MIGRA. Las tablas nuevas lo generan solas y ninguna tiene
-- foreign keys, así que nada apunta a esos números. Las fechas reales
-- (created_at, fecha, cerrado_en, actualizado_en) sí van explícitas. El
-- generador ordena por el id viejo, así que se conserva el orden relativo —
-- importa en ind_stock_movimientos, que desempata por id.
--
-- CADA IMPORT ESTÁ PROTEGIDO con un `where` que mira cuántas filas hay ya en
-- la tabla destino. Si no coincide con lo esperado, no inserta nada. Eso hace
-- que correr una tanda dos veces no duplique, y que no se puedan correr fuera
-- de orden.
--
-- VALIDADO contra PostgreSQL 16.15 simulando la migración entera con datos
-- elegidos para romperla: apóstrofes, comillas dobles, un `drop table x;--`
-- embebido en un campo de texto, tildes, saltos de línea, tabs, NULL en todas
-- las columnas opcionales, numeric con decimales y timestamptz con huso.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- LO QUE HAY QUE MIGRAR
-- ----------------------------------------------------------------------------
--   rental_data           1829 filas   (4 tandas)
--   stock_movimientos      531 filas   (2 tandas)
--   stock_items            237 filas
--   clientes_data           82 filas
--   dtm_data                21 filas
--   chat_messages           10 filas
--   notifications           10 filas
--   ipc_data                 9 filas
--   facturacion_data         4 filas
--
-- NO hay nada que migrar en:
--   stock_snapshots      0 filas
--   stock_cierres        0 filas
--
-- `stock_cierres` está en cero porque nunca se pudo cerrar un mes:
-- `cerrarMes()` guarda primero la foto en stock_snapshots y recién después
-- escribe el cierre, y como esa tabla no existía en el proyecto viejo, la
-- función siempre cortó en el primer paso. Por eso stock_snapshots tampoco
-- tiene nada que traer: la tabla que quedó en el proyecto de la app de
-- plantas se creó ahí por error y nunca recibió una fila. No hay que tocar
-- ese proyecto. Con la migración del paso 1 la función queda arreglada y los
-- cierres van a empezar a funcionar.


-- ############################################################################
-- facturacion_data  ->  ind_facturacion_data        (4 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.facturacion_data t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_facturacion_data
       (mes_anio,modelo_negocio,importe_pesos,created_at)
select mes_anio,modelo_negocio,importe_pesos,created_at
  from datos, jsonb_populate_recordset(null::public.ind_facturacion_data, datos.filas)
 where (select count(*) from public.ind_facturacion_data) = 0;   -- debe insertar 4

-- ############################################################################
-- ipc_data  ->  ind_ipc_data        (9 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.ipc_data t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_ipc_data
       (anio,mes,mes_anio,ipc_mensual,ipc_acumulado,created_at)
select anio,mes,mes_anio,ipc_mensual,ipc_acumulado,created_at
  from datos, jsonb_populate_recordset(null::public.ind_ipc_data, datos.filas)
 where (select count(*) from public.ind_ipc_data) = 0;   -- debe insertar 9

-- ############################################################################
-- chat_messages  ->  ind_chat_messages        (10 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.chat_messages t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_chat_messages
       (user_email,user_name,message,created_at)
select user_email,user_name,message,created_at
  from datos, jsonb_populate_recordset(null::public.ind_chat_messages, datos.filas)
 where (select count(*) from public.ind_chat_messages) = 0;   -- debe insertar 10

-- ############################################################################
-- notifications  ->  ind_notifications        (10 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.notifications t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_notifications
       (title,body,read,created_at)
select title,body,read,created_at
  from datos, jsonb_populate_recordset(null::public.ind_notifications, datos.filas)
 where (select count(*) from public.ind_notifications) = 0;   -- debe insertar 10

-- ############################################################################
-- dtm_data  ->  ind_dtm_data        (21 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.dtm_data t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_dtm_data
       (anio,mes,mes_anio,serie,modelo_negocio,tipo_servicio,descripcion,
       costo,facturacion_dtm,created_at)
select anio,mes,mes_anio,serie,modelo_negocio,tipo_servicio,descripcion,
       costo,facturacion_dtm,created_at
  from datos, jsonb_populate_recordset(null::public.ind_dtm_data, datos.filas)
 where (select count(*) from public.ind_dtm_data) = 0;   -- debe insertar 21

-- ############################################################################
-- clientes_data  ->  ind_clientes_data        (82 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.clientes_data t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_clientes_data
       (tipo,mes,activos,nuevos,altas,bajas,serie,tipologia,cliente,
       created_at)
select tipo,mes,activos,nuevos,altas,bajas,serie,tipologia,cliente,
       created_at
  from datos, jsonb_populate_recordset(null::public.ind_clientes_data, datos.filas)
 where (select count(*) from public.ind_clientes_data) = 0;   -- debe insertar 82

-- ############################################################################
-- stock_items  ->  ind_stock_items        (237 filas)
-- ############################################################################

-- (A) proyecto VIEJO — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from public.stock_items t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_stock_items
       (serie,if_codigo,tipo,medida,modulo,tipologia,modelo_negocio,estado,
       sucursal,ubicacion,cliente,cliente_codigo,contacto,fecha_entrega,
       fecha_devolucion,vto_oc,propiedad,detalle,moneda,tarifa_lista,
       importe_mensual,actualizado_en,actualizado_por)
select serie,if_codigo,tipo,medida,modulo,tipologia,modelo_negocio,estado,
       sucursal,ubicacion,cliente,cliente_codigo,contacto,fecha_entrega,
       fecha_devolucion,vto_oc,propiedad,detalle,moneda,tarifa_lista,
       importe_mensual,actualizado_en,actualizado_por
  from datos, jsonb_populate_recordset(null::public.ind_stock_items, datos.filas)
 where (select count(*) from public.ind_stock_items) = 0;   -- debe insertar 237

-- ############################################################################
-- stock_movimientos  ->  ind_stock_movimientos        (531 filas, 2 tandas)
-- ############################################################################

-- --- TANDA 1 de 2: filas 1 a 500 ---------------------------------
-- (A) proyecto VIEJO  ·  TANDA 1 de 2 — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from (select * from public.stock_movimientos order by id limit 500 offset 0) t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_stock_movimientos
       (serie,fecha,tipo,estado_ant,estado_nuevo,cliente_ant,cliente_nuevo,
       importe_ant,importe_nuevo,nota,usuario,orden)
select serie,fecha,tipo,estado_ant,estado_nuevo,cliente_ant,cliente_nuevo,
       importe_ant,importe_nuevo,nota,usuario,orden
  from datos, jsonb_populate_recordset(null::public.ind_stock_movimientos, datos.filas)
 where (select count(*) from public.ind_stock_movimientos) = 0;   -- debe insertar 500

-- --- TANDA 2 de 2: filas 501 a 531 ---------------------------------
-- (A) proyecto VIEJO  ·  TANDA 2 de 2 — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from (select * from public.stock_movimientos order by id limit 31 offset 500) t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_stock_movimientos
       (serie,fecha,tipo,estado_ant,estado_nuevo,cliente_ant,cliente_nuevo,
       importe_ant,importe_nuevo,nota,usuario,orden)
select serie,fecha,tipo,estado_ant,estado_nuevo,cliente_ant,cliente_nuevo,
       importe_ant,importe_nuevo,nota,usuario,orden
  from datos, jsonb_populate_recordset(null::public.ind_stock_movimientos, datos.filas)
 where (select count(*) from public.ind_stock_movimientos) = 500;   -- debe insertar 31

-- ############################################################################
-- rental_data  ->  ind_rental_data        (1829 filas, 4 tandas)
-- ############################################################################

-- --- TANDA 1 de 4: filas 1 a 500 ---------------------------------
-- (A) proyecto VIEJO  ·  TANDA 1 de 4 — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from (select * from public.rental_data order by id limit 500 offset 0) t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_rental_data
       (serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at)
select serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at
  from datos, jsonb_populate_recordset(null::public.ind_rental_data, datos.filas)
 where (select count(*) from public.ind_rental_data) = 0;   -- debe insertar 500

-- --- TANDA 2 de 4: filas 501 a 1000 ---------------------------------
-- (A) proyecto VIEJO  ·  TANDA 2 de 4 — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from (select * from public.rental_data order by id limit 500 offset 500) t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_rental_data
       (serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at)
select serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at
  from datos, jsonb_populate_recordset(null::public.ind_rental_data, datos.filas)
 where (select count(*) from public.ind_rental_data) = 500;   -- debe insertar 500

-- --- TANDA 3 de 4: filas 1001 a 1500 ---------------------------------
-- (A) proyecto VIEJO  ·  TANDA 3 de 4 — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from (select * from public.rental_data order by id limit 500 offset 1000) t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_rental_data
       (serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at)
select serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at
  from datos, jsonb_populate_recordset(null::public.ind_rental_data, datos.filas)
 where (select count(*) from public.ind_rental_data) = 1000;   -- debe insertar 500

-- --- TANDA 4 de 4: filas 1501 a 1829 ---------------------------------
-- (A) proyecto VIEJO  ·  TANDA 4 de 4 — copiar la celda entera:
select coalesce(json_agg(t order by t.id)::text, '[]') as datos
  from (select * from public.rental_data order by id limit 329 offset 1500) t;

-- (B) proyecto del CRM — pegar el JSON entre los $json$:
with pegado as (select $json$
[]
$json$::jsonb as j),
-- El editor de Supabase no copia el texto de la celda: copia el
-- resultado entero envuelto, o sea [{"datos": "<el json escapado>"}].
-- Esto acepta esa forma Y tambien el json crudo, asi no importa como
-- haya salido el copiar.
datos as (select case
    when jsonb_typeof(j) = 'array' and jsonb_typeof(j -> 0) = 'object'
         and (j -> 0) ? 'datos' then (j -> 0 ->> 'datos')::jsonb
    else j end as filas from pegado)
insert into public.ind_rental_data
       (serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at)
select serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at
  from datos, jsonb_populate_recordset(null::public.ind_rental_data, datos.filas)
 where (select count(*) from public.ind_rental_data) = 1500;   -- debe insertar 329


-- ----------------------------------------------------------------------------
-- VERIFICACIÓN FINAL — en el proyecto del CRM
-- ----------------------------------------------------------------------------
-- Tiene que dar exactamente estos números:
--   ind_rental_data             1829
--   ind_stock_snapshots            0
--   ind_ipc_data                   9
--   ind_dtm_data                  21
--   ind_facturacion_data           4
--   ind_clientes_data             82
--   ind_stock_items              237
--   ind_stock_movimientos        531
--   ind_stock_cierres              0
--   ind_chat_messages             10
--   ind_notifications             10

select 'ind_rental_data           ' as tabla, count(*) as filas, 1829 as esperado from public.ind_rental_data
 union all select 'ind_stock_snapshots       ' as tabla, count(*) as filas, 0 as esperado from public.ind_stock_snapshots
 union all select 'ind_ipc_data              ' as tabla, count(*) as filas, 9 as esperado from public.ind_ipc_data
 union all select 'ind_dtm_data              ' as tabla, count(*) as filas, 21 as esperado from public.ind_dtm_data
 union all select 'ind_facturacion_data      ' as tabla, count(*) as filas, 4 as esperado from public.ind_facturacion_data
 union all select 'ind_clientes_data         ' as tabla, count(*) as filas, 82 as esperado from public.ind_clientes_data
 union all select 'ind_stock_items           ' as tabla, count(*) as filas, 237 as esperado from public.ind_stock_items
 union all select 'ind_stock_movimientos     ' as tabla, count(*) as filas, 531 as esperado from public.ind_stock_movimientos
 union all select 'ind_stock_cierres         ' as tabla, count(*) as filas, 0 as esperado from public.ind_stock_cierres
 union all select 'ind_chat_messages         ' as tabla, count(*) as filas, 10 as esperado from public.ind_chat_messages
 union all select 'ind_notifications         ' as tabla, count(*) as filas, 10 as esperado from public.ind_notifications
 order by 1;

-- Y esta tiene que devolver CERO filas (si devuelve alguna, esa tabla no cuadra):

select 'ind_rental_data' as tabla, count(*) as filas, 1829 as esperado from public.ind_rental_data having count(*) <> 1829
 union all select 'ind_stock_snapshots' as tabla, count(*) as filas, 0 as esperado from public.ind_stock_snapshots having count(*) <> 0
 union all select 'ind_ipc_data' as tabla, count(*) as filas, 9 as esperado from public.ind_ipc_data having count(*) <> 9
 union all select 'ind_dtm_data' as tabla, count(*) as filas, 21 as esperado from public.ind_dtm_data having count(*) <> 21
 union all select 'ind_facturacion_data' as tabla, count(*) as filas, 4 as esperado from public.ind_facturacion_data having count(*) <> 4
 union all select 'ind_clientes_data' as tabla, count(*) as filas, 82 as esperado from public.ind_clientes_data having count(*) <> 82
 union all select 'ind_stock_items' as tabla, count(*) as filas, 237 as esperado from public.ind_stock_items having count(*) <> 237
 union all select 'ind_stock_movimientos' as tabla, count(*) as filas, 531 as esperado from public.ind_stock_movimientos having count(*) <> 531
 union all select 'ind_stock_cierres' as tabla, count(*) as filas, 0 as esperado from public.ind_stock_cierres having count(*) <> 0
 union all select 'ind_chat_messages' as tabla, count(*) as filas, 10 as esperado from public.ind_chat_messages having count(*) <> 10
 union all select 'ind_notifications' as tabla, count(*) as filas, 10 as esperado from public.ind_notifications having count(*) <> 10;


-- ----------------------------------------------------------------------------
-- DESPUÉS DE MIGRAR
-- ----------------------------------------------------------------------------
-- 1. Que la verificación dé los números de arriba.
-- 2. Recién ahí deployar el index.html con la vista de Indicadores.
-- 3. Entrar a Indicadores en el CRM y compararlo contra la app de Vercel,
--    que sigue andando: tienen que mostrar lo mismo.
-- 4. Confirmado eso, se puede dar de baja Vercel y el proyecto viejo.
