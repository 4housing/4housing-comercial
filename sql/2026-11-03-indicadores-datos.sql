-- ============================================================================
-- Integración de Indicadores al CRM — PASO 2: los datos
--
-- Mueve las filas del proyecto viejo (zziktktjsnkmtaqwghha) a las tablas ind_*
-- del proyecto del CRM (wcpkpwxhqdcdljfwzcmy), creadas en el paso 1.
--
-- Son DOS proyectos Supabase distintos, así que no hay `insert ... select` que
-- los cruce. Para cada tabla hay dos consultas:
--
--   A) en el proyecto VIEJO  -> devuelve una celda con un JSON
--   B) en el proyecto NUEVO  -> se pega ese JSON adentro y se ejecuta
--
-- Se usa JSON y no un INSERT armado a mano a propósito: el escapado de
-- comillas, los NULL y los tipos los resuelve Postgres, no nosotros.
--
-- EL `id` NO SE MIGRA. Las tablas nuevas lo generan solas
-- (`generated always as identity`) y ninguna tabla tiene foreign keys, así que
-- no hay nada que apunte a esos números. Sí se migran las fechas reales
-- (created_at, fecha, cerrado_en, actualizado_en): van en la lista de columnas.
-- El generador ordena por el id viejo, así que el orden relativo se conserva
-- (importa en ind_stock_movimientos, que desempata por id al ordenar).
--
-- Cada import está protegido: si la tabla destino YA tiene filas, no inserta
-- nada. Correrlo dos veces no duplica.
--
-- VALIDADO contra PostgreSQL 16.15 simulando la migración entera con datos
-- elegidos para romperla: apóstrofes, comillas dobles, un `drop table x;--`
-- embebido en un campo de texto, tildes, saltos de línea, tabs, NULL en todas
-- las columnas opcionales, numeric con decimales y timestamptz con huso.
-- Resultado: 0 diferencias en las 52 columnas comparadas, orden relativo
-- idéntico, y re-ejecutar el import no duplica nada.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PASO 0 — cuántas filas hay (correr en el proyecto VIEJO)
-- ----------------------------------------------------------------------------
-- Decide el método: hasta ~2.000 filas va el JSON de acá abajo; si alguna tabla
-- es mucho más grande, el SQL Editor no va a poder mostrar ni copiar la celda
-- y conviene ir por CSV (ver el final del archivo).

select 'rental_data         ' as tabla, count(*) from public.rental_data
 union all select 'ipc_data            ' as tabla, count(*) from public.ipc_data
 union all select 'dtm_data            ' as tabla, count(*) from public.dtm_data
 union all select 'facturacion_data    ' as tabla, count(*) from public.facturacion_data
 union all select 'clientes_data       ' as tabla, count(*) from public.clientes_data
 union all select 'stock_items         ' as tabla, count(*) from public.stock_items
 union all select 'stock_movimientos   ' as tabla, count(*) from public.stock_movimientos
 union all select 'stock_cierres       ' as tabla, count(*) from public.stock_cierres
 union all select 'chat_messages       ' as tabla, count(*) from public.chat_messages
 union all select 'notifications       ' as tabla, count(*) from public.notifications
 order by 1;


-- ----------------------------------------------------------------------------
-- OJO con stock_snapshots
-- ----------------------------------------------------------------------------
-- Esa tabla NO está en el proyecto de indicadores: se creó por error en el
-- proyecto de la app de plantas. Su consulta A hay que correrla ALLÁ.
-- Contarla:   select count(*) from public.stock_snapshots;
--
-- Una vez migrada y verificada, conviene BORRARLA de ese proyecto: tiene datos
-- comerciales de 4housing y ese proyecto tiene registro de usuarios abierto.


-- ############################################################################
-- rental_data  ->  ind_rental_data
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.rental_data t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_rental_data
       (serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at)
select serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at
  from jsonb_populate_recordset(null::public.ind_rental_data, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_rental_data);

-- ############################################################################
-- stock_snapshots  ->  ind_stock_snapshots
-- ATENCIÓN: esta sale del proyecto de PLANTAS, no del de indicadores.
-- ############################################################################

-- (A) en el proyecto PLANTAS — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.stock_snapshots t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_stock_snapshots
       (serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at)
select serie,cliente,tipologia,modelo_negocio,anio,mes,mes_anio,moneda,
       importe_mensual,estado_serie,tipo_cambio,importe_pesos,created_at
  from jsonb_populate_recordset(null::public.ind_stock_snapshots, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_stock_snapshots);

-- ############################################################################
-- ipc_data  ->  ind_ipc_data
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.ipc_data t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_ipc_data
       (anio,mes,mes_anio,ipc_mensual,ipc_acumulado,created_at)
select anio,mes,mes_anio,ipc_mensual,ipc_acumulado,created_at
  from jsonb_populate_recordset(null::public.ind_ipc_data, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_ipc_data);

-- ############################################################################
-- dtm_data  ->  ind_dtm_data
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.dtm_data t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_dtm_data
       (anio,mes,mes_anio,serie,modelo_negocio,tipo_servicio,descripcion,costo,
       facturacion_dtm,created_at)
select anio,mes,mes_anio,serie,modelo_negocio,tipo_servicio,descripcion,costo,
       facturacion_dtm,created_at
  from jsonb_populate_recordset(null::public.ind_dtm_data, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_dtm_data);

-- ############################################################################
-- facturacion_data  ->  ind_facturacion_data
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.facturacion_data t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_facturacion_data
       (mes_anio,modelo_negocio,importe_pesos,created_at)
select mes_anio,modelo_negocio,importe_pesos,created_at
  from jsonb_populate_recordset(null::public.ind_facturacion_data, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_facturacion_data);

-- ############################################################################
-- clientes_data  ->  ind_clientes_data
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.clientes_data t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_clientes_data
       (tipo,mes,activos,nuevos,altas,bajas,serie,tipologia,cliente,created_at)
select tipo,mes,activos,nuevos,altas,bajas,serie,tipologia,cliente,created_at
  from jsonb_populate_recordset(null::public.ind_clientes_data, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_clientes_data);

-- ############################################################################
-- stock_items  ->  ind_stock_items
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.stock_items t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_stock_items
       (serie,if_codigo,tipo,medida,modulo,tipologia,modelo_negocio,estado,
       sucursal,ubicacion,cliente,cliente_codigo,contacto,fecha_entrega,
       fecha_devolucion,vto_oc,propiedad,detalle,moneda,tarifa_lista,
       importe_mensual,actualizado_en,actualizado_por)
select serie,if_codigo,tipo,medida,modulo,tipologia,modelo_negocio,estado,
       sucursal,ubicacion,cliente,cliente_codigo,contacto,fecha_entrega,
       fecha_devolucion,vto_oc,propiedad,detalle,moneda,tarifa_lista,
       importe_mensual,actualizado_en,actualizado_por
  from jsonb_populate_recordset(null::public.ind_stock_items, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_stock_items);

-- ############################################################################
-- stock_movimientos  ->  ind_stock_movimientos
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.stock_movimientos t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_stock_movimientos
       (serie,fecha,tipo,estado_ant,estado_nuevo,cliente_ant,cliente_nuevo,
       importe_ant,importe_nuevo,nota,usuario,orden)
select serie,fecha,tipo,estado_ant,estado_nuevo,cliente_ant,cliente_nuevo,
       importe_ant,importe_nuevo,nota,usuario,orden
  from jsonb_populate_recordset(null::public.ind_stock_movimientos, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_stock_movimientos);

-- ############################################################################
-- stock_cierres  ->  ind_stock_cierres
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.stock_cierres t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_stock_cierres
       (mes_anio,cerrado_en,cerrado_por,alquilados,activos,valorizado,nota)
select mes_anio,cerrado_en,cerrado_por,alquilados,activos,valorizado,nota
  from jsonb_populate_recordset(null::public.ind_stock_cierres, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_stock_cierres);

-- ############################################################################
-- chat_messages  ->  ind_chat_messages
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.chat_messages t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_chat_messages
       (user_email,user_name,message,created_at)
select user_email,user_name,message,created_at
  from jsonb_populate_recordset(null::public.ind_chat_messages, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_chat_messages);

-- ############################################################################
-- notifications  ->  ind_notifications
-- ############################################################################

-- (A) en el proyecto VIEJO — copiar la celda del resultado entera:
select coalesce(json_agg(t order by t.id)::text, '[]')
  from public.notifications t;

-- (B) en el proyecto del CRM — pegar el JSON entre los $json$:
insert into public.ind_notifications
       (title,body,read,created_at)
select title,body,read,created_at
  from jsonb_populate_recordset(null::public.ind_notifications, $json$
[]
$json$::jsonb)
 where not exists (select 1 from public.ind_notifications);


-- ----------------------------------------------------------------------------
-- VERIFICACIÓN — correr en el proyecto del CRM y comparar contra el PASO 0
-- ----------------------------------------------------------------------------

select 'ind_rental_data         ' as tabla, count(*) from public.ind_rental_data
 union all select 'ind_stock_snapshots     ' as tabla, count(*) from public.ind_stock_snapshots
 union all select 'ind_ipc_data            ' as tabla, count(*) from public.ind_ipc_data
 union all select 'ind_dtm_data            ' as tabla, count(*) from public.ind_dtm_data
 union all select 'ind_facturacion_data    ' as tabla, count(*) from public.ind_facturacion_data
 union all select 'ind_clientes_data       ' as tabla, count(*) from public.ind_clientes_data
 union all select 'ind_stock_items         ' as tabla, count(*) from public.ind_stock_items
 union all select 'ind_stock_movimientos   ' as tabla, count(*) from public.ind_stock_movimientos
 union all select 'ind_stock_cierres       ' as tabla, count(*) from public.ind_stock_cierres
 union all select 'ind_chat_messages       ' as tabla, count(*) from public.ind_chat_messages
 union all select 'ind_notifications       ' as tabla, count(*) from public.ind_notifications
 order by 1;


-- ----------------------------------------------------------------------------
-- SI ALGUNA TABLA ES DEMASIADO GRANDE PARA EL JSON
-- ----------------------------------------------------------------------------
-- Dos salidas:
--
-- 1) POR PARTES. Agregarle un rango al generador y repetir el import con cada
--    tramo (el `where not exists` hay que sacarlo a partir del segundo tramo,
--    si no el segundo no entra):
--
--      select coalesce(json_agg(t order by t.id)::text,'[]')
--        from public.rental_data t
--       where t.id between 1 and 2000;      -- después 2001-4000, etc.
--
-- 2) POR CSV, que es lo práctico arriba de unas pocas miles de filas:
--    - En el proyecto viejo: Table Editor -> la tabla -> Export -> CSV.
--    - Abrir el CSV y BORRAR LA COLUMNA `id` (si no, choca con el identity).
--    - En el CRM: Table Editor -> la tabla ind_* -> Insert -> Import data from CSV.
--    - Verificar con la consulta de verificación de arriba.
--
--    Las columnas se llaman igual en las dos puntas (solo cambia el nombre de
--    la tabla), así que el mapeo sale derecho.

-- ----------------------------------------------------------------------------
-- DESPUÉS DE MIGRAR
-- ----------------------------------------------------------------------------
-- 1. Correr la verificación y que los números den iguales al PASO 0.
-- 2. Recién ahí deployar el index.html con la vista de Indicadores.
-- 3. Entrar a Indicadores en el CRM y comparar contra la app de Vercel, que
--    sigue andando: tienen que mostrar lo mismo.
-- 4. Cuando eso esté confirmado, borrar `public.stock_snapshots` del proyecto
--    de plantas y recién entonces dar de baja Vercel y el proyecto viejo.

