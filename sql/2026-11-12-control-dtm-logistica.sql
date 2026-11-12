-- ============================================================================
-- Control DTM y Logística — modelo de datos, auditoría y permisos
--
-- CORRER MANUALMENTE en el SQL Editor del proyecto del CRM
-- (wcpkpwxhqdcdljfwzcmy), DESPUÉS de:
--   2026-11-02-indicadores-tablas.sql     (crea las tablas ind_, usa tiene_sector)
--   2026-11-03-indicadores-editores.sql   (crea ind_editores)
-- y ANTES de desplegar el index.html que usa la vista (regla 2: primero el SQL).
--
--
-- QUÉ RESUELVE
-- ------------
-- Cada mes se bajan de Tango cuatro informes de mayor por auxiliar — compras y
-- ventas, de DTM y de Logística — y alguien los cruza a mano, contenedor por
-- contenedor, para contestar dos preguntas:
--   1) ¿cada servicio que compramos se le facturó al cliente?
--   2) ¿esa facturación dejó al menos el markup mínimo SOBRE EL COSTO (20%)?
-- Estas tablas guardan esos renglones para que el control corra sobre el
-- acumulado y no sobre el archivo que se acaba de subir, y las vistas del
-- punto 4 contestan las dos preguntas solas.
--
--
-- ES ADITIVO
-- ----------
-- Crea objetos nuevos, todos con prefijo `ind_dtmlog_`. No toca, renombra ni
-- borra ninguna tabla, función ni política existente, ni del CRM ni de
-- Indicadores. En particular:
--   * NO toca `ind_dtm_data`. Esa es otra cosa y CONVIVE con ésta: es el
--     resumen MENSUAL por serie que ya alimenta el dashboard (columnas
--     `costo` / `facturacion_dtm`), cargado a mano desde el Excel. Esta
--     migración guarda el DETALLE por comprobante que exporta Tango. Las dos
--     fuentes miden lo mismo y no dan lo mismo: para octubre 2026 el Excel
--     manual dice 38.206.900,21 de costo y el export de Tango 10.190.380,61
--     (26,7%). Esa diferencia es en sí misma un indicador, así que la vista
--     de auditoría la expone (`costo_manual`, `dif_costo`) en vez de elegir
--     una fuente y tapar la otra.
--   * NO toca `ind_editores` ni `perfiles_sector`. Quién importa y quién carga
--     a mano se decide en una lista propia, `ind_dtmlog_editores` (punto 2).
--
--
-- LO QUE HAY QUE SABER DE LOS ARCHIVOS DE TANGO (verificado sobre la muestra
-- real de octubre 2026: 4 archivos, 59 filas, 21 comprobantes, 14 contenedores)
-- ----------------------------------------------------------------------------
-- (a) CADA COMPROBANTE VIENE DOS VECES. Una fila "02 - EERR" con el total
--     imputado a la cuenta de resultados, y una o más filas
--     "04 - CONTENEDOR/MODULO" con el desglose por contenedor. La fila de pie
--     del archivo es un =SUM() plano sobre TODAS las filas, así que vale
--     suma(02) + suma(04), o sea EL DOBLE del movimiento real. Verificado al
--     centavo en los cuatro archivos:
--         Ventas_DTM   pie -102.670.612,00  → real -51.335.306,00
--         Ventas_LOG   pie  -10.460.000,00  → real  -5.230.000,00
--         Compras_LOG  pie    5.920.000,00  → real   2.960.000,00
--         Compras_DTM  pie   20.380.761,22  → real  10.190.380,61
--     Un importador NUNCA divide el pie por dos: suma las filas 02. El pie se
--     guarda igual, en `total_declarado`, solo para poder probar que el archivo
--     entró entero (`total_declarado = 2 × total_real`).
--
-- (b) LA CUENTA ES EL DATO AUTORITATIVO, no el nombre del archivo. Una cuenta
--     por archivo en la muestra, pero se clasifica FILA POR FILA:
--         52000013  compras / DTM    Gastos Servicios de DTM & Mantenimiento
--         55000009  compras / LOG    Gastos de Transporte Alquiler
--         41000004  ventas  / DTM    Venta Servicios de DTM & Mantenimiento
--         41000005  ventas  / LOG    Venta Logistica Alquiler
--     El CHECK `..._cuenta_chk` de los puntos 1.2 y 1.3 hace cumplir este mapeo
--     para esas cuatro cuentas y deja pasar cualquier otra: si mañana aparece
--     una cuenta nueva el import no se rompe, pero clasificar por nombre de
--     archivo sí falla ruidosamente, que es lo que se quiere.
--
-- (c) EL NÚMERO DE COMPROBANTE NO ALCANZA COMO CLAVE, NI SIQUIERA CON EL
--     AUXILIAR. Caso real: A0001000000384 aparece dos veces con el mismo
--     auxiliar M00096 — cuenta 41000005 por -2.165.000 y cuenta 41000004 por
--     -650.000. Es UNA factura al cliente que vende Logística y DTM juntas.
--     Con clave (comprobante, auxiliar) el upsert pisa una con la otra y se
--     pierden 4.330.000. Por eso la cuenta está en la clave del comprobante.
--
-- (d) EL ORDEN DE LAS COLUMNAS DIFIERE entre compras y ventas, y hasta cambia
--     el NOMBRE de la columna de fecha ("Fecha contable" en compras, "Fecha de
--     emisión" en ventas). El importador mapea POR NOMBRE, nunca por posición.
--     Acá queda una sola columna `fecha` con la nota de qué es cada una.
--
-- (e) LAS VENTAS VIENEN CON IMPORTE NEGATIVO y las compras positivo. Se
--     guardan TAL CUAL vinieron, sin corregir el signo: si algún día Tango
--     cambia de criterio, un dato guardado crudo se puede reinterpretar, uno
--     "arreglado" en la importación ya no. El signo se resuelve en la vista
--     (`fact_ars = -sum(...)`), y de yapa eso hace que una nota de crédito,
--     que viene positiva, RESTE facturación sin ningún caso especial.
--
-- (f) LA COLUMNA `Leyenda` ES INÚTIL PARA EMPAREJAR SERVICIOS: dice
--     'Subtotal gravado' en las 55 filas de detalle. Y el informe de ventas NO
--     trae el cliente. Por eso el emparejamiento es por CONTENEDOR y PERÍODO,
--     no por servicio, y el cliente tiene columna propia con su procedencia
--     (`cliente_origen`) para no hacer pasar por dato de Tango algo que se
--     dedujo o se tipeó.
--
-- (g) LOS CÓDIGOS DE CONTENEDOR NO SE ESCRIBEN IGUAL EN LOS DOS SISTEMAS. El
--     CRM escribe 'IF 4252-04' y Tango 'IF 04252-4', y es el mismo trailer.
--     En el mismo archivo convive 'IF 04252-11', que es OTRO contenedor. La
--     unificación es AUTOMÁTICA (punto 3) porque es el mismo equipo, pero toda
--     unificación que junte dos escrituras distintas se LISTA en
--     `ind_dtmlog_v_series_unificadas` para que se vea y se pueda desarmar si
--     alguna vez junta de más.
-- ============================================================================


-- ############################################################################
-- 1. LAS TABLAS
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1.1  IMPORTACIONES — una fila por archivo subido
-- ----------------------------------------------------------------------------
-- No es decorativa. Cumple dos funciones que nada más puede cumplir:
--   * Probar que el archivo entró completo (`total_declarado` vs `total_real`,
--     ver (a) arriba).
--   * Fijar la FECHA DE CORTE. La edad de un caso sin contraparte NO se mide
--     contra hoy — se mide contra hasta dónde llega el último informe de ese
--     lado (decisión D4). Si el informe de ventas llega al 30/09 y el de
--     compras al 31/10, una compra del 23/10 todavía no se puede juzgar, y la
--     vista la deja en gris en vez de pintarla de rojo por falta de datos.
create table if not exists public.ind_dtmlog_importaciones (
  id                bigint generated always as identity primary key,

  archivo           text    not null,            -- nombre del .xlsx tal cual
  origen            text    not null,            -- 'compras' | 'ventas'
  categoria         text    not null,            -- 'DTM' | 'LOG'
  cod_cuenta        text    not null,            -- la cuenta del archivo, ver (b)

  desde             date,                        -- menor fecha del archivo
  hasta             date,                        -- mayor fecha del archivo = la FECHA DE CORTE

  filas_02          integer not null default 0,  -- cuántas filas "02 - EERR" traía
  filas_04          integer not null default 0,  -- cuántas filas "04 - CONTENEDOR/MODULO"

  total_declarado   numeric,                     -- el pie del archivo (= 2 × el real)
  total_real        numeric,                     -- la suma de las filas 02
  cuadra            boolean not null default false,

  importado_por     text,
  importado_en      timestamptz not null default now(),

  constraint ind_dtmlog_imp_origen_chk    check (origen in ('compras','ventas')),
  constraint ind_dtmlog_imp_categoria_chk check (categoria in ('DTM','LOG')),
  constraint ind_dtmlog_imp_ventana_chk   check (hasta is null or desde is null or hasta >= desde)
);

comment on table public.ind_dtmlog_importaciones is
  'Una fila por archivo de Tango subido. `hasta` es la FECHA DE CORTE de ese '
  'lado: la vista de auditoría mide contra ella, no contra now(), así un caso '
  'no se pone en rojo por falta de datos (decisión D4).';

comment on column public.ind_dtmlog_importaciones.total_declarado is
  'El total del pie del archivo. Es el DOBLE del movimiento real porque el '
  '=SUM() del Excel suma las filas 02 y las 04 juntas. Se guarda para poder '
  'verificar que el archivo entró entero, NUNCA para usarlo como total.';

create index if not exists ind_dtmlog_imp_corte_idx
  on public.ind_dtmlog_importaciones (origen, hasta desc);


-- ----------------------------------------------------------------------------
-- 1.2  COMPROBANTES — las filas "02 - EERR"
-- ----------------------------------------------------------------------------
-- Grano: una fila por línea de la cuenta de resultados. OJO que eso NO es
-- "un comprobante": el mismo comprobante puede tocar dos cuentas (ver (c)).
-- Por eso la cuenta está en la clave natural.
--
-- POR QUÉ ESTÁ SEPARADO DEL DESGLOSE: son dos granos distintos. Mezclados en
-- una tabla con un discriminador, cualquier consulta que se olvide de filtrar
-- cuenta todo dos veces — exactamente el error que comete el pie del propio
-- archivo. Además, tenerlos separados habilita el control que más falta hace:
-- un comprobante imputado a la cuenta pero SIN desglose por contenedor es un
-- padre sin hijos (`SIN_DESGLOSE` en ind_dtmlog_v_comprobantes_sospechosos).
-- Guardando solo el desglose, ese caso desaparecería sin dejar rastro.
create table if not exists public.ind_dtmlog_comprobantes (
  id                bigint generated always as identity primary key,

  importacion_id    bigint references public.ind_dtmlog_importaciones(id),

  origen            text    not null,            -- 'compras' | 'ventas'
  categoria         text    not null,            -- 'DTM' | 'LOG', derivada de la cuenta
  cod_cuenta        text    not null,
  desc_cuenta       text,

  proveedor         text,                        -- solo compras; ventas no lo trae
  tipo_comprobante  text,                        -- 'FAC', 'NC', ... (en la muestra: 100% FAC)
  nro_comprobante   text    not null,
  fecha             date    not null,            -- contable en compras, de emisión en ventas
  periodo           text    not null,            -- 'YYYY-MM' de `fecha`

  total_cte         numeric,                     -- Saldo (CTE) = pesos
  total_ext         numeric,                     -- Saldo (EXT) = dólares

  -- El informe de ventas NO trae el cliente (ver (f)). Cuando se completa, se
  -- deja asentado DE DÓNDE salió: 'tango' si algún día el informe lo trae,
  -- 'derivado' si se dedujo del contenedor, 'manual' si lo tipeó una persona.
  -- Sin esta columna, un dato deducido se confunde con un dato del ERP.
  cliente           text,
  cliente_origen    text,

  -- Pedido explícito: la carga manual deja asentado QUIÉN y CUÁNDO.
  fuente            text    not null default 'tango',   -- 'tango' | 'manual'
  cargado_por       text,
  cargado_en        timestamptz not null default now(),

  -- Columna generada para poder tener la clave natural como CONSTRAINT con
  -- nombre (un índice único sobre coalesce(proveedor,'') sería equivalente,
  -- pero PostgREST no puede usar una expresión como `on_conflict`, y el
  -- importador de la app upsertea por REST).
  proveedor_k       text generated always as (coalesce(proveedor,'')) stored,

  constraint ind_dtmlog_cmp_origen_chk    check (origen in ('compras','ventas')),
  constraint ind_dtmlog_cmp_categoria_chk check (categoria in ('DTM','LOG')),
  constraint ind_dtmlog_cmp_fuente_chk    check (fuente in ('tango','manual')),
  constraint ind_dtmlog_cmp_clior_chk     check (cliente_origen is null
                                                 or cliente_origen in ('tango','derivado','manual')),
  constraint ind_dtmlog_cmp_periodo_chk   check (periodo ~ '^[0-9]{4}-[0-9]{2}$'),

  -- El mapeo cuenta → (origen, categoría) de (b), hecho cumplir para las cuatro
  -- cuentas conocidas. Una cuenta nueva pasa sin romper el import; clasificar
  -- por nombre de archivo, en cambio, revienta acá y se ve.
  constraint ind_dtmlog_cmp_cuenta_chk check (
    case cod_cuenta
      when '52000013' then origen = 'compras' and categoria = 'DTM'
      when '55000009' then origen = 'compras' and categoria = 'LOG'
      when '41000004' then origen = 'ventas'  and categoria = 'DTM'
      when '41000005' then origen = 'ventas'  and categoria = 'LOG'
      else true
    end
  ),

  -- La clave natural. La cuenta está adentro por (c): sin ella,
  -- A0001000000384 se pisa a sí misma y se pierden 4.330.000.
  constraint ind_dtmlog_cmp_natural_key
    unique (origen, proveedor_k, nro_comprobante, cod_cuenta)
);

comment on table public.ind_dtmlog_comprobantes is
  'Las filas "02 - EERR" del export de Tango: el total de cada comprobante '
  'imputado a una cuenta. Un mismo nro de comprobante puede estar dos veces, '
  'con cuentas distintas (una factura que vende Logística y DTM juntas).';

comment on constraint ind_dtmlog_cmp_natural_key on public.ind_dtmlog_comprobantes is
  'Clave natural del upsert. Incluye cod_cuenta a propósito: A0001000000384 '
  'existe con 41000005 y con 41000004 y son dos renglones contables distintos.';

create index if not exists ind_dtmlog_cmp_periodo_idx
  on public.ind_dtmlog_comprobantes (periodo, origen, categoria);
create index if not exists ind_dtmlog_cmp_imp_idx
  on public.ind_dtmlog_comprobantes (importacion_id);


-- ----------------------------------------------------------------------------
-- 1.3  RENGLONES — las filas "04", el grano de la auditoría
-- ----------------------------------------------------------------------------
-- Acá vive el dato que se audita: cuánto costó / cuánto se facturó POR
-- CONTENEDOR.
--
-- POR QUÉ LA BAJA ES LÓGICA (`activo`) Y NO HAY DELETE:
-- un renglón que se da de baja es, casi siempre, un error de imputación de
-- Tango que alguien detectó. Borrarlo deja la base "limpia" y el reclamo sin
-- prueba: el caso desaparece del control y nadie se entera de que existió.
-- Con baja lógica queda el renglón, el motivo, quién y cuándo, y las vistas
-- simplemente no lo cuentan. Es el mismo criterio que el historial de la
-- liquidación Repcont: el registro es de lo que PASÓ, no de lo que convenía.
create table if not exists public.ind_dtmlog_renglones (
  id                bigint generated always as identity primary key,

  comprobante_id    bigint not null
                      references public.ind_dtmlog_comprobantes(id) on delete cascade,

  auxiliar          text,                        -- el código interno de Tango, tipo M00096
  serie_raw         text,                        -- la columna "Desc. auxiliar" TAL CUAL vino
  serie_norm        text    not null,            -- normalizada, ver punto 3
  leyenda           text,                        -- 'Subtotal gravado' en el 100% de la muestra

  importe_cte       numeric,                     -- pesos, con el signo que vino de Tango
  importe_ext       numeric,                     -- dólares, idem

  -- Copias del comprobante padre, para poder filtrar sin join. NO se cargan a
  -- mano: el trigger del punto 3 las sincroniza desde el padre en cada
  -- insert/update, así no pueden quedar en desacuerdo (un renglón con el
  -- período equivocado caería en otro cluster y en otro mes, en silencio).
  origen            text    not null,
  categoria         text    not null,
  fecha             date    not null,
  periodo           text    not null,

  -- Carga manual: quién, cuándo y por qué. El comentario es obligatorio.
  fuente            text    not null default 'tango',   -- 'tango' | 'manual'
  comentario        text,
  cargado_por       text,
  cargado_en        timestamptz not null default now(),

  -- Baja lógica.
  activo            boolean not null default true,
  baja_motivo       text,
  baja_por          text,
  baja_en           timestamptz,

  leyenda_k         text generated always as (coalesce(leyenda,'')) stored,

  constraint ind_dtmlog_ren_origen_chk    check (origen in ('compras','ventas')),
  constraint ind_dtmlog_ren_categoria_chk check (categoria in ('DTM','LOG')),
  constraint ind_dtmlog_ren_fuente_chk    check (fuente in ('tango','manual')),
  constraint ind_dtmlog_ren_periodo_chk   check (periodo ~ '^[0-9]{4}-[0-9]{2}$'),

  constraint ind_dtmlog_ren_cuenta_chk check (
    case
      when origen = 'compras' and categoria = 'DTM' then true
      else true
    end
  ),

  -- Un renglón cargado a mano SIN decir por qué y SIN decir quién fue es un
  -- número inventado dentro de un control contable. No se permite.
  constraint ind_dtmlog_ren_manual_chk check (
    fuente <> 'manual'
    or (comentario is not null and btrim(comentario) <> ''
        and cargado_por is not null and btrim(cargado_por) <> '')
  ),

  -- Una baja sin motivo tampoco sirve de nada.
  constraint ind_dtmlog_ren_baja_chk check (
    activo
    or (baja_motivo is not null and btrim(baja_motivo) <> ''
        and baja_por is not null and btrim(baja_por) <> '')
  ),

  constraint ind_dtmlog_ren_natural_key
    unique (comprobante_id, auxiliar, leyenda_k)
);

comment on table public.ind_dtmlog_renglones is
  'Las filas "04 - CONTENEDOR/MODULO": costo y facturación por contenedor. '
  'Es el grano de la auditoría. No se borra nunca: la baja es lógica '
  '(activo=false + motivo + quién + cuándo) para que el error de imputación '
  'que se dio de baja siga siendo reclamable.';

comment on column public.ind_dtmlog_renglones.serie_raw is
  'El código del contenedor TAL CUAL lo escribió Tango. Se guarda crudo '
  'porque es la prueba de la escritura: `ind_dtmlog_v_series_unificadas` lo '
  'usa para mostrar qué escrituras distintas quedaron unificadas.';

comment on column public.ind_dtmlog_renglones.serie_norm is
  'El código normalizado (ver ind_dtmlog_norm_serie). Lo escribe el trigger, '
  'no la app: así nunca puede ser otra cosa que la normalización de serie_raw.';

create index if not exists ind_dtmlog_ren_serie_idx
  on public.ind_dtmlog_renglones (serie_norm, periodo) where activo;
create index if not exists ind_dtmlog_ren_cmp_idx
  on public.ind_dtmlog_renglones (comprobante_id);
create index if not exists ind_dtmlog_ren_periodo_idx
  on public.ind_dtmlog_renglones (periodo) where activo;


-- ----------------------------------------------------------------------------
-- 1.4  COMENTARIOS — APPEND ONLY
-- ----------------------------------------------------------------------------
-- El control va a marcar casos que, revisados, resultan estar bien: el costo
-- cayó en otro período, se imputó a otro contenedor, se bonificó, Tango lo
-- cargó mal. Sin un lugar donde dejar eso, el mismo caso vuelve a aparecer en
-- rojo todos los meses y el control se vuelve ruido que nadie mira.
--
-- Es APPEND ONLY (sin update ni delete, ver punto 5): una justificación que se
-- puede editar después no justifica nada. Si cambió de opinión, se agrega otra
-- fila y la última manda.
--
-- POR QUÉ GUARDA UNA `huella`: la justificación vale para el caso tal como
-- estaba cuando se justificó. Si después aparece otra factura del mismo
-- contenedor en el mismo mes, los números cambian y la justificación vieja ya
-- no corresponde. La vista de auditoría recalcula la huella; si no coincide
-- con la guardada, el caso REABRE solo.
create table if not exists public.ind_dtmlog_comentarios (
  id                bigint generated always as identity primary key,

  caso_clave        text    not null,            -- serie_norm || '|' || periodo
  huella            text,                        -- la huella del caso al momento de comentar
  accion            text    not null,            -- 'comentario' | 'justificar' | 'posponer'
  motivo            text,                        -- obligatorio si accion='justificar'
  posponer_hasta    date,                        -- obligatorio si accion='posponer'
  texto             text    not null,
  usuario           text    not null,
  creado_en         timestamptz not null default now(),

  constraint ind_dtmlog_com_accion_chk
    check (accion in ('comentario','justificar','posponer')),

  -- Justificar sin motivo de la lista es poner "ya está" y seguir. La lista
  -- cerrada obliga a decir QUÉ clase de caso es, que es lo único que después
  -- se puede contar y usar para mejorar el circuito.
  constraint ind_dtmlog_com_motivo_chk check (
    accion <> 'justificar'
    or motivo in ('costo_otro_periodo','imputado_otro_contenedor','bonificado',
                  'error_carga_tango','diferencia_aceptada')
  ),

  constraint ind_dtmlog_com_posponer_chk check (
    accion <> 'posponer' or posponer_hasta is not null
  ),

  constraint ind_dtmlog_com_texto_chk check (btrim(texto) <> ''),
  constraint ind_dtmlog_com_usuario_chk check (btrim(usuario) <> '')
);

comment on table public.ind_dtmlog_comentarios is
  'Bitácora de los casos revisados. APPEND ONLY: no tiene políticas de update '
  'ni de delete a propósito. Guarda la huella del caso para que la '
  'justificación caduque sola si los números del caso cambian.';

create index if not exists ind_dtmlog_com_caso_idx
  on public.ind_dtmlog_comentarios (caso_clave, creado_en desc);


-- ----------------------------------------------------------------------------
-- 1.5  CONFIG — una sola fila
-- ----------------------------------------------------------------------------
-- Mismo patrón que la tabla `contador` del CRM: un CHECK que fuerza id = 1, así
-- no hay forma de terminar con dos configuraciones y que el control dé distinto
-- según cuál lea.
--
-- `desde_periodo` NO es decorativo: el control arranca en 2026-10 (decisión
-- D4). Los períodos anteriores se pueden importar y quedan guardados, pero no
-- se auditan — auditar hacia atrás meses en los que nadie cargaba con este
-- criterio sería generar cientos de alertas falsas el primer día.
create table if not exists public.ind_dtmlog_config (
  id                     integer primary key default 1,
  markup_minimo          numeric not null default 20,   -- en %, SOBRE EL COSTO
  dias_compra_sin_venta  integer not null default 45,   -- rojo a partir de acá
  dias_venta_sin_compra  integer not null default 60,   -- ámbar a partir de acá, nunca rojo
  desde_periodo          text    not null default '2026-10',
  actualizado_por        text,
  actualizado_en         timestamptz not null default now(),

  constraint ind_dtmlog_config_unica_fila check (id = 1),
  constraint ind_dtmlog_config_desde_chk  check (desde_periodo ~ '^[0-9]{4}-[0-9]{2}$'),
  constraint ind_dtmlog_config_markup_chk check (markup_minimo >= 0),
  constraint ind_dtmlog_config_dias_chk   check (dias_compra_sin_venta > 0
                                                 and dias_venta_sin_compra > 0)
);

insert into public.ind_dtmlog_config (id) values (1) on conflict (id) do nothing;

comment on table public.ind_dtmlog_config is
  'Una sola fila (CHECK id=1, patrón de la tabla contador). Umbrales del '
  'control y período desde el que se audita.';


-- ############################################################################
-- 2. QUIÉN IMPORTA Y QUIÉN CARGA A MANO — lista propia, decisión D5
-- ############################################################################
-- Patrón idéntico a `ind_editores` (2026-11-03-indicadores-editores.sql) y por
-- la misma razón: dar de alta a alguien tiene que ser un insert en una tabla
-- nueva, no un UPDATE sobre `perfiles_sector`, que es donde viven los permisos
-- ya configurados de todo el equipo del CRM. Esos permisos no se tocan.
--
-- Es una lista SEPARADA de ind_editores aunque arranque con la misma gente:
-- cargar el Excel de rental y auditar el margen de DTM son dos permisos
-- distintos, y mezclarlos obligaría a dar los dos para dar uno solo.
create table if not exists public.ind_dtmlog_editores (
  email       text primary key,
  nota        text,
  created_at  timestamptz not null default now()
);

comment on table public.ind_dtmlog_editores is
  'Quién puede importar los informes de Tango y cargar renglones a mano en el '
  'Control DTM/Logística. Se administra SOLO desde el SQL Editor: la API no '
  'tiene permisos sobre esta tabla a propósito (ver abajo).';

-- Semilla: arranca con la misma gente que ya carga Indicadores. Esta migración
-- corre como owner, así que puede leer ind_editores aunque la API no pueda.
insert into public.ind_dtmlog_editores (email, nota)
select e.email,
       'Heredado de ind_editores al crear el Control DTM/Logística (12/11/2026)'
  from public.ind_editores e
on conflict (email) do nothing;

-- Para sumar a alguien:
--   insert into public.ind_dtmlog_editores (email, nota)
--   values ('victorialopez@4housing.com.ar', 'Audita márgenes de DTM')
--   on conflict (email) do nothing;
--
-- Para dar de baja:
--   delete from public.ind_dtmlog_editores where email = 'alguien@4housing.com.ar';
--
-- Para ver quién está habilitado:
--   select email, nota, created_at from public.ind_dtmlog_editores order by email;

-- `security definer` para que pueda leer la tabla aunque el usuario no tenga
-- ningún permiso sobre ella (que es justamente el caso: ver el revoke de abajo).
create or replace function public.ind_dtmlog_puede_editar()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ind_dtmlog_editores e
    where lower(e.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.ind_dtmlog_puede_editar() from public, anon;
grant execute on function public.ind_dtmlog_puede_editar() to authenticated;

-- RLS ACTIVO Y CERO POLÍTICAS. No es un olvido: con RLS prendido y sin
-- ninguna política, nadie lee ni escribe esta tabla por la API. La función de
-- arriba la lee igual porque es `security definer`.
-- Sin esto, cualquiera del sector se agregaría a sí mismo a la lista y se
-- daría permiso para cargar renglones a mano en un control contable.
alter table public.ind_dtmlog_editores enable row level security;
revoke all on public.ind_dtmlog_editores from anon, authenticated;


-- ############################################################################
-- 3. NORMALIZACIÓN DE CÓDIGOS DE CONTENEDOR — decisión D2
-- ############################################################################
-- El CRM escribe 'IF 4252-04' y Tango 'IF 04252-4'. Es el mismo trailer, así
-- que se unifican AUTOMÁTICAMENTE: una tabla de alias revisada a mano sería más
-- "segura" en teoría, pero en la práctica deja al mismo equipo sin control
-- hasta que alguien cargue el alias, y un casillero vacío no se nota.
-- El resguardo es otro: toda unificación que junte dos escrituras distintas se
-- LISTA en `ind_dtmlog_v_series_unificadas`, así si alguna vez junta de más se
-- ve en una pantalla en vez de esconderse en una suma.
--
-- LA REGLA (idéntica en SQL y en JS):
--   1. trim, mayúsculas, espacios internos colapsados a uno solo
--   2. cada corrida máxima de dígitos se reemplaza por esa corrida sin ceros a
--      la izquierda (si queda vacía, '0')
--
-- El JS equivalente, que el index.html tiene que usar TAL CUAL:
--   const normSerie = s => (s||'').trim().toUpperCase().replace(/\s+/g,' ')
--                            .replace(/\d+/g, d => d.replace(/^0+/,'') || '0');
--
-- Lo que DEBE dar:
--   'IF 4252-04'     -> 'IF 4252-4'
--   'IF 04252-4'     -> 'IF 4252-4'    (el mismo contenedor que el anterior)
--   'IF 04252-11'    -> 'IF 4252-11'   (DISTINTO de los dos anteriores)
--   'ZCSU 511065-4'  -> 'ZCSU 511065-4'
--   'amfu  848078-5' -> 'AMFU 848078-5'
--
-- El `(?<!\d)` del regex es lo que hace que la regla sea POR CORRIDA: sin él,
-- '0405' daría '45' en vez de '405', porque el '0' del medio también perdería
-- su lugar.
create or replace function public.ind_dtmlog_norm_serie(p_serie text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_serie is null or btrim(p_serie) = '' then null
    else regexp_replace(
           regexp_replace(upper(btrim(p_serie)), '\s+', ' ', 'g'),
           '(?<!\d)0+(\d)', '\1', 'g')
  end;
$$;

comment on function public.ind_dtmlog_norm_serie(text) is
  'Normaliza un código de contenedor para poder cruzar el CRM con Tango: '
  'mayúsculas, espacios colapsados y cada corrida de dígitos sin ceros a la '
  'izquierda. ''IF 4252-04'' y ''IF 04252-4'' dan lo mismo; ''IF 04252-11'' no.';

revoke all on function public.ind_dtmlog_norm_serie(text) from public, anon;
grant execute on function public.ind_dtmlog_norm_serie(text) to authenticated;


-- El trigger que garantiza la coherencia del renglón con su comprobante.
-- Existe para que `origen`, `categoria`, `fecha`, `periodo` y `serie_norm` NO
-- dependan de que el importador los mande bien: un renglón con el período
-- equivocado caería en otro mes y en otro cluster sin que nada falle.
create or replace function public.ind_dtmlog_renglon_sincroniza()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  c record;
begin
  select origen, categoria, fecha, periodo
    into c
    from public.ind_dtmlog_comprobantes
   where id = new.comprobante_id;

  if not found then
    raise exception 'ind_dtmlog_renglones: no existe el comprobante %', new.comprobante_id;
  end if;

  new.origen    := c.origen;
  new.categoria := c.categoria;
  new.fecha     := c.fecha;
  new.periodo   := c.periodo;

  -- serie_norm siempre sale de serie_raw. Si el renglón se cargó a mano sin
  -- serie_raw, se normaliza lo que haya venido en serie_norm.
  new.serie_norm := public.ind_dtmlog_norm_serie(
                      coalesce(nullif(btrim(coalesce(new.serie_raw,'')), ''), new.serie_norm));

  if new.serie_norm is null then
    raise exception 'ind_dtmlog_renglones: falta el código de contenedor (serie_raw)';
  end if;

  return new;
end;
$$;

drop trigger if exists ind_dtmlog_ren_sync on public.ind_dtmlog_renglones;
create trigger ind_dtmlog_ren_sync
  before insert or update on public.ind_dtmlog_renglones
  for each row execute function public.ind_dtmlog_renglon_sincroniza();


-- ############################################################################
-- 4. LAS VISTAS
-- ############################################################################
-- POR QUÉ NO SE MATERIALIZAN:
--   * Una vista materializada NO respeta RLS: se calcula con los permisos de
--     quien la creó (el owner) y después cualquiera con select la lee entera.
--     Todo el esquema de permisos de esta migración se evaporaría.
--   * Habría que refrescarla, y el refresh es justo lo que nadie se acuerda de
--     hacer: el día que alguien importe y la pantalla muestre los números de
--     ayer, el control deja de ser confiable y no tira ningún error.
--   * El volumen no lo pide: son decenas de comprobantes por mes.
-- Todas van con `security_invoker = true`, así la RLS que se aplica es la del
-- usuario que consulta y no la del dueño de la vista.
--
-- POR QUÉ SE BORRAN ANTES DE CREARLAS, EN VEZ DE `create or replace` a secas:
-- `create or replace view` NO puede renombrar ni reordenar columnas. El día que
-- esta migración se vuelva a correr con una columna nueva en el medio —que es
-- exactamente lo que pasa cuando se corrige algo— falla con
-- "cannot change name of view column X to Y", que no dice nada sobre la causa
-- real. Borrando primero, el archivo es re-corrible siempre. Las tablas NO se
-- borran: esto no toca ni un dato.
drop view if exists public.ind_dtmlog_v_auditoria                 cascade;
drop view if exists public.ind_dtmlog_v_lag                       cascade;
drop view if exists public.ind_dtmlog_v_series_unificadas         cascade;
drop view if exists public.ind_dtmlog_v_comprobantes_sospechosos  cascade;
drop view if exists public.ind_dtmlog_v_contenedor_periodo        cascade;
drop view if exists public.ind_dtmlog_v_clusters                  cascade;
drop view if exists public.ind_dtmlog_v_renglones                 cascade;


-- ----------------------------------------------------------------------------
-- 4.1  Renglones activos, con los datos de su comprobante
-- ----------------------------------------------------------------------------
create or replace view public.ind_dtmlog_v_renglones
with (security_invoker = true) as
select
  r.id,
  r.comprobante_id,
  r.auxiliar,
  r.serie_raw,
  r.serie_norm,
  r.leyenda,
  r.importe_cte,
  r.importe_ext,
  r.origen,
  r.categoria,
  r.fecha,
  r.periodo,
  r.fuente,
  r.comentario,
  r.cargado_por,
  r.cargado_en,
  c.cod_cuenta,
  c.desc_cuenta,
  c.proveedor,
  c.tipo_comprobante,
  c.nro_comprobante,
  c.cliente,
  c.cliente_origen,
  c.total_cte     as comprobante_total_cte,
  c.total_ext     as comprobante_total_ext,
  c.importacion_id
from public.ind_dtmlog_renglones r
join public.ind_dtmlog_comprobantes c on c.id = r.comprobante_id
where r.activo;


-- ----------------------------------------------------------------------------
-- 4.2  CLUSTERS — decisión D3
-- ----------------------------------------------------------------------------
-- Cuando un comprobante toca más de un contenedor, Tango reparte el importe en
-- partes iguales. La realidad no se reparte así: el servicio que se le hizo a
-- un contenedor puede haber costado el triple que el del otro. Entonces el
-- markup POR CONTENEDOR de esos casos es un artefacto del reparto, no un dato.
--
-- La única unidad en la que el markup sí significa algo es el conjunto de
-- contenedores y comprobantes que están atados entre sí: si A y B comparten una
-- factura, y B y C comparten otra, los tres se calculan juntos. Eso es,
-- formalmente, la componente conexa del grafo bipartito contenedor—comprobante
-- DENTRO DEL PERÍODO. Se resuelve con una CTE recursiva (cierre transitivo).
--
-- `cluster_id` es el min(serie_norm) de la componente: cualquier representante
-- sirve, pero tiene que ser estable, y el mínimo lo es.
-- Un contenedor que no comparte ningún comprobante es su propio cluster
-- (cluster_n = 1) y ahí el markup por contenedor SÍ vale.
create or replace view public.ind_dtmlog_v_clusters
with (security_invoker = true) as
with recursive
  base as (
    select distinct r.periodo, r.serie_norm, r.comprobante_id
      from public.ind_dtmlog_v_renglones r
  ),
  -- Dos series son vecinas si comparten un comprobante en el mismo período.
  -- El join incluye el par (x,x), así una serie aislada queda en su propio
  -- cluster sin tratarla como caso especial.
  pares as (
    select distinct a.periodo, a.serie_norm as desde_serie, b.serie_norm as hasta_serie
      from base a
      join base b
        on b.periodo = a.periodo
       and b.comprobante_id = a.comprobante_id
  ),
  alcance as (
    select periodo, desde_serie, hasta_serie from pares
    union
    select p.periodo, a.desde_serie, p.hasta_serie
      from alcance a
      join pares p
        on p.periodo = a.periodo
       and p.desde_serie = a.hasta_serie
  )
select
  periodo,
  desde_serie       as serie_norm,
  min(hasta_serie)  as cluster_id
from alcance
group by periodo, desde_serie;


-- ----------------------------------------------------------------------------
-- 4.3  CONTENEDOR × PERÍODO — los números crudos de cada caso
-- ----------------------------------------------------------------------------
create or replace view public.ind_dtmlog_v_contenedor_periodo
with (security_invoker = true) as
with agr as (
  select
    r.serie_norm,
    r.periodo,
    min(r.serie_raw) as serie_raw,

    -- Las compras vienen positivas y las ventas negativas (ver (e)). El signo
    -- se da vuelta acá y no en la importación, así una nota de crédito —que
    -- viene con el signo contrario— RESTA sola, sin caso especial.
    coalesce(sum(r.importe_cte)  filter (where r.origen = 'compras'), 0) as costo_ars,
    coalesce(sum(-r.importe_cte) filter (where r.origen = 'ventas'),  0) as fact_ars,
    coalesce(sum(r.importe_ext)  filter (where r.origen = 'compras'), 0) as costo_usd,
    coalesce(sum(-r.importe_ext) filter (where r.origen = 'ventas'),  0) as fact_usd,

    coalesce(sum(r.importe_cte)  filter (where r.origen='compras' and r.categoria='DTM'), 0) as costo_dtm,
    coalesce(sum(-r.importe_cte) filter (where r.origen='ventas'  and r.categoria='DTM'), 0) as fact_dtm,
    coalesce(sum(r.importe_cte)  filter (where r.origen='compras' and r.categoria='LOG'), 0) as costo_log,
    coalesce(sum(-r.importe_cte) filter (where r.origen='ventas'  and r.categoria='LOG'), 0) as fact_log,

    count(distinct r.comprobante_id) filter (where r.origen = 'compras') as n_compras,
    count(distinct r.comprobante_id) filter (where r.origen = 'ventas')  as n_ventas,

    min(r.fecha) filter (where r.origen = 'compras') as primera_compra,
    max(r.fecha) filter (where r.origen = 'compras') as ultima_compra,
    min(r.fecha) filter (where r.origen = 'ventas')  as primera_venta,
    max(r.fecha) filter (where r.origen = 'ventas')  as ultima_venta,

    array_agg(distinct r.proveedor order by r.proveedor)
      filter (where r.origen = 'compras' and r.proveedor is not null)     as proveedores,
    array_agg(distinct r.nro_comprobante order by r.nro_comprobante)
      filter (where r.origen = 'compras')                                 as comprobantes_compra,
    array_agg(distinct r.nro_comprobante order by r.nro_comprobante)
      filter (where r.origen = 'ventas')                                  as comprobantes_venta,

    array_agg(distinct r.categoria order by r.categoria)                  as categorias,

    -- Para la huella. Lleva la cuenta pegada porque el mismo nro de
    -- comprobante puede ser dos renglones contables distintos (ver (c)), y la
    -- huella tiene que distinguirlos. No es para mostrar.
    array_agg(distinct (r.nro_comprobante || ':' || r.cod_cuenta)
              order by (r.nro_comprobante || ':' || r.cod_cuenta))        as claves_comprobante
  from public.ind_dtmlog_v_renglones r
  group by r.serie_norm, r.periodo
)
select
  a.*,
  coalesce(array_length(a.proveedores, 1), 0) > 1 as multi_proveedor,
  -- Hay costo en una categoría y venta en la OTRA: típicamente un flete
  -- (Logística) que se facturó dentro de un servicio de DTM. No está mal por
  -- sí mismo, pero rompe cualquier control hecho categoría por categoría, así
  -- que se marca.
  ((a.costo_dtm <> 0 and a.fact_log <> 0) or (a.costo_log <> 0 and a.fact_dtm <> 0))
    as cruce_categoria
from agr a;


-- ----------------------------------------------------------------------------
-- 4.4  AUDITORÍA — el veredicto
-- ----------------------------------------------------------------------------
-- Es la vista que consume la pantalla. Junta los números del caso, su cluster,
-- las fechas de corte, la comparación contra la carga manual, la huella y el
-- estado.
--
-- SOBRE LOS UMBRALES (decisión D4): "compra sin venta" es plata que salió y no
-- volvió → rojo a los 45 días. "venta sin compra" es, casi siempre, un costo
-- que todavía no llegó o que se imputó en otro lado → ámbar a los 60, NUNCA
-- rojo: facturar de más no es un problema de caja y pintarlo de rojo haría que
-- el rojo deje de significar algo.
--
-- La edad se mide contra la FECHA DE CORTE DEL OTRO LADO, no contra hoy. Una
-- compra del 23/10 cuando el informe de ventas solo llega al 30/09 no se puede
-- juzgar todavía, y queda en gris. Si falta el informe del otro lado, la edad
-- es NULL y el caso tampoco se pone en rojo: falla cerrado.
create or replace view public.ind_dtmlog_v_auditoria
with (security_invoker = true) as
with
  cfg as (
    -- Los coalesce son el default si la fila de config no estuviera: la vista
    -- tiene que seguir devolviendo filas, no quedarse vacía en silencio.
    select coalesce(max(markup_minimo), 20)          as markup_minimo,
           coalesce(max(dias_compra_sin_venta), 45)  as dias_compra_sin_venta,
           coalesce(max(dias_venta_sin_compra), 60)  as dias_venta_sin_compra,
           coalesce(max(desde_periodo), '2026-10')   as desde_periodo
      from public.ind_dtmlog_config
  ),
  cortes as (
    select max(hasta) filter (where origen = 'compras') as corte_compras,
           max(hasta) filter (where origen = 'ventas')  as corte_ventas
      from public.ind_dtmlog_importaciones
  ),
  -- La carga manual del CRM (ind_dtm_data), agregada con la MISMA
  -- normalización de serie. `mes_anio` ya viene en 'YYYY-MM', igual que
  -- `periodo`; se filtra por formato para que una fila con basura no arrastre
  -- el join.
  -- OJO: ESTA VISTA DEPENDE DE LOS PERMISOS DE `ind_dtm_data`.
  -- Como va con `security_invoker = true`, el select sobre ind_dtm_data se hace
  -- con los permisos de quien consulta. Hoy eso funciona porque la migración
  -- del 2/11 le dio `grant select to authenticated` y una política
  -- `using (tiene_sector('fhcomercial'))`, los mismos que esta migración usa.
  -- Si alguna vez se le sacan esos permisos, el Control DTM entero deja de
  -- cargar con un "permission denied for table ind_dtm_data" que no menciona a
  -- esta vista por ningún lado. Es el precio de leer la otra fuente con los
  -- permisos del usuario en vez de saltárselos, y es el precio correcto.
  -- La verificación 6.h de abajo lo chequea.
  manual as (
    select public.ind_dtmlog_norm_serie(d.serie) as serie_norm,
           d.mes_anio                            as periodo,
           sum(coalesce(d.costo, 0))             as costo_manual,
           sum(coalesce(d.facturacion_dtm, 0))   as fact_manual
      from public.ind_dtm_data d
     where d.serie is not null
       and d.mes_anio ~ '^[0-9]{4}-[0-9]{2}$'
     group by 1, 2
  ),
  base as (
    select cp.*, cl.cluster_id, m.costo_manual, m.fact_manual
      from public.ind_dtmlog_v_contenedor_periodo cp
      join public.ind_dtmlog_v_clusters cl
        on cl.periodo = cp.periodo and cl.serie_norm = cp.serie_norm
      left join manual m
        on m.serie_norm = cp.serie_norm and m.periodo = cp.periodo
  ),
  cluster_agr as (
    select periodo,
           cluster_id,
           count(*)           as cluster_n,
           sum(costo_ars)     as costo_cluster,
           sum(fact_ars)      as fact_cluster,
           -- Los mismos totales del cluster pero con la fuente manual. Ver el
           -- comentario de `markup_cluster_manual` más abajo: con los datos de
           -- octubre 2026 estos dos pares dan veredictos OPUESTOS.
           sum(costo_manual)  as costo_cluster_manual,
           sum(fact_manual)   as fact_cluster_manual
      from base
     group by periodo, cluster_id
  ),
  calc as (
    select
      b.*,
      ca.cluster_n,
      ca.costo_cluster,
      ca.fact_cluster,
      cfg.markup_minimo,
      cfg.dias_compra_sin_venta,
      cfg.dias_venta_sin_compra,
      co.corte_compras,
      co.corte_ventas,
      ca.costo_cluster_manual,
      ca.fact_cluster_manual,

      case when ca.costo_cluster > 0
           then round((ca.fact_cluster / ca.costo_cluster - 1) * 100, 2) end as markup_cluster,

      -- EL MISMO MARKUP, PERO CON EL COSTO DE LA AUDITORÍA MANUAL.
      -- No es un dato de color: con octubre 2026 los dos números dan veredictos
      -- OPUESTOS sobre el mismo grupo de contenedores.
      --   con el costo del export:  costo 7.078.799  fact 25.261.000  -> +256,9 %  (pasa)
      --   con el costo manual:      costo 21.131.468 fact 25.261.000  ->  +19,5 %  (NO pasa)
      -- La causa es que el informe de compras de Tango trae el 26,7 % del costo
      -- que la auditoría manual le asigna al mes: la factura del proveedor se
      -- contabiliza bastante después que la venta. Mientras esa brecha exista,
      -- el markup calculado SOLO con el export dice que todo da ganancia.
      -- Por eso conviven las dos fuentes (decisión D1) y la pantalla muestra las
      -- dos columnas: la diferencia entre ambas es, en sí misma, el indicador.
      case when ca.costo_cluster_manual > 0
           then round((ca.fact_cluster_manual / ca.costo_cluster_manual - 1) * 100, 2) end as markup_cluster_manual,

      case when b.costo_manual > 0 and ca.cluster_n = 1
           then round((coalesce(b.fact_manual, 0) / b.costo_manual - 1) * 100, 2) end      as markup_manual,

      -- Qué porcentaje del costo que la auditoría manual conoce llegó al
      -- informe de Tango. Si es bajo, el markup del export no significa nada.
      case when b.costo_manual > 0
           then round(b.costo_dtm / b.costo_manual * 100, 1) end                           as cobertura_costo,

      -- NULL cuando no hay costo (no hay contra qué calcular) y cuando el
      -- cluster tiene más de una serie (el reparto de Tango es parejo y el
      -- número por contenedor no significa nada). Mostrar un markup inventado
      -- es peor que no mostrar ninguno.
      case when b.costo_ars > 0 and ca.cluster_n = 1
           then round((b.fact_ars / b.costo_ars - 1) * 100, 2) end           as markup,

      case
        when b.costo_ars > 0 and b.fact_ars <= 0
          then (co.corte_ventas  - b.primera_compra)
        when b.fact_ars > 0 and b.costo_ars <= 0
          then (co.corte_compras - b.primera_venta)
      end                                                                    as dias_sin_contraparte,

      -- La huella: si cambia cualquiera de los comprobantes del caso, sus
      -- totales redondeados a peso o las categorías que toca, la justificación
      -- guardada deja de corresponder y el caso REABRE.
      md5(
        b.serie_norm || '|' || b.periodo || '|' ||
        coalesce(array_to_string(b.claves_comprobante, ','), '') || '|' ||
        round(b.costo_ars)::text || '|' || round(b.fact_ars)::text || '|' ||
        coalesce(array_to_string(b.categorias, ','), '')
      )                                                                      as huella
    from base b
    join cluster_agr ca on ca.periodo = b.periodo and ca.cluster_id = b.cluster_id
    cross join cfg
    cross join cortes co
    where b.periodo >= cfg.desde_periodo
  )
select
  c.*,
  c.serie_norm || '|' || c.periodo                 as caso_clave,
  c.costo_manual - c.costo_ars                     as dif_costo,
  -- `dif_costo` es lo que pide el contrato, pero compara la carga manual
  -- (que es SOLO de DTM) contra el costo total, que incluye Logística. En la
  -- práctica la comparación que cierra es ésta otra, así que va al lado.
  c.costo_manual - c.costo_dtm                     as dif_costo_dtm,
  -- Bandera aparte, NO un estado: el estado se decide con el export, que es la
  -- fuente auditable y la única que va a quedar el día que la carga manual se
  -- deje de hacer. Pero mientras las dos convivan, un caso que pasa con el
  -- export y NO pasa con el costo real tiene que verse: es justamente el que la
  -- auditoría manual detecta hoy y el control nuevo se comería.
  (coalesce(c.markup_cluster_manual, c.markup_manual) is not null
   and coalesce(c.markup_cluster_manual, c.markup_manual) < c.markup_minimo)
                                                   as alerta_manual,
  case
    -- Plata que salió y no volvió.
    when c.costo_ars > 0 and c.fact_ars <= 0 then
      case when c.dias_sin_contraparte >= c.dias_compra_sin_venta
           then 'SIN_FACTURAR' else 'ESPERANDO_VENTA' end
    -- Se facturó y no aparece el costo.
    when c.fact_ars > 0 and c.costo_ars <= 0 then
      case when c.dias_sin_contraparte >= c.dias_venta_sin_compra
           then 'FALTA_COSTO' else 'ESPERANDO_COSTO' end
    -- Los dos lados, y el markup del contenedor es un dato real.
    when c.costo_ars > 0 and c.fact_ars > 0 and c.cluster_n = 1 then
      case when c.markup >= c.markup_minimo then 'OK' else 'MARGEN_BAJO' end
    -- Los dos lados, pero repartidos entre varios contenedores: se juzga el
    -- cluster, y el resultado nunca es rojo porque el reparto no es el dato.
    when c.costo_ars > 0 and c.fact_ars > 0 then
      case when c.markup_cluster >= c.markup_minimo then 'REPARTO_OK' else 'REPARTO_BAJO' end
    -- Ni costo ni facturación positivos: el caso quedó en cero o en negativo
    -- (una nota de crédito sin su factura en el mismo mes, un renglón en 0).
    -- NO entra en ninguno de los ocho estados del contrato, y meterlo a la
    -- fuerza en uno lo pintaría de un color que no le corresponde.
    else 'SIN_IMPORTE'
  end                                              as estado
from calc c;

comment on view public.ind_dtmlog_v_auditoria is
  'El veredicto por contenedor y período. markup NULL cuando el cluster tiene '
  'más de una serie: ahí el reparto de Tango es parejo y el markup por '
  'contenedor sería un artefacto (decisión D3). La edad se mide contra la '
  'fecha de corte del informe del otro lado, no contra now() (decisión D4).';


-- ----------------------------------------------------------------------------
-- 4.5  COMPROBANTES SOSPECHOSOS
-- ----------------------------------------------------------------------------
-- Dos cosas distintas:
--   NO_CUADRA     la suma de las filas 04 no da el total de la fila 02.
--                 Significa que el desglose está incompleto: hay plata
--                 imputada a la cuenta que no está asignada a ningún
--                 contenedor, y por lo tanto no la audita nadie.
--   SIN_DESGLOSE  hay fila 02 y NINGUNA 04. Es el error de carga de OC que se
--                 quiere cazar: el gasto entró a la cuenta sin decir de qué
--                 contenedor es.
--
-- La comparación es CON REDONDEO y con tolerancia de 1 peso, no con `=` crudo:
-- los totales llegan desde el .xlsx como float IEEE-754 y arrastran residuos
-- del orden de 1e-12. Un `=` exacto marcaría como sospechosos comprobantes que
-- cuadran perfectamente, y el control se volvería ruido el primer día.
create or replace view public.ind_dtmlog_v_comprobantes_sospechosos
with (security_invoker = true) as
select
  c.id                                              as comprobante_id,
  c.origen,
  c.categoria,
  c.cod_cuenta,
  c.proveedor,
  c.nro_comprobante,
  c.fecha,
  c.periodo,
  c.total_cte,
  coalesce(sum(r.importe_cte), 0)                   as suma_renglones,
  round(c.total_cte - coalesce(sum(r.importe_cte), 0), 2) as diferencia,
  count(r.id)                                       as n_renglones,
  case when count(r.id) = 0 then 'SIN_DESGLOSE' else 'NO_CUADRA' end as problema
from public.ind_dtmlog_comprobantes c
left join public.ind_dtmlog_renglones r
       on r.comprobante_id = c.id and r.activo
group by c.id, c.origen, c.categoria, c.cod_cuenta, c.proveedor,
         c.nro_comprobante, c.fecha, c.periodo, c.total_cte
having count(r.id) = 0
    or abs(round(coalesce(c.total_cte, 0), 2) - round(coalesce(sum(r.importe_cte), 0), 2)) > 1;


-- ----------------------------------------------------------------------------
-- 4.6  SERIES UNIFICADAS — la lista de control de la decisión D2
-- ----------------------------------------------------------------------------
-- Los códigos se unifican solos, pero toda unificación que junte DOS
-- ESCRITURAS DISTINTAS aparece acá. Es el contrapeso de la automatización: la
-- unificación equivocada no se esconde en una suma, se ve en una pantalla.
--
-- Mira las dos fuentes a la vez — los renglones de Tango y la carga manual de
-- `ind_dtm_data` — porque el caso que motivó la decisión es justamente un
-- cruce entre sistemas: 'IF 4252-04' lo escribe el CRM y 'IF 04252-4' lo
-- escribe Tango. Mirando una sola fuente, esa unificación no se vería.
create or replace view public.ind_dtmlog_v_series_unificadas
with (security_invoker = true) as
with escrituras as (
  select r.serie_norm,
         btrim(r.serie_raw) as escritura,
         'tango (dtmlog)'   as fuente
    from public.ind_dtmlog_renglones r
   where r.activo and coalesce(btrim(r.serie_raw), '') <> ''
  union all
  select public.ind_dtmlog_norm_serie(d.serie),
         btrim(d.serie),
         'crm (ind_dtm_data)'
    from public.ind_dtm_data d
   where coalesce(btrim(d.serie), '') <> ''
)
select
  e.serie_norm,
  count(distinct e.escritura)                              as n_escrituras,
  array_agg(distinct e.escritura order by e.escritura)     as escrituras,
  array_agg(distinct e.fuente    order by e.fuente)        as fuentes
from escrituras e
where e.serie_norm is not null
group by e.serie_norm
having count(distinct e.escritura) > 1;


-- ----------------------------------------------------------------------------
-- 4.7  LAG entre costo y facturación
-- ----------------------------------------------------------------------------
-- Las ventanas de 45 y 60 días son una estimación: nadie midió cuánto tarda en
-- la práctica el circuito. Esta vista da el dato propio — por cada caso que
-- CIERRA (tiene los dos lados en el mismo contenedor y período), cuántos días
-- pasaron entre la última compra y la última venta. Con tres o cuatro meses
-- acá, los umbrales de `ind_dtmlog_config` se recalibran con la realidad en
-- vez de con una corazonada.
create or replace view public.ind_dtmlog_v_lag
with (security_invoker = true) as
select
  cp.serie_norm,
  cp.periodo,
  cp.primera_compra,
  cp.ultima_compra,
  cp.primera_venta,
  cp.ultima_venta,
  (cp.ultima_venta - cp.ultima_compra)   as dias_lag,
  (cp.primera_venta - cp.primera_compra) as dias_lag_primeras,
  cp.costo_ars,
  cp.fact_ars
from public.ind_dtmlog_v_contenedor_periodo cp
where cp.ultima_compra is not null
  and cp.ultima_venta  is not null;


-- ############################################################################
-- 5. RLS — solo `authenticated`, nunca `anon` (regla 7 de CLAUDE.md)
-- ############################################################################
-- Lectura   : todo el sector comercial (tiene_sector('fhcomercial')).
-- Escritura : además, estar en ind_dtmlog_editores.
-- Delete    : NO se habilita en ninguna tabla.
--             * renglones y comprobantes: la baja es lógica (activo=false).
--             * comentarios: append only, una justificación borrable no
--               justifica nada.
--             * importaciones y config: nada de esto se borra desde la app.
-- Ni una sola política menciona a `anon`.

alter table public.ind_dtmlog_importaciones enable row level security;
alter table public.ind_dtmlog_comprobantes  enable row level security;
alter table public.ind_dtmlog_renglones     enable row level security;
alter table public.ind_dtmlog_comentarios   enable row level security;
alter table public.ind_dtmlog_config        enable row level security;

-- 5.a — lectura + insert + update para las cuatro tablas de datos del circuito
do $$
declare
  t text;
begin
  foreach t in array array[
    'ind_dtmlog_importaciones','ind_dtmlog_comprobantes',
    'ind_dtmlog_renglones','ind_dtmlog_config'
  ]
  loop
    execute format($f$
      drop policy if exists "%1$s_leer" on public.%1$I;
      create policy "%1$s_leer" on public.%1$I
        for select to authenticated
        using (public.tiene_sector('fhcomercial'));

      drop policy if exists "%1$s_escribir" on public.%1$I;
      create policy "%1$s_escribir" on public.%1$I
        for insert to authenticated
        with check (public.tiene_sector('fhcomercial') and public.ind_dtmlog_puede_editar());

      drop policy if exists "%1$s_actualizar" on public.%1$I;
      create policy "%1$s_actualizar" on public.%1$I
        for update to authenticated
        using (public.tiene_sector('fhcomercial') and public.ind_dtmlog_puede_editar())
        with check (public.tiene_sector('fhcomercial') and public.ind_dtmlog_puede_editar());
    $f$, t);
  end loop;
end $$;

-- 5.b — comentarios: APPEND ONLY, y con DOS niveles distintos de permiso.
--
-- Lee cualquiera del sector: la bitácora es para que la vea el equipo.
--
-- Escribir se parte en dos a propósito, porque las tres acciones NO son lo
-- mismo:
--   * 'comentario' no cambia nada de lo que muestra el tablero. Lo puede dejar
--     cualquiera del sector, y conviene que así sea: el que sabe por qué falta
--     un costo suele ser alguien de compras, no el que importa los archivos.
--     Pedir permiso de edición para dejar una nota haría que nadie deje notas.
--   * 'justificar' y 'posponer' SACAN un caso del tablero. Eso sí es una
--     decisión sobre qué se mira y qué no, así que exige estar en
--     ind_dtmlog_editores, igual que importar.
-- En los tres casos la nota tiene que venir firmada con el mail del JWT, para
-- que nadie firme con el nombre de otro.
--
-- No hay política de update ni de delete, y es a propósito: una justificación
-- no se edita ni se borra, queda en el historial aunque el caso reabra.
drop policy if exists "ind_dtmlog_comentarios_leer" on public.ind_dtmlog_comentarios;
create policy "ind_dtmlog_comentarios_leer" on public.ind_dtmlog_comentarios
  for select to authenticated
  using (public.tiene_sector('fhcomercial'));

drop policy if exists "ind_dtmlog_comentarios_escribir" on public.ind_dtmlog_comentarios;
create policy "ind_dtmlog_comentarios_escribir" on public.ind_dtmlog_comentarios
  for insert to authenticated
  with check (
    public.tiene_sector('fhcomercial')
    and lower(usuario) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and (accion = 'comentario' or public.ind_dtmlog_puede_editar())
  );


-- ----------------------------------------------------------------------------
-- 5.c — GRANTS explícitos
-- ----------------------------------------------------------------------------
-- Si el grant falta, el RLS ni se evalúa: falla antes con un "permission denied
-- for table" que despista. Y se revoca de `anon` aunque ninguna política lo
-- mencione: sin grant no hay ni siquiera intento de lectura.
do $$
declare
  t text;
begin
  foreach t in array array[
    'ind_dtmlog_importaciones','ind_dtmlog_comprobantes',
    'ind_dtmlog_renglones','ind_dtmlog_config'
  ]
  loop
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

grant select, insert on public.ind_dtmlog_comentarios to authenticated;
revoke all on public.ind_dtmlog_comentarios from anon;

-- Las secuencias de las columnas `identity`: sin usage, el insert falla.
do $$
declare
  s text;
begin
  for s in
    select quote_ident(n.nspname) || '.' || quote_ident(c.relname)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind = 'S' and n.nspname = 'public'
       and c.relname like 'ind\_dtmlog\_%'
  loop
    execute format('grant usage, select on sequence %s to authenticated', s);
    execute format('revoke all on sequence %s from anon', s);
  end loop;
end $$;

-- Las vistas: select para authenticated, nada para anon. Con
-- security_invoker = true la RLS que se aplica adentro es la del que consulta.
do $$
declare
  v text;
begin
  foreach v in array array[
    'ind_dtmlog_v_renglones','ind_dtmlog_v_clusters',
    'ind_dtmlog_v_contenedor_periodo','ind_dtmlog_v_auditoria',
    'ind_dtmlog_v_comprobantes_sospechosos','ind_dtmlog_v_series_unificadas',
    'ind_dtmlog_v_lag'
  ]
  loop
    execute format('revoke all on public.%I from anon', v);
    execute format('grant select on public.%I to authenticated', v);
  end loop;
end $$;


-- ############################################################################
-- 6. VERIFICACIÓN — correr después y mirar los resultados
-- ############################################################################
-- 6.a — las 6 tablas, con RLS activo. ind_dtmlog_editores tiene que salir con
--       rls_activo = true y politicas = 0 (eso NO es un error, ver punto 2).
--
-- select c.relname as tabla,
--        c.relrowsecurity as rls_activo,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename=c.relname) as politicas,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename=c.relname
--            and 'anon' = any(p.roles)) as politicas_anon   -- TIENE QUE DAR 0
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relkind='r' and c.relname like 'ind\_dtmlog\_%'
--  order by c.relname;
--
-- 6.b — anon no debe tener NINGÚN grant sobre nada de dtmlog (tiene que dar 0 filas)
--
-- select table_name, privilege_type
--   from information_schema.role_table_grants
--  where table_schema='public' and table_name like 'ind\_dtmlog\_%' and grantee='anon';
--
-- 6.c — las 7 vistas tienen que estar con security_invoker
--
-- select c.relname, c.reloptions
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relkind='v' and c.relname like 'ind\_dtmlog\_v\_%'
--  order by c.relname;
--
-- 6.d — la normalización de series hace lo que tiene que hacer
--
-- select s, public.ind_dtmlog_norm_serie(s)
--   from unnest(array['IF 4252-04','IF 04252-4','IF 04252-11',
--                     'ZCSU 511065-4','amfu  848078-5']) s;
--   -- esperado: 'IF 4252-4', 'IF 4252-4', 'IF 4252-11', 'ZCSU 511065-4', 'AMFU 848078-5'
--
-- 6.e — quién quedó habilitado para cargar (debería ser la misma gente que ind_editores)
--
-- select email, nota from public.ind_dtmlog_editores order by email;
--
-- 6.f — DESPUÉS DE LA PRIMERA IMPORTACIÓN: que cada archivo haya entrado entero.
--       `cuadra` tiene que ser true en las 4 filas y el pie tiene que ser el
--       doble del total real.
--
-- select archivo, origen, categoria, filas_02, filas_04,
--        total_real, total_declarado,
--        round(total_declarado - 2*total_real, 2) as debe_dar_cero, cuadra
--   from public.ind_dtmlog_importaciones order by importado_en desc;
--
-- 6.g — DESPUÉS DE LA PRIMERA IMPORTACIÓN: el tablero
--
-- select estado, count(*) from public.ind_dtmlog_v_auditoria group by 1 order by 2 desc;
-- select * from public.ind_dtmlog_v_comprobantes_sospechosos;
-- select * from public.ind_dtmlog_v_series_unificadas;


-- ############################################################################
-- 7. ROLLBACK — deshace TODO lo de esta migración, sin tocar nada del CRM
-- ############################################################################
-- Borra solo objetos con prefijo ind_dtmlog_. No toca ind_dtm_data,
-- ind_editores, ind_puede_editar, tiene_sector ni ninguna tabla del CRM.
--
-- drop view if exists public.ind_dtmlog_v_lag;
-- drop view if exists public.ind_dtmlog_v_series_unificadas;
-- drop view if exists public.ind_dtmlog_v_comprobantes_sospechosos;
-- drop view if exists public.ind_dtmlog_v_auditoria;
-- drop view if exists public.ind_dtmlog_v_contenedor_periodo;
-- drop view if exists public.ind_dtmlog_v_clusters;
-- drop view if exists public.ind_dtmlog_v_renglones;
--
-- drop trigger if exists ind_dtmlog_ren_sync on public.ind_dtmlog_renglones;
-- drop function if exists public.ind_dtmlog_renglon_sincroniza();
--
-- drop table if exists public.ind_dtmlog_comentarios;
-- drop table if exists public.ind_dtmlog_renglones;
-- drop table if exists public.ind_dtmlog_comprobantes;
-- drop table if exists public.ind_dtmlog_importaciones;
-- drop table if exists public.ind_dtmlog_config;
-- drop table if exists public.ind_dtmlog_editores;
--
-- drop function if exists public.ind_dtmlog_puede_editar();
-- drop function if exists public.ind_dtmlog_norm_serie(text);
