-- Copia los datos de las tablas antiguas (esquema public) a los esquemas de cada contexto.
-- Ejecutar UNA vez, después de 001 a 007, y solo con los servicios detenidos.
-- Aborta si algún esquema destino ya tiene datos (no sobrescribe ni duplica).
-- Los ids se conservan para que las reservas sigan apuntando a sus vuelos y asientos.
-- No copia tokens: son sesiones vencibles; los usuarios vuelven a iniciar sesión.

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM identidad.usuarios)
       OR EXISTS (SELECT 1 FROM vuelos.vuelos)
       OR EXISTS (SELECT 1 FROM vuelos.asientos_vuelo)
       OR EXISTS (SELECT 1 FROM aviones.aviones)
       OR EXISTS (SELECT 1 FROM reservas.reservas)
       OR EXISTS (SELECT 1 FROM reservas.reserva_asientos) THEN
        RAISE EXCEPTION 'Los esquemas destino ya tienen datos: no se copia nada.';
    END IF;
END $$;

INSERT INTO identidad.usuarios (id, nombre, email, password_hash, rol)
SELECT id, nombre, email, password_hash, rol FROM public.usuarios;

INSERT INTO aviones.aviones (id, nombre, capacidad, activo)
SELECT id, nombre, capacidad, activo FROM public.aviones;

INSERT INTO vuelos.vuelos (id, origen, destino, fecha, hora, precio, asientos_disponibles, activo, hora_llegada, avion_id)
SELECT id, origen, destino, fecha, hora, precio, asientos_disponibles, activo, hora_llegada, avion_id FROM public.vuelos;

INSERT INTO vuelos.asientos_vuelo (id, vuelo_id, codigo, fila, columna, reserva_id)
SELECT id, vuelo_id, codigo, fila, columna, reserva_id FROM public.asientos_vuelo;

INSERT INTO reservas.reservas (id, usuario_email, vuelo_id, pasajero, estado, lote_id, precio, tipo_documento, documento)
SELECT id, usuario_email, vuelo_id, pasajero, estado, lote_id, precio, tipo_documento, documento FROM public.reservas;

INSERT INTO reservas.reserva_asientos (reserva_id, vuelo_id, asiento)
SELECT reserva_id, vuelo_id, asiento FROM public.reserva_asientos;

-- Las secuencias de identidad no avanzan con inserts de id explícito: se ajustan al máximo copiado.
SELECT setval(pg_get_serial_sequence('identidad.usuarios', 'id'), COALESCE((SELECT MAX(id) FROM identidad.usuarios), 1), (SELECT COUNT(*) > 0 FROM identidad.usuarios));
SELECT setval(pg_get_serial_sequence('aviones.aviones', 'id'), COALESCE((SELECT MAX(id) FROM aviones.aviones), 1), (SELECT COUNT(*) > 0 FROM aviones.aviones));
SELECT setval(pg_get_serial_sequence('vuelos.vuelos', 'id'), COALESCE((SELECT MAX(id) FROM vuelos.vuelos), 1), (SELECT COUNT(*) > 0 FROM vuelos.vuelos));
SELECT setval(pg_get_serial_sequence('vuelos.asientos_vuelo', 'id'), COALESCE((SELECT MAX(id) FROM vuelos.asientos_vuelo), 1), (SELECT COUNT(*) > 0 FROM vuelos.asientos_vuelo));
SELECT setval(pg_get_serial_sequence('reservas.reservas', 'id'), COALESCE((SELECT MAX(id) FROM reservas.reservas), 1), (SELECT COUNT(*) > 0 FROM reservas.reservas));

-- Verificación: los conteos deben coincidir con public antes del COMMIT.
SELECT
    (SELECT COUNT(*) FROM identidad.usuarios)  AS usuarios,
    (SELECT COUNT(*) FROM vuelos.vuelos)       AS vuelos,
    (SELECT COUNT(*) FROM vuelos.asientos_vuelo) AS asientos,
    (SELECT COUNT(*) FROM aviones.aviones)     AS aviones,
    (SELECT COUNT(*) FROM reservas.reservas)   AS reservas,
    (SELECT COUNT(*) FROM reservas.reserva_asientos) AS reserva_asientos;

COMMIT;
