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

- `COD_GVA23` de Victoria López Aybar en Tango: falta dar de alta como vendedora.
- Config `lista_precios_dolar_billete`: falta completar el número de lista de Tango.
- **Diferencias abiertas en la liquidación del técnico de reefers** (salieron de
  cruzar el Excel histórico contra la base, 4/11/2026). Ninguna se corrigió:
  son decisiones comerciales, no bugs del código.
  - **5 series que la planilla factura y que no existen en `ind_rental_data`**:
    `CRLU 110562-4`, `FSCU 560476-4`, `SCXU 492781-3`, `SUDU 475338-3`,
    `TOLU 780207-8`. 150 días por mes = 600 USD. Falta confirmar si salieron de
    la flota o si es un error de clasificación en Tango.
  - **3 que la planilla factura y la base tiene en stock**: `CRLU 726949-8`,
    `SUDU 475651-0`, `ZCSU 511065-4`. En septiembre 2026 cobran mes completo,
    y ese mes no tuvo ningún tramo parcial.
  - **4 alquiladas a las que la planilla no les puso días**: `CCLU 859877-6`,
    `CCLU 860139-7`, `CXRU 118045-3`, `SUDU 475293-6`.
  - **`ZCSU 511065-4` está duplicada en 15 hojas seguidas** (07-2025 a 09-2026):
    455 días de más, 1.820 USD. El botón la cuenta una sola vez.
  - **Julio 2025 se pagó de menos**: la fórmula del total de esa hoja arranca en
    `F11` en vez de `F4` y se comió el bloque de 20 pies. 93 días = 372 USD
    (al TC 1375 de esa hoja, ARS 511.500). Es la única hoja de 33 con el rango
    mal.
  - En conjunto, para septiembre 2026 el botón da **150 días menos** que la
    planilla: 1.560 contra 1.710 (600 USD, ARS 930.000 al TC 1550).
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
