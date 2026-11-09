Feature: registro de aviones (S6 Aviones) y creación de vuelos con avión.
Branch: feature/registro-aviones. Delivery: single-pr (default ask-on-risk not triggered: under 400 lines per unit).
Test runner: python -m pytest (SQLite in tests); front end: flutter analyze, flutter test.

## Specs

S1. "tenemos que hacer un servicio para registro de aviones" → microservicio aparte S6 Aviones, puerto 5006, con su propia base de datos (contexto "aviones").
S2. "el nombre del avion y la capacidad que seria el numero de asientos" → avión = nombre + capacidad. Capacidad = número de asientos, con las reglas de shared/asientos (18 a 180, múltiplo de 6). Nombre único.
S3. "cada vuelo tiene un numero de asientos" → al crear o editar un vuelo se elige un avión; el mapa de asientos del vuelo sale de la capacidad del avión (en lugar de totalAsientos).
S4. "que sea igual de agnostico que ahora" → S6 usa shared/db.py como los demás servicios: DB_PROVIDER=sqlite | sqlserver | postgres, sin SQL propio del motor en el código.
S5. "para que mi amigo pueda usarlo en supabase y haga los cambios" → supabase/006_aviones.sql idempotente (esquema aviones, tabla, columna vuelos.avion_id) y README documentado.
S6. "revisa bien lo de crear vuelos, deberia existir ya tambien" → el alta de vuelos existe; no se muestra porque el botón exige rol administrador y no hay ninguna cuenta administradora (ADMIN_EMAILS vacío y sin usuarios). Documentar cómo obtener el primer administrador.
S7. Front end (Flutter): el administrador registra aviones (lista, alta, edición, activar/desactivar) y crea vuelos eligiendo avión; la vista previa del plano usa la capacidad del avión.

Assumptions (not requested verbatim, to confirm if they change):
A1. avionId reemplaza totalAsientos en POST/PUT /api/admin/vuelos (cambio de contrato; cliente Flutter se actualiza en esta rama).
A2. Cambiar la capacidad de un avión solo afecta a vuelos creados después; los existentes conservan su mapa.
A3. Sin borrado de aviones: se desactivan (activo=false) y dejan de poder asignarse a vuelos nuevos.
A4. Vuelos sembrados o anteriores (avion_id NULL) conservan su mapa; al editarlos hay que elegir avión.

## Tasks

T1 [S1, S2, S4] Servicio S6 Aviones + contexto de base de datos + tests. Route: inline. Status: pending.
T2 [S5] supabase/006_aviones.sql + README (puertos, variables, primer administrador). Route: inline. Status: pending.
T3 [S3, S6] S3 valida avión contra S6 al crear y editar; avion_id en vuelos; actualizar tests existentes de totalAsientos. Route: inline. Status: pending.
T4 [S1] Gateway (ruta /api/admin/aviones, puerto, estado) y consola (servicio S6). Route: inline. Status: pending.
T5 [S6, S7] Flutter: modelo Avion, AvionesService, diálogo de aviones para administrador, selector de avión en alta/edición de vuelo. Route: inline. Status: pending.
T6 [all] Verificación completa: pytest, flutter analyze, flutter test. Status: pending.

## Log

L1 (user, original request, verbatim): "necesito que hagamos el tema de los vuelos, tenemos que hacer un servicio para registro de aviones, nos lo solicito el docente, ademas revisa bien lo de crear vuelos, deberia existir ya tambien"
L2 (user, correction, verbatim): "nonono, me refiero a registrar aviones para los vuelos, recuerdas que cada vuelo tiene un numero de asientos?, tambien he regresado .env a sql lite que teniamos porque tenia que ya migrar a supabase pero mi compañero de equipo no envia el .env correcto asi que levanta docker para que podamos usarlo, creo que un registro de aviones incluiria el nombre del avion y la capacidad que seria el numero de asientos, explicame como esto funciona en los vuelos para entender como podemos hacer el front end de este paso para vuelos"
L3 (user, decision, verbatim): "si un microservicio aparte y se que va a ser un monton de cambios pero realizalo y que sea igual de agnostico que ahora para que mi amigo pueda usarlo en supabase y haga los cambios"
L4 (agent): Branch created from main; previous fixes committed as dbd9af9 (gestion/usuarios/vuelos). Engram was degraded at start; this document is the recovery copy.
