-- Documento de quien viaja en cada asiento (cedula o pasaporte). Idempotente. Ejecutar despues de 003.
ALTER TABLE reservas.reservas ADD COLUMN IF NOT EXISTS tipo_documento varchar(10) NULL;
ALTER TABLE reservas.reservas ADD COLUMN IF NOT EXISTS documento varchar(20) NULL;
