# 4housing-comercial — Contexto del proyecto

Este archivo es la memoria persistente del proyecto para Claude Code. Cualquier
instancia (la de Pablo o la de Ignacio) debe leer esto antes de tocar código.

## Qué es esto

CRM comercial interno de **4housing (4COMMERCE SRL)**, empresa de construcción
modular en Buenos Aires, Argentina. Cubre prospección, oportunidades, cotizaciones,
cobranzas, facturación (integración con ERP) y pipeline, para dos unidades de
negocio: **Rental** (alquiler de módulos) y **Ventas** (venta única).

Reemplaza procesos manuales y se conecta con el ERP **Tango Delta 5 (Axoft)**.

## Personas y roles

- **Pablo** — co-dueño de 4housing, builder y mantenedor principal de la app.
  Decide sobre cambios estructurales. Prefiere entender el "por qué" antes de
  que se implemente algo grande. Comunica en español rioplatense (voseo), directo
  y sin relleno.
- **Ignacio Sánchez Moser** — también va a operar Claude Code sobre este mismo repo.
- **Equipo comercial:** Ignacio Sánchez Moser, Victoria López Aybar, Pablo Spinetto,
  Leandro Seoane, Héctor Bermúdez.
- **Equipo de cobranzas (Gerencia de Administración y Finanzas):** Santiago Cittar,
  Alexis Carranza, Micaela Seoane.

## Stack

- **Frontend:** un solo archivo `index.html` (vanilla JS/HTML/CSS, sin frameworks).
- **Hosting:** GitHub Pages, org `4housing`, repo `4housing-comercial`.
  URL pública: https://4housing.github.io/4housing-comercial/
  (El repo se mudó de la org `labo-comercial`; el dominio viejo puede servir una
  versión desactualizada. Si un cambio "no aparece", chequear la URL además de
  la caché del navegador.)
- **Backend:** Supabase (REST API + Edge Functions + RLS).
  Project ID: `wcpkpwxhqdcdljfwzcmy`
- **Auth — OJO, hay DOS caminos distintos y conviene no confundirlos:**
  1. **Login de la app: Supabase Auth con proveedor Azure**
     (`sbClient.auth.signInWithOAuth({provider:'azure'})`, scopes
     `openid profile email`). De acá sale `AUTH_USER`, y **cada llamada REST a
     Supabase viaja con el JWT del usuario**, así que las políticas RLS
     distinguen usuarios (ver `public.tiene_sector('fhcomercial')`, que existe
     en la base pero NO está en el repo).
  2. **MSAL v3.7.0 embebido (`msal-browser.min.js`): solo para Microsoft
     Graph**, con una app registrada aparte (`f47da2c5-7922-4e2f-8648-51b8486552fb`).
     Lo usan SharePoint (`Files.ReadWrite.All`, `Sites.ReadWrite.All`) y el
     calendario de la Agenda (`Calendars.Read`). El token se pide con
     `_spToken(interactivo, scopes)`; **solo se cachea en `_spTok` cuando son los
     scopes de SharePoint** — meter ahí un token de otro scope rompe SharePoint.
  Client ID del login: `66a475e3-745f-4931-8085-ee71a0b6d6fe`
  Tenant ID: `c408b6d8-ae0b-4d30-9056-da52e18116c4`
- **ERP:** Tango Delta 5 (Axoft), servidor local accesible desde internet.
  API usa headers `ApiAuthorization` (token) y `Company: 3`.
- **Notificaciones:** Power Automate (webhook Teams firmado) + Supabase Edge
  Function (Microsoft Graph `Mail.Send`).
- **Mail pipeline:** Power Automate + Supabase Edge Function + Claude API para
  clasificar mails entrantes a `info@4housing.com.ar`.
- **Diseño:** paleta oliva/crema (`#9db98b`, `#5f7a4e`, `#37432c`, `#f4f2ea`),
  tipografías Archivo/Quicksand, sello ISO/TÜV NORD.

## Reglas de trabajo — NO NEGOCIABLES

> **Criterio, no candado.** Estas reglas son el default. Se pueden saltar si el dueño
> de la decisión (Pablo) lo resuelve explícitamente — pero Claude debe **advertir ANTES**,
> con claridad, que la acción incumple tal regla y qué riesgo tiene, y esperar el OK.
> Claude nunca rompe una regla por su cuenta ni en silencio.

1. **SQL nunca se ejecuta automáticamente.** Toda migración se entrega como
   archivo `.sql` separado para que Pablo lo corra manualmente en el SQL Editor
   de Supabase. Claude Code no tiene ni debe usar credenciales de escritura
   directa a la base de producción salvo que Pablo lo autorice explícitamente
   para una tarea puntual.
2. **Orden de deploy:** primero el SQL (si agrega columnas/tablas), después el
   deploy del HTML. Nunca al revés.
3. **El token de la API de Tango NUNCA va en `index.html`** (es público en
   GitHub Pages). Todo llamado a Tango pasa por Supabase Edge Functions.
4. **Cambios incrementales y aditivos:** no reescribir funciones existentes
   salvo necesidad real. Cada feature se entrega como pieza separada y testeable.
5. **Todo cambio en JS se valida con `node --check`** antes de darlo por
   terminado.
6. **Decisiones estructurales se cierran antes de escribir código.** Si hay
   una decisión de diseño/arquitectura pendiente, se discute y se cierra
   primero con Pablo (y con Ignacio si corresponde).
7. **RLS por defecto en `authenticated`, nunca en `anon`.** Crear políticas
   permisivas para `anon` "temporalmente" es el error recurrente que ya causó
   trabajo de hardening. Toda tabla nueva arranca con políticas solo para
   `authenticated`.
8. **Nada de credenciales sensibles hardcodeadas más allá de lo ya aceptado**
   (la anon key de Supabase es pública por diseño; el token de Tango NO).
9. **No romper nada de lo que ya funciona. Es la regla que manda sobre todas
   las demás.** Llegar al estado actual costó mucho trabajo; una feature nueva
   nunca justifica degradar una que ya anda. En la práctica:
   - **Preferir agregar antes que modificar.** Una vista nueva, una función
     nueva, una tabla nueva son de bajo riesgo. Tocar una función que ya usa
     otra parte de la app es de alto riesgo, aunque el cambio parezca trivial.
   - **Si hay que tocar código compartido, buscar primero TODOS los usos**
     (`grep`) y entender qué depende de él. Ejemplo real: `_spToken()` cacheaba
     el token en la global `_spTok`; agregarle el calendario sin cuidado habría
     hecho fallar con 403 las carpetas de SharePoint de Ventas, que ya andaban.
   - **Probar lo que se tocó, no solo lo que se agregó.** `node --check` valida
     sintaxis, no comportamiento. Si el cambio afecta algo existente, hay que
     verificar que eso existente siga funcionando.
   - **Un PR por feature, chico y reversible.** Si algo sale mal en producción,
     tiene que poder revertirse solo, sin arrastrar lo demás.
   - **Ante la duda, preguntar antes de tocar.** Es preferible una consulta de
     más que una regresión.

## Flujo de trabajo en git (dos personas, mismo repo)

- Evitar que ambos commiteen directo a `main` en simultáneo sobre `index.html`
  (archivo único y grande → conflictos difíciles de mergear).
- Usar ramas por feature + Pull Request, o coordinarse antes de tocar el archivo
  si se prefiere simplicidad.
- Antes de empezar una sesión de Claude Code, hacer `git pull` para no pisar
  cambios del otro.
- Commits chicos y descriptivos, en español, describiendo qué feature/fix es.

## Patrones técnicos establecidos

- **Formato de referencia unificado:** `OE-{R|V}-{número}-{versión}` con
  contadores independientes por unidad de negocio vía RPC `next_seq_un(p_unidad)`.
- **Paginación:** usar siempre `SB._fetchAll()` para cualquier query que pueda
  superar 1000 filas (cap por defecto de PostgREST).
- **Tabla `contador`:** tiene constraint `contador_unica_fila` (una sola fila).
  Los contadores son columnas de esa fila única, actualizados con
  `FOR UPDATE` row locking dentro de las RPCs.
- **CSS de tablas:** usar `vertical-align:top` + `word-break:break-word` +
  `td.nowrap` selectivo para celdas de contenido corto. NO usar
  `white-space:nowrap` global (rompe tablas anchas) ni `table-layout:fixed`
  con ellipsis (corta contenido).
- **Tablas — estándar (pedido de Mica):** toda tabla de datos (`table.grid`) lleva:
  (1) **orden por columna** — `sortTh(label,col,sortVar,renderCall,cls)` + `toggleSort`
  + un `window.<algoSort>={col,dir}`; (2) **columnas redimensionables** — automático
  vía `habilitarResizeColumnas` (MutationObserver sobre `#content`, ancho guardado en
  localStorage por firma `_firmaTabla`); (3) **filtros tipo Excel por columna** —
  `xlfRegister(ns,{rows,val,dateVal,onChange})` + `sortFilterTh(label,col,sortVar,
  renderCall,ns,fCol,cls)` (el `fCol` `'__fecha__'` da rango de fechas), se filtra la
  lista con `xlfPass(ns,row[,valFn])` antes de renderizar, y `xlfClearBtn(ns)` limpia;
  (4) **botón "Auto-ajustar columnas"** — `tblAutofit('#idTabla')`. El popup del filtro
  se monta en `<body>` (no lo recorta `th{overflow:hidden}`). Aplicado en Ventas,
  Rental y Panel (ver commits 7f4696e/9311d0a). Para tablas que mezclan filas de
  oportunidad y de cotización, pasar un `valFn` a `xlfPass` para las OP (solo las
  columnas que comparten).
- **Power Automate:** los triggers HTTP del tenant requieren OAuth; se usa la
  URL firmada del Teams Workflow (`COBRANZA_WEBHOOK_URL`), que acepta POST
  anónimo sin problemas de CORS.

## Estado actual (features completadas)

- **Indicadores** (menú Rental): la app de rental-dashboard, que vivía en otro
  repo y se deployaba a Vercel, ahora es una vista nativa del CRM. Antes el menú
  tenía un `<a>` que abría `rental-dashboard-xi.vercel.app` en otra pestaña, con
  login propio (email+contraseña) contra **otro proyecto Supabase**
  (`zziktktjsnkmtaqwghha`). Ahora entra con la sesión de Azure del CRM y lee del
  Supabase del CRM.
  - **Las 11 tablas llevan prefijo `ind_`** (`ind_rental_data`, `ind_stock_items`,
    `ind_stock_movimientos`, `ind_stock_snapshots`, `ind_stock_cierres`,
    `ind_ipc_data`, `ind_dtm_data`, `ind_facturacion_data`, `ind_clientes_data`,
    `ind_chat_messages`, `ind_notifications`). El prefijo es para no confundir
    `ind_clientes_data` (resumen mensual de rental) con `clientes` (los clientes
    comerciales): son cosas distintas.
  - **Todo el JS corre dentro de un IIFE** y lo único que expone es
    `window.IND`, con los 25 handlers que el HTML necesita en sus `onclick`.
    **Esto NO es cosmético:** la app define su propio `esc()` que escapa solo
    comillas dobles, y el CRM tiene un `esc()` que escapa `& < > "` y se usa en
    284 lugares. Pegado en el mismo scope, ganaba la última declaración y el CRM
    quedaba con **XSS almacenado en esos 284 puntos**. Lo mismo con `doLogin`,
    que habría reemplazado el login de Microsoft. **Nunca sacar el IIFE.**
  - **Todo el CSS está scopeado bajo `#view-indicadores`** (7 clases chocaban:
    `.badge .field .kpi-grid .kpi-label .kpi-sub .kpi-value .topbar`).
  - **Bloque "Blindaje" al final de ese CSS:** el scope protege al CRM de
    indicadores, pero no al revés. Reglas globales del CRM como `.topbar{}` o
    `.badge::before{}` también matchean adentro del contenedor, y se filtraban
    en las propiedades que la hoja de indicadores no declara (el `.badge::before`
    del CRM le metía un punto decorativo a todos los badges). El blindaje las
    devuelve al default con `revert`. **Si se agrega una clase nueva al CRM que
    indicadores también use, hay que regenerarlo.**
  - La vista tiene **contenedor propio, hermano de `#content`**, y `go()` alterna
    cuál se ve. No se re-renderiza: así conserva gráficos y datos ya cargados al
    cambiar de vista y volver.
  - **Chart.js 4.4.1 se carga diferido**, recién al entrar a la vista por primera
    vez, para no cobrarle 200 KB a quien nunca la abre.
  - **Permisos: Indicadores NO usa los del CRM, y es a propósito.**
    - *Ver el ítem del menú:* `comPuedeVer()` devuelve `true` para
      `'indicadores'` con un early-return. Es una sección que se agregó
      **después** de que se configuraran los permisos del equipo, así que no
      figura en el array `ver` de nadie y el menú la habría ocultado para
      todos. Exceptuarla evita reescribir los permisos ya cargados de cada
      persona. No cambia nada para las secciones que ya existían, y leer no es
      un riesgo porque el RLS de las tablas `ind_` ya deja leer a todo el
      sector.
    - *Cargar datos (el tab "Datos", que borra tablas enteras):* lo decide la
      tabla **`ind_editores`** (mail + nota), no `perfiles_sector`. La primera
      versión leía `perfiles_sector.permisos`, pero eso obligaba a **escribir**
      en una tabla del CRM para dar de alta a alguien. Se descartó: los
      permisos del CRM no se tocan. Alta y baja son un insert/delete en
      `ind_editores`.
    - `ind_editores` tiene **RLS activo y cero políticas**, y los grants
      revocados a `anon` y `authenticated`: nadie la lee ni la escribe desde la
      app. `ind_puede_editar()` la lee igual porque es `security definer`. Sin
      esto, cualquiera se daría permiso a sí mismo para borrar el histórico.
    - La interfaz pregunta por `sb.rpc('ind_puede_editar')`, **la misma función
      que usa el RLS**, así que el botón y la base nunca pueden discrepar. Si
      el RPC falla, el tab queda oculto (falla cerrado).
    - Dirección **no** tiene permiso automático de carga: si se quiere, se
      agrega el mail a `ind_editores`.
  - Se perdió el login biométrico propio (WebAuthn): ahora lo maneja Microsoft.
  - **Datos migrados el 3/11/2026**: 2.733 filas en 9 tablas, verificadas una
    por una contra el origen. `ind_stock_cierres` e `ind_stock_snapshots`
    quedaron vacías porque nunca se había podido cerrar un mes: `cerrarMes()`
    guarda primero la foto en snapshots y recién después escribe el cierre, y
    esa tabla se había creado por error en OTRO proyecto Supabase (el de una
    app de plantas), así que la función siempre cortó en el primer paso. La
    migración lo deja arreglado y los cierres empiezan a funcionar.
  - **LA CARGA DE DATOS VA SOLO POR EL CRM.** El deploy de Vercel y el proyecto
    `zziktktjsnkmtaqwghha` quedan como respaldo **al menos hasta diciembre de
    2026** (decisión de Ignacio: un mes de convivencia antes de dar de baja
    nada). Pero son una **foto congelada al 3/11/2026**, no un espejo: si
    alguien sube el Excel por la app de Vercel, esos datos entran en el proyecto
    viejo, el CRM no se entera, y los indicadores del CRM parecen
    "desactualizados" sin ninguna señal de error. Es la confusión más probable
    de este período y no deja rastro en ningún log.
  - Un proyecto de Supabase vivo **no es un backup**: depende de la cuenta y los
    proyectos gratuitos se pausan por inactividad (de ahí la tabla `heartbeat`
    que tiene el proyecto viejo). El respaldo de verdad es el export en CSV.
- **Agenda** (menú Comercial): vista de lista y calendario mensual que unifica
  vencimientos. Junta cuatro fuentes: tareas propias (tabla `agenda_tareas`,
  se cargan a mano desde el botón o clickeando un día), próximo paso y fecha
  límite de oportunidades, validez de ofertas enviadas, y las reuniones de
  Outlook/Teams vía Graph (opt-in, con botón "Unirse"). Filtro "Mis pendientes"
  y cartel de recordatorio al abrir (1 vez por día, solo lo vencido/de hoy).
  - El usuario se identifica comparando el nombre de Azure AD contra
    `COMERCIALES` **ignorando tildes** (Azure devuelve "Ignacio Sanchez Moser",
    la lista tiene "Ignacio Sánchez Moser"), con respaldo por el usuario del
    mail. Si no matchea, no adivina: muestra todo el equipo y avisa.
  - "Mis pendientes" es comodidad visual, **no** barrera de seguridad.
- **Liquidación Repcont** (Indicadores → Stock, con **BA Reefers** elegido):
  genera el Excel mensual del técnico de los reefers, que cobra por día y por
  equipo. Reemplaza una planilla que se llevaba a mano desde enero de 2024.
  - **La regla de facturación**, verificada contra las 33 hojas del histórico y
    contra los datos de producción de septiembre 2026: factura la serie cuya
    `tipologia` contiene **`REEFER`** y que estuvo **alquilada** en el mes.
    `REEF-PAÑOL` queda afuera porque la cadena no contiene `REEFER` (son
    contenedores sin equipo de frío, usados como pañol: no requieren servicio
    técnico). De los 12 `REEF-PAÑOL`, 11 no figuran siquiera en la planilla del
    técnico y el que figura lleva 15 meses con cero días. Cero excepciones.
  - **NO se filtra por `modelo_negocio`**, y es importante: ese campo sale del
    prefijo del código de artículo de Tango (`VBARE`/`VBAMO`/`VNQMO`), o sea
    que clasifica **qué se le factura al cliente**, no qué caja es. Hay reefers
    reales bajo `BA MODULOS`. Filtrar por ahí dejaría equipos afuera.
  - **Los días se calculan por unión de intervalos, nunca por suma.** Si una
    serie tuvo varios tramos en el mes se fusionan los que se solapan y recién
    ahí se suman los largos. Sumar sin fusionar es lo que hizo que
    `ZCSU 511065-4`, duplicada en el Excel histórico desde julio 2025,
    acumulara 455 días de más (1.820 USD). Ambos extremos se cobran
    (`hasta - desde + 1`), que es el criterio del histórico.
  - **La tarifa no es constante**: 3,5 USD/día en todo 2024, 4 desde enero de
    2025. Se resuelve por mes, así regenerar un mes viejo da lo que se pagó
    entonces. El campo es editable.
  - **El tipo de cambio es el del día en que se baja el informe**, no el del
    cierre del mes: es el criterio del técnico, que factura con el TC del día
    en que recibe la liquidación. Se trae de `dolarapi` con respaldo en
    `bluelytics`, **se muestra y se puede editar**, y si ninguna fuente
    responde queda vacío y se escribe a mano. **Nunca hay un default
    silencioso**: el CRM ya tiene un `tcDe()` que devuelve `1` cuando no
    encuentra la moneda y un `1470` hardcodeado en la carga; ninguno de los dos
    se usa acá, y reusarlos daría un total mil veces menor sin tirar un error.
  - Como el TC depende del día de descarga, el mismo mes daría distinto cada
    vez. Por eso la tabla **`ind_liquidacion_repcont`** guarda el TC usado con
    su **fecha y su fuente**, más el detalle por serie. El Excel histórico no
    guardaba nada de eso: el TC era un número pelado tipeado en una celda.
  - **Los 33 meses ya liquidados se cargaron de entrada**
    (`sql/2026-11-04-repcont-historial.sql`): sin eso la hoja HISTORIAL del
    primer archivo generado salía con una sola fila. Registra **lo que se
    pagó**, no lo que correspondía — incluidos los meses con equipos ya
    vendidos, la serie duplicada y el total mal sumado de julio 2025. El
    historial es el registro de lo que pasó; corregirlo ahí taparía justo lo
    que hay que reclamar. `tc_fecha` queda en NULL a propósito: la planilla
    nunca anotó a qué día correspondía la cotización. Va con
    `on conflict (mes_anio) do nothing`, así nunca pisa una liquidación hecha
    desde el botón, y el rollback borra solo lo cargado
    (`generado_por = 'carga histórica'`). Total del período:
    **USD 227.997 / $ 280.393.660** en 33 meses.
  - El archivo lleva dos hojas: la del mes (misma estructura que el histórico,
    con **CLIENTE en G y NOTAS en H** — a la derecha de F, para no tocar las
    fórmulas del pie, que referencian E y F) y **HISTORIAL**, que se arma desde
    la tabla.
  - **La fila del pie se calcula**, no se clava: en el histórico se movió entre
    la 79 y la 87 según el mes, y en **julio 2025 quedó mal escrita**
    (`=SUM(F11:F79)` en vez de `=SUM(F4:F79)`), lo que se comió las tres filas
    de 20 pies: **93 días = 372 USD que no se le pagaron al técnico**.
  - **NUNCA pasar un objeto `Date` por SheetJS.** Al escribir sin
    `{cellDates:true}`, `datenum()` interpreta la fecha en hora **local del
    navegador**, así que en Buenos Aires (UTC-3) un `Date.UTC(2026,8,1)` se
    guarda como **31/08/2026 20:59:12**: la hoja entera sale corrida un día, se
    mete en el mes anterior y contradice la columna DIAS, sin ningún error.
    `new Date(anio, mes-1, d)` tampoco sirve: `datenum` resta la diferencia de
    husos contra 1899-12-30, y para Buenos Aires ese offset es **256 min**
    (CMT −4:16:48) contra 180 de hoy, o sea 23:59:12 del día anterior. Se
    escribe el **serial de Excel a mano**: `Date.UTC(a,m,d)/86400000 + 25569`.
    Las celdas quedan `t==='n'`, no `t==='d'`, y el formato se aplica como tal.
    **Un entorno de prueba en UTC no detecta esto**: hay que forzar el huso
    (en Playwright, `timezoneId`).
  - **El mes en curso no se puede elegir**, y hay que mantenerlo así: `allData`
    lo incluye (`mesesDeStock`/`recomponerDatos` sintetizan las filas del mes
    abierto para el "● En vivo"), y `rcTramosDe` sin movimientos devuelve el
    **mes completo**. Elegirlo liquidaría días que todavía no pasaron, `parcial`
    daría `false` porque `dias == último`, y el upsert por `mes_anio` dejaría
    asentada esa fila hasta que alguien regenere el mes de verdad.
  - **`ind_stock_movimientos` se carga sin paginar** (`index.html:8374`), y
    PostgREST corta en 1000 filas. Hoy son ~531, pero la tabla solo crece: si
    llega al tope, los meses con alta o baja se liquidarían como mes completo
    en silencio. El modal avisa cuando `STOCK_MOVS.length >= 1000`. **El
    arreglo de fondo es migrar esa carga a `SB._fetchAll()`**, que es el patrón
    del proyecto, pero toca código compartido y no se hizo con esta feature.
  - Si un reefer facturaba el mes anterior y este mes **no tiene ninguna fila**
    en `ind_rental_data`, se marca como **"Falta el dato"**, distinto de una
    baja: una baja es un hecho comercial, esto es un agujero en los datos. Es
    exactamente como el Excel histórico terminó con 5 series que cobran y no
    existen en la base.
  - El modal muestra un panel de **novedades** (altas, bajas, meses parciales,
    series con varios tramos, pañol excluidos). No corrige nada solo: lo pone
    adelante para que se revise antes de emitir.
  - **El bloque define su propio `rcEsc()` y eso no es cosmético:** adentro del
    IIFE de Indicadores, `esc()` es la versión que escapa **solo comillas
    dobles**; la buena del CRM queda tapada. Los nombres de cliente vienen del
    Excel de Tango, así que no son de confianza. Usar `esc()` ahí sería XSS.
  - **Única función existente que se tocó:** `setModelo()`, que suma una llamada
    a `rcToggle()` dentro de un `try/catch` para mostrar u ocultar el botón.
    El resto es todo agregado: 737 líneas insertadas, 0 borradas.
- **Control DTM y Logística** (menú Rental, debajo de Indicadores): audita, por
  contenedor y por mes, que cada servicio de DTM o de Logística contratado a un
  proveedor se le haya facturado al cliente, y que haya dado al menos 20 % de
  markup **sobre el costo**. Reemplaza la auditoría manual que se hacía
  cruzando a mano los informes de Tango en un Excel.
  - **El total que trae el pie de los informes de Tango vale el DOBLE.** Cada
    comprobante aparece dos veces: como fila `02 - EERR` (el total de la cuenta
    de resultados) y abierto en filas `04 - CONTENEDOR/MODULO`. La fórmula del
    pie es un `=SUM()` plano que no filtra por nivel, así que suma las dos.
    Verificado al centavo en los cuatro archivos y en las dos monedas
    (Ventas DTM: pie −102.670.612, real −51.335.306). **El importador NUNCA
    divide el pie por dos: suma los `02`.** El factor 2 es una consecuencia de
    que el desglose esté completo, no una constante: si un día un comprobante
    viene sin sus `04`, el pie deja de valer el doble, y eso es justamente la
    señal de que falta algo. Se usa como checksum.
  - **La clave natural necesita la CUENTA.** `A0001000000384` aparece dos veces
    con el mismo auxiliar `M00096`: cuenta 41000005 por −2.165.000 (Logística) y
    41000004 por −650.000 (DTM). Es la factura que vende las dos cosas juntas al
    mismo contenedor. Con clave `(comprobante, auxiliar)` se pisa y se pierden
    4.330.000. Las claves son `(origen, proveedor_k, nro_comprobante,
    cod_cuenta)` y `(comprobante_id, auxiliar, leyenda_k)`; `proveedor_k` y
    `leyenda_k` son columnas **generadas** (`coalesce(x,'')`) y no expresiones,
    porque PostgREST necesita nombres de columna reales para el `on_conflict`
    del upsert.
  - **Se clasifica FILA POR FILA por `Cód. cuenta`**, nunca por el nombre del
    archivo: 55000009 compras LOG, 52000013 compras DTM, 41000005 ventas LOG,
    41000004 ventas DTM. Por eso hay un solo botón de importar y no cuatro
    ranuras: "subí el archivo equivocado" no existe por construcción. Una cuenta
    desconocida **no se descarta en silencio**, entra en los avisos.
  - **Las columnas se mapean por NOMBRE, nunca por posición.** El orden ya
    difiere entre compras y ventas, y hasta cambia el nombre de la columna de
    fecha (`Fecha contable` contra `Fecha de emisión`).
  - **`cstNum()` (`index.html:5700`) NO se puede reusar:** lee `'1.380.000,00'`
    como **1,38**, porque borra la coma decimal y deja los puntos de miles. No
    tira excepción. El bloque define su propio `dtmNum()`, que devuelve **NaN**
    para lo que no entiende, nunca 0: un cero silencioso en una columna de costo
    hace que el control diga que todo da ganancia.
  - **Las fechas no se leen con `v instanceof Date` + `toISOString()`.** Es el
    mismo bug de huso que ya está documentado para la escritura, pero al leer:
    con `cellDates:true` y TZ de Buenos Aires el 09/10/2026 vuelve como
    `2026-10-09T03:00:48Z` (el offset CMT −4:16:48) y al **este** de Greenwich
    `slice(0,10)` da el día anterior. Se lee con `XLSX.SSF.parse_date_code`.
    Comprobado: reintroducir el bug a propósito hace fallar la suite en Auckland
    y en Kolkata, **y no en UTC ni en Buenos Aires** — o sea que una prueba que
    corra solo en el contenedor lo deja pasar.
  - **El bloque vive FUERA del IIFE de Indicadores, en su propio `<script>`.**
    Adentro, `esc()` es la versión que escapa solo comillas dobles; los nombres
    de proveedor vienen del Excel de Tango, así que sería XSS almacenado. Y hay
    una razón más: el `MutationObserver` de `habilitarResizeColumnas` observa
    `#content` y nada más, así que una vista en contenedor propio se quedaría
    sin columnas redimensionables (el estándar de tablas las exige).
  - **Escribe con `sbClient.from()`, no con `sbFetch`.** `sbFetch` tiene el
    guard de edición por sección (`index.html:1282`) que rebota los métodos
    distintos de GET si la vista no está en el array `editar` del usuario. Esta
    sección no se gobierna por los permisos del CRM sino por
    **`ind_dtmlog_editores`**, mismo patrón que `ind_editores`. Por eso también
    está en `SECCIONES_REPORTE_COM` (para que no salga el cartel amarillo de
    solo lectura) y en el early-return de `comPuedeVer()`.
  - **El markup por contenedor es un ARTEFACTO cuando el comprobante toca
    varios.** El comprobante de venta `A0000500007807` (9.180.000) Tango lo abre
    en **cuatro filas idénticas de 2.295.000**; la auditoría manual del mismo
    servicio reparte 2.800.000 / 1.690.000 / 1.690.000 / 3.000.000. El veredicto
    de markup se da vuelta en 2 de los 4. Por eso el markup se calcula al nivel
    del **cluster** (la componente conexa del grafo contenedor–comprobante
    dentro del período, con una CTE recursiva) y el por-contenedor se deja en
    NULL. Un cluster nunca sale en rojo: sale en ámbar.
  - **EL PUNTO MÁS IMPORTANTE, y el que puede cambiar la feature entera: el
    export de compras de Tango trae el 26,7 % del costo.** Octubre 2026 ya está
    auditado a mano en `ind_dtm_data`: costo 38.206.900,21, facturación
    49.385.306,00. El export de **ventas** reproduce esa facturación **al peso**
    (diferencia 0,00); el de **compras** trae 10.190.380,61 de los 38,2 M. Son
    los mismos servicios, no dos universos. Consecuencia medida: el cluster de
    octubre da **+256,9 % con el costo del export y +19,5 % con el costo real**,
    o sea OK contra *por debajo del mínimo*. `AMFU 848078-5` da +20,7 % y
    +18,8 %. **El export solo no es impreciso: da vuelta el veredicto.** Por eso
    las dos fuentes conviven (decisión D1): la vista expone `markup_manual`,
    `markup_cluster_manual`, `cobertura_costo` y la bandera `alerta_manual`, y
    la pantalla muestra las dos columnas una al lado de la otra.
  - **Los códigos de contenedor se unifican automáticamente.** El CRM escribe
    `IF 4252-04` y Tango `IF 04252-4`: es el mismo trailer. La regla (idéntica
    en SQL y en JS) es mayúsculas, espacios colapsados y cada corrida de dígitos
    sin ceros a la izquierda. `IF 04252-11` queda distinto. Dos series ISO de 6
    dígitos no pueden colisionar (si una pierde un cero queda más corta), y
    contra las 65 series reales que hay en `index.html` no hay ni una fusión
    indebida. El resguardo es `ind_dtmlog_v_series_unificadas`, que lista toda
    unificación que juntó más de una escritura, y la pantalla la muestra.
  - **Justificar y posponer son dos cosas distintas, a propósito.** "Todavía no
    pasó" se pospone y vuelve solo en una fecha; "esto está explicado" se
    justifica y vuelve solo si cambia la **huella** del caso (md5 de los
    comprobantes y los totales redondeados a peso). Si hubiera un solo botón, la
    gente justificaría cosas que estaba posponiendo. El motivo sale de una lista
    corta de cinco, para poder medir después cuál se repite y con qué proveedor.
    `ind_dtmlog_comentarios` es **append-only**: sin update ni delete, ni
    política ni grant.
  - **Comentar y justificar tienen permisos DISTINTOS.** Comentar lo puede
    cualquiera del sector (el que sabe por qué falta un costo suele ser alguien
    de compras, no el que importa); justificar y posponer **sacan un caso del
    tablero**, así que exigen estar en `ind_dtmlog_editores`. En los tres casos
    el RLS obliga a que la nota venga firmada con el mail del JWT.
  - **La edad de un caso se mide contra la fecha de corte del último informe
    importado, y cruzando los lados**: una compra sin venta se mide contra hasta
    dónde llegan las **ventas**. Si se midiera contra `now()`, dos semanas sin
    importar envejecerían todo el tablero a rojo sin que hubiera pasado nada.
    Ventanas: 45 días para "compra sin venta" (rojo) y 60 para "venta sin
    compra" (ámbar, nunca rojo). `ind_dtmlog_v_lag` guarda el lag real de cada
    par que cierra, para recalibrarlas con el dato propio a los tres meses.
  - **La baja es lógica, nunca `delete`**, y el CHECK obliga a registrar motivo
    **y quién**. Las vistas no se materializan: una vista materializada no
    respeta RLS y además habría que refrescarla.
  - **La vista de auditoría depende de los permisos de `ind_dtm_data`.** Va con
    `security_invoker`, así que lee esa tabla con los permisos del usuario. Hoy
    funciona porque la migración del 2/11 le dio `grant select to authenticated`
    y política por sector. Si alguna vez se los sacan, el Control DTM entero
    deja de cargar con un `permission denied for table ind_dtm_data` que no
    menciona esta vista por ningún lado.
  - **La migración borra las vistas antes de crearlas.** `create or replace
    view` no puede renombrar ni reordenar columnas, así que re-correr el archivo
    con una columna nueva en el medio falla con un error que no dice nada. Las
    tablas no se tocan: no se pierde un dato.
  - **Validación.** SQL: PostgreSQL 16 descartable con las 59 filas reales —
    21 comprobantes y 34 renglones, idempotente en tres cargas, 19 pruebas de
    permisos (anon no lee nada, el de la lista escribe, el de afuera comenta
    pero no justifica, sin sector no ve nada), y el rollback no deja ni un
    objeto. Parser: 128 casos × 4 husos (UTC, Buenos Aires, Auckland, Kolkata),
    con la verdad de las fechas sacada de openpyxl. Navegador: 68 pruebas con
    Playwright forzando `timezoneId: 'America/Argentina/Buenos_Aires'`, más 29
    de regresión sobre lo que ya andaba. Todo en
    `scratchpad/dtm/` (fuera del repo).
  - **Lo único que se tocó de lo existente son 2 líneas**: `comPuedeVer()`
    (`index.html:1842`, sumar `'ctrl_dtm'` al early-return, mismo patrón que
    `'indicadores'`) y `SECCIONES_REPORTE_COM` (`index.html:1833`). El resto son
    1.045 líneas agregadas, 0 borradas.
- **Duplicar cotización**: copia una OE en una oferta nueva (número propio,
  versión 01). Distinto de "Nueva versión". No hereda fecha de envío, carpeta
  de SharePoint ni la oportunidad de origen (copiar `fromOppId` le robaría la
  OP a la original al guardar).
- **Impresión**: en `@media print` hay una regla que oculta **todo** hijo directo
  de `<body>` salvo `.app`, `#catPrintLayer` y `#edcPrintLayer` (era la única
  forma de tapar el botón flotante de `/portal/nav.js`, que vive en un shadow
  DOM). Trampa a tener presente: **si algún día se agrega un elemento nuevo a
  nivel de `<body>` que SÍ deba imprimirse, hay que sumarlo a esa lista** o no
  va a salir en el PDF, sin ningún error visible.
- Pipeline Kanban, log de actividades con próximo paso, audit trail parcial
  (tabla `audit_log`, `fn_audit()`). Triggers confirmados funcionando (con
  registros reales) en `oportunidades` y `cotizaciones`. Los triggers en
  `pedidos` y `facturas` NO están confirmados: `audit_log` no tiene ningún
  registro de esas dos tablas — pendiente verificar si los triggers existen
  y están disparando (investigación directa 2/7/2026).
- Módulo de cotizaciones de Ventas (sin plazo/período, columna `unidad_negocio`
  en `cotizaciones`).
- Módulo de Cobranzas: condiciones de pago, adicionales, sistema de ageing,
  semáforo, notificaciones Teams + mail.
- Circuito de facturación: tablas `pedidos` y `facturas`, arquitectura de
  integración con Tango vía Edge Functions diseñada. Las tablas maestras
  (`tango_articulos`, `tango_clientes`, `tango_vendedores`, `tango_depositos`,
  `tango_config`) NUNCA se crearon en producción (confirmado por investigación
  directa el 2/7/2026: no existen en el esquema, sin rastro en `audit_log`,
  sin referencias en `index.html` ni en migraciones del repo). La importación
  real de estas tablas sigue pendiente.
- Hardening de seguridad: políticas `anon` permisivas eliminadas de `catalogo`,
  `clientes`, `contador`, `cotizaciones`; `execute` de `next_seq()` revocado a `anon`.
- Consistencia visual entre dashboards Rental y Ventas.

## Pendientes conocidos

- **Control DTM — LA PREGUNTA QUE HAY QUE RESPONDER PRIMERO**: ¿el costo de
  octubre aparece en el informe de **compras de noviembre**? De eso depende si
  la brecha del 73 % es un desfasaje contable (y entonces la ventana de gracia
  lo resuelve, y con el tiempo el export solo alcanza) o si el costo que usa la
  auditoría manual sale de las OC y no de la contabilidad (y entonces el export
  **nunca** va a servir para calcular margen y hay que replantear). Se responde
  pidiéndole a Ignacio los cuatro informes de un mes completo.
- **Control DTM — falta la columna de cliente en el informe de ventas de
  Tango.** El de compras ya trae `Proveedor`; el de ventas no trae su
  equivalente. Es la misma familia de consulta, o sea que es un campo que falta
  en la consulta compartida, no un dato inexistente. Mientras tanto el cliente
  no se deriva: se muestra vacío, porque un nombre equivocado con cara de dato
  cierto es peor que un casillero vacío en una pantalla que se usa para
  reclamarle a compras o a un cliente.
- **Avisarle a Administración que el total del pie de esos cuatro informes de
  Tango vale el doble del movimiento real.** Si alguien lo está leyendo como
  total, está leyendo el doble.
- **Caso concreto de imputación cruzada, para revisar con compras**: comprobante
  `A0002000000834` de OFIC3 del 23/10. Tango le asigna 1.082.000 a
  `GSTU 718552-9` y 810.000 a `IF 03061-2`; la auditoría manual los tiene al
  revés. Los mismos dos importes, intercambiados entre los mismos dos
  contenedores.

- `COD_GVA23` de Victoria López Aybar en Tango: falta dar de alta como vendedora.
- Config `lista_precios_dolar_billete`: falta completar el número de lista de Tango.
- **Diferencias entre el Excel del técnico de reefers y la base** (salieron de
  cruzar las 33 hojas contra producción, 4/11/2026). El código no necesita
  cambios: el botón ya las resuelve todas. Lo que queda son decisiones
  comerciales.
  - **RESUELTO — 5 series que la planilla factura y no existen en
    `ind_rental_data`** (confirmado por Ignacio, 4/11/2026). Ninguna debe
    facturar, y el botón ya las excluye porque no están en `ind_rental_data`.
    Siguieron facturando hasta septiembre 2026 con estas fechas de salida:

    | serie | salió | facturó desde | meses | días | USD |
    |---|---|---|---:|---:|---:|
    | `SCXU 492781-3` | 01/09/2023 (subalquiler devuelto) | 01/2024 | 33 | 1.004 | 3.833 |
    | `TOLU 780207-8` | 02/01/2025 | 01/2025 | 21 | 638 | 2.552 |
    | `FSCU 560476-4` | 02/01/2025 | 01/2025 | 21 | 638 | 2.552 |
    | `SUDU 475338-3` | 02/01/2025 | 01/2025 | 21 | 638 | 2.552 |
    | `CRLU 110562-4` | 02/01/2025 | 01/2025 | 21 | 638 | 2.552 |
    | | | | | **3.556** | **14.041** |

    Las fechas son `dd/mm/aaaa`, confirmado por Ignacio. El `SCXU` salió
    **antes de que empezara la planilla** y se facturó los 33 meses enteros.

    **`TOLU 780207-8` y `TOLU 780208-3` son dos contenedores distintos**, no
    una serie mal escrita: el `780208-3` sigue alquilado a BAMBOO y factura
    bien; el `780207-8` se vendió el 2/1/2025 y siguió facturando 21 meses.
    Durante el análisis se había planteado que uno duplicaba al otro porque las
    dos facturan los mismos días todos los meses — **eso no prueba nada**:
    44 de las 74 series del archivo hacen lo mismo porque están alquiladas de
    forma continua. Vale como recordatorio de que en esta flota la continuidad
    es la norma, no una anomalía.
  - **ABIERTO — 3 que la planilla factura y la base tiene en stock**:
    `CRLU 726949-8`, `SUDU 475651-0`, `ZCSU 511065-4`. En septiembre 2026
    cobran mes completo, y ese mes no tuvo ningún tramo parcial.
  - **ABIERTO — 4 alquiladas a las que la planilla no les puso días**:
    `CCLU 859877-6`, `CCLU 860139-7`, `CXRU 118045-3`, `SUDU 475293-6`.
  - **`ZCSU 511065-4` está duplicada en 15 hojas seguidas** (07-2025 a 09-2026):
    455 días de más, 1.820 USD. El botón la cuenta una sola vez. Este sí es un
    duplicado confirmado: la misma serie aparece dos veces en la misma hoja.
  - **Julio 2025 se pagó de menos**: la fórmula del total de esa hoja arranca en
    `F11` en vez de `F4` y se comió el bloque de 20 pies. 93 días = 372 USD
    (al TC 1375 de esa hoja, ARS 511.500). Es la única hoja de 33 con el rango
    mal.
  - **Conciliación de septiembre 2026, exacta**: planilla 57 filas (1.710 días);
    −5 fuera de la flota, −1 fila repetida, −3 que la base tiene en stock,
    +4 alquilados sin días = **52 contenedores, 1.560 días**, que es justo lo
    que da el botón.
  - **Acumulado**: 14.041 USD facturados después de la salida + 1.820 del
    duplicado de ZCSU − 372 que se pagaron de menos en julio 2025 =
    **15.489 USD de más**, sin contar los 3 en stock ni los 4 sin días, que
    siguen abiertos.
- **Pedido draft UI** dentro de cada cobranza — próximo paso grande, requiere
  tocar el `index.html` actual completo.
- Push de pedidos a Tango vía API (`POST Api/Create/{process}`) una vez exista
  la UI. Mientras tanto, importación por Excel de facturas sigue siendo el
  workaround (la API de lectura de Tango está "próximamente").
- Talonarios: 56 (PEDIDOS ALQUILERES) para Rental, 57 (PEDIDOS VENTAS) para Ventas.
- Circuito de aprobación de adicionales post-venta (re-cotización) — no
  implementado todavía.
- Compartimentalización row-level entre usuarios internos (hoy todos los
  usuarios autenticados ven todos los datos) — consideración de seguridad futura.
- Existe una tabla `contadores` (plural) además de `contador` (singular), con
  estructura distinta (`nombre` + `seq`, 2 filas, sin foreign keys). No está
  confirmado si las RPCs `next_seq()` / `next_seq_un()` la usan — hay que
  revisar el código de esas funciones antes de tocar o eliminar cualquiera de
  las dos tablas.

## Cómo entregar trabajo

- **Archivos HTML/JS:** entregar el archivo completo actualizado o instrucciones
  claras de qué reemplazar, ya validado con `node --check`.
- **Migraciones SQL:** archivo `.sql` separado (o `INSTRUCCIONES-SQL.md` si hace
  falta explicar pasos), nunca ejecutado directo contra producción sin que
  Pablo lo revise y corra él mismo.
- **Si algo no sale como se esperaba:** diagnosticar con evidencia (grep/diff
  contra el archivo original), no adivinar.
- Asumir que el archivo entregado se despliega tal cual, sin ediciones manuales
  intermedias — es una base confiable para diagnosticar síntomas.
