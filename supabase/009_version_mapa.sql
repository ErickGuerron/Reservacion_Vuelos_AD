-- Versión del mapa de asientos por vuelo (control de concurrencia optimista).
-- Idempotente: se puede ejecutar más de una vez. Ejecutar después de 008.
-- Cada cambio de asientos (reservar, cancelar, cambiar asiento) suma 1 a `version` dentro de su
-- misma transacción. Una reserva con una versión vieja se rechaza y el cliente recarga el mapa.

ALTER TABLE vuelos.vuelos ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 0;
