-- Concurrencia de asientos y reservas (PostgreSQL / Supabase).
-- Idempotente: se puede ejecutar más de una vez. Ejecutar después de 006.
-- Los servicios bloquean filas con SELECT ... FOR UPDATE; estos índices hacen que la base de datos
-- rechace cualquier estado inconsistente aunque una operación concurrente llegue tarde.

-- Una reserva ocupa como máximo un asiento. Sin esto, un cambio de asiento concurrente podía
-- dejar dos asientos a nombre de la misma reserva.
CREATE UNIQUE INDEX IF NOT EXISTS uq_asiento_reserva
    ON vuelos.asientos_vuelo (reserva_id)
    WHERE reserva_id IS NOT NULL;

-- Búsqueda del primer asiento libre de un vuelo (asignación automática).
CREATE INDEX IF NOT EXISTS ix_asientos_vuelo_libres
    ON vuelos.asientos_vuelo (vuelo_id, fila, columna)
    WHERE reserva_id IS NULL;
