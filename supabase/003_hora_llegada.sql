-- Hora estimada de llegada de un vuelo (opcional, HH:MM). Idempotente. Ejecutar despues de 002.
ALTER TABLE vuelos.vuelos ADD COLUMN IF NOT EXISTS hora_llegada varchar(5) NULL;
