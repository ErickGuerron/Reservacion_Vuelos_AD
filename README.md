# Reservas SOA (FastAPI)

Five independent FastAPI services that communicate over HTTP with JSON, one database per service (SQLite).

| Service | Port | Endpoints |
|---|---|---|
| S1 Usuarios | 5001 | `POST /api/usuarios` |
| S2 Autenticación | 5002 | `POST /api/auth/login` |
| S3 Vuelos | 5003 | `GET /api/vuelos?origen=&destino=&fecha=`, `GET /api/vuelos/{id}`, `GET /api/vuelos/{id}/asientos` (seat map), `POST /api/admin/vuelos` (admin) |
| S4 Reservas | 5004 | `POST /api/reservas` (Bearer, optional `asiento`) |
| S5 Gestión de reservas | 5005 | `GET /api/reservas`, `DELETE /api/reservas/{id}` (Bearer) |

Internal calls between services (not for clients): S3 `POST /api/internal/vuelos/{id}/asientos/reservar` (used by S4) and `POST /api/internal/reservas/{id}/liberar` (used by S5).

## Administrators and seat selection

- **Roles**: every account has a role, `"cliente"` (default on registration) or `"administrador"`. The role is stored in the identity database (`usuarios.rol`) and copied into the `rol` claim of each token and into the login response.
- **Bootstrap admins**: emails listed in `ADMIN_EMAILS` (comma-separated, set in `.env`) are always administrators. They are promoted at login and the API cannot demote them (409 `ADMIN_DE_CONFIGURACION`).
- **Manage roles** (administrator token): `GET /api/admin/usuarios` lists accounts with their role; `PUT /api/admin/usuarios/{id}/rol` with `{"rol": "cliente" | "administrador"}` changes a role. The last administrator cannot be demoted (409 `ULTIMO_ADMINISTRADOR`). S1 checks the role in the database, so a demoted account loses access at once; S3 trusts the token claim until it expires (60 minutes).
- **Passwords**: stored with bcrypt (cost 12). Passwords longer than 72 bytes are rejected at registration, because bcrypt ignores or rejects anything beyond that. Hashes created before bcrypt (PBKDF2) still work and are upgraded on the next successful login. Users do not need to reset their password.
- **Create a flight** (admin token): `POST /api/admin/vuelos` with `{origen, destino, fecha, precio, filas, columnas}`. Origin and destination are 3-letter codes; `filas` is 1-50 and `columnas` is 1-8 (letters A to H). The response is 201 with the flight. Without a token it returns 401; with a client token it returns 403 (`PERMISO_DENEGADO`).
- **Seat map** (public): `GET /api/vuelos/{id}/asientos` returns `{vueloId, filas, columnas, asientosLibres, asientos: [{codigo, fila, columna, ocupado}]}`. Seat codes look like `12C`.
- **Choose a seat**: `POST /api/reservas` accepts `"asiento": "12C"`. The seat is taken in S3 inside the same transaction as the reservation, so a seat taken by another passenger returns 409 `ASIENTO_OCUPADO`, an unknown seat returns 404 `ASIENTO_NO_EXISTE`, and no reservation is saved in either case. If `asiento` is omitted, the first free seat is assigned. The response includes `asiento`.
- **Cancel**: `DELETE /api/reservas/{id}` frees the seat in S3 before marking the reservation as cancelled. If S3 is down, the cancellation fails with 503 and the reservation stays confirmed.
- Flights that existed before this change receive a seat map on startup, with as many seats as they had free, laid out in 6 columns (A to F).

## Passenger document and invoice

- **Document per passenger**: each seat of a purchase carries the document of the person who flies in it. `POST /api/reservas` and `POST /api/reservas/lote` accept `tipoDocumento` (`"cedula"` or `"pasaporte"`) and `documento` per passenger. Both go together or neither is sent. A cédula is validated as an Ecuadorian ID (10 digits, province 01-24 or 30, third digit below 6, check digit); a passport is 6-12 letters or digits. Invalid values return 400 and nothing is stored. Reservations made before this change keep both fields `null`. Existing databases get the two columns on startup; on Supabase run `supabase/004_documento_pasajero.sql`.
- **Listing**: `GET /api/reservas` and the S4 responses include `tipoDocumento` and `documento`.
- **Invoice XML** (`GET /api/reservas/lote/{id}/factura`): the existing fields are unchanged (`numero`, `fecha`, `cliente`, `pasajeros`, `subtotal`, `iva` at 15 %, `total`). After `total` it adds `<vuelo>` (origin, destination, date, time, when S3 answers) and `<boletos>` with one `<boleto>` per confirmed passenger (`pasajero`, `tipoDocumento`, `documento`, `asiento`, `precio`).
- **Flutter client**: the invoice dialog shows the flight, one ticket per passenger and the IVA, and downloads the invoice as XML (as S5 returns it) or as PDF (built in the app with the `pdf` package; run `flutter pub get` after pulling).

## CORS for Flutter

Browser clients can call every service from any `localhost` or `127.0.0.1` port. Flutter web picks a random port on each run, so the default is a regular expression (`CORS_ORIGIN_REGEX`) and not a fixed list. The explicit list `CORS_ORIGINS` still applies on top of it. Set `CORS_ORIGIN_REGEX` to an empty value to disable the regular expression.

Interactive contracts (OpenAPI): `http://localhost:<port>/docs` for each service.

## Configuration (.env)

Create a `.env` file in this folder (it is ignored by git). Settings are read from it at startup; real environment variables take precedence.

```ini
JWT_SECRET=a-secret-of-at-least-32-bytes-long!!
DB_PROVIDER=sqlite            # or sqlserver
FLIGHTS_SERVICE_URL=http://localhost:5003

# Only when DB_PROVIDER=sqlserver
SQLSERVER_SERVER=localhost
SQLSERVER_DRIVER=ODBC Driver 18 for SQL Server
SQLSERVER_USER=               # empty = Windows authentication
SQLSERVER_PASSWORD=
```

- **SQLite** (default): one file per context under `data/`, created automatically.
- **SQL Server**: three databases on the server, created automatically: `ReservasIdentidad` (S1, S2), `ReservasVuelos` (S3) and `ReservasReservas` (S4, S5). The login needs permission to create databases.
- The automated tests always use SQLite. To verify SQL Server, run the services with `DB_PROVIDER=sqlserver` and repeat the request flow.

## Setup

```powershell
python -m pip install -r requirements.txt
$env:JWT_SECRET = "a-secret-of-at-least-32-bytes-long!!"   # same value for every service
python -m pytest
```

## Run with the console (recommended for the demo)

The console starts the API gateway and the five services in the background, and can switch one service off and on:

```powershell
python -m orquestador iniciar              # gateway (8000) + S1..S5, in the background
python -m orquestador estado               # enabled / running state of each process
python -m orquestador desactivar reservas  # stops S4; the gateway answers 503 SERVICIO_DESACTIVADO
python -m orquestador activar reservas     # enables it again and starts it
python -m orquestador detener              # stops everything the console started
```

Logs go to `runtime/logs/`. If a port is already used by a process the console did not start, `iniciar` reports it and does not touch it; close that process first. `desactivar` also works on such a service: the gateway blocks its routes even if the process keeps running.

## API Gateway

Clients use one address: `http://localhost:8000`. The gateway forwards each route to its service, keeps the method, query, body and `Authorization` header, and sets the CORS headers itself, so Flutter web and the browser client work through it.

- Internal endpoints (`/api/internal/...`) are not routed: 404 `RUTA_NO_EXISTE`.
- A disabled service answers 503 `SERVICIO_DESACTIVADO`; a service that does not respond answers 503 `SERVICIO_NO_DISPONIBLE`.
- `GET http://localhost:8000/api/gateway/servicios` shows, for each service, whether it is enabled and whether it answers.
- Switches are stored in `runtime/estado.json` and read on every request, so the gateway does not need a restart.

## Run each service by hand

Start each service from this folder (one terminal each):

```powershell
python -m uvicorn usuarios.main:app --port 5001
python -m uvicorn autenticacion.main:app --port 5002
python -m uvicorn vuelos.main:app --port 5003
python -m uvicorn reservas.main:app --port 5004
python -m uvicorn gestion.main:app --port 5005
```

Start the flight service (S3) before S4 is used; S4 calls it at `FLIGHTS_SERVICE_URL` (default `http://localhost:5003`).

## Web client

`cliente/` is a static HTML + JavaScript client that consumes all five services with `fetch` (JSON over HTTP). Serve it on port 8080 so its origin matches the CORS default:

```powershell
python -m http.server 8080 --directory cliente
```

Open `http://localhost:8080`. The bottom panel logs every request and response. Allowed origins are set with `CORS_ORIGINS` (comma-separated, default `http://localhost:8080,http://127.0.0.1:8080`).

Optional environment variables: `IDENTITY_DB`, `FLIGHTS_DB`, `BOOKINGS_DB` (SQLite file paths, default under `data/`), `JWT_SECRET`, `FLIGHTS_SERVICE_URL`, `CORS_ORIGINS`, `CORS_ORIGIN_REGEX`, `ADMIN_EMAILS`.

## Error contract

Every error: `{"codigo": "<CODE>", "mensaje": "<text>"}`. Invalid input returns 400 (`DATOS_INVALIDOS`).

## Known limitations

- Seat claims are atomic inside S3 (a conditional UPDATE), so two passengers cannot take the same seat. S4 takes the seat in S3 before it commits the reservation; if S4 fails to commit after S3 accepted the seat, that seat stays taken until someone cancels it. There is no compensation job.
- The internal endpoints under `/api/internal/` have no authentication. They are reachable by anyone who can reach port 5003 or 5005; use network isolation outside local development.
- S1 and S2 share the identity database file; S4 and S5 share the reservations database file. This is the deliberate trade-off of the five-service design.
- A JWT is validated locally by each service with a shared HS256 key; there is no token revocation.

## Arrival time (`horaLlegada`)

Flights carry an optional estimated arrival time (`HH:MM`, 24 h, local time at the destination). It lives in `vuelos.vuelos.hora_llegada` (migration `supabase/003_hora_llegada.sql`), is served by S3 as `horaLlegada` on public and admin endpoints and is included in the `<vuelo>` block of the invoice XML. An arrival earlier than the departure is read as the next day (`+1`); the server does not validate it against the departure. `PUT /api/admin/vuelos/{id}` replaces the whole flight, so clients must resend `horaLlegada` when editing.

### Departure and arrival rules (S3)

- `shared/horarios.py` holds the rules. Times are local to each airport; durations are computed in UTC with the airport time zone (Ecuador UTC-5, Madrid with daylight saving; `tzdata` is in `requirements.txt` for Windows).
- Creating or editing a flight requires the departure (origin local time) to be in the future. When `horaLlegada` is sent and the route is known, the implied duration must be within the usual duration +/- 25 % (at least 20 minutes). Usual durations are rough averages in `DURACIONES_MIN` (UIO-GYE 55 min, UIO-MAD 9 h 45, MAD-UIO 10 h 40, GYE-MAD 9 h 50, MAD-GYE 10 h 40) and can be tuned there. Unknown routes skip the duration check.
- `GET /api/vuelos/estimacion?origen&destino&fecha&hora[&horaLlegada]` returns the usual duration, the suggested arrival and whether a given arrival is coherent (404 `RUTA_SIN_ESTIMACION` for unknown routes). The Flutter flight form uses it to suggest the arrival.
- `GET /api/vuelos?franja=madrugada|manana|tarde|noche` filters by departure band (00-06, 06-12, 12-18, 18-24). Explorar vuelos applies the same bands on the client.
