# Reservas SOA (FastAPI)

Five independent FastAPI services that communicate over HTTP with JSON, one database per service (SQLite).

| Service | Port | Endpoints |
|---|---|---|
| S1 Usuarios | 5001 | `POST /api/usuarios` |
| S2 Autenticación | 5002 | `POST /api/auth/login` |
| S3 Vuelos | 5003 | `GET /api/vuelos?origen=&destino=&fecha=`, `GET /api/vuelos/{id}` (internal) |
| S4 Reservas | 5004 | `POST /api/reservas` (Bearer) |
| S5 Gestión de reservas | 5005 | `GET /api/reservas`, `DELETE /api/reservas/{id}` (Bearer) |

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

## Run

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

Optional environment variables: `IDENTITY_DB`, `FLIGHTS_DB`, `BOOKINGS_DB` (SQLite file paths, default under `data/`), `JWT_SECRET`, `FLIGHTS_SERVICE_URL`, `CORS_ORIGINS`.

## Error contract

Every error: `{"codigo": "<CODE>", "mensaje": "<text>"}`. Invalid input returns 400 (`DATOS_INVALIDOS`).

## Known limitations

- Seats are read from S3 but not decremented when a reservation is created or cancelled. S3 exposes no write endpoint, which keeps the endpoint list to the guide's scope. Two concurrent bookings can take the last seat.
- S1 and S2 share the identity database file; S4 and S5 share the reservations database file. This is the deliberate trade-off of the five-service design.
- A JWT is validated locally by each service with a shared HS256 key; there is no token revocation.
