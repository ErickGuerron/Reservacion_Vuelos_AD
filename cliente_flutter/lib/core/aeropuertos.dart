// Aeropuertos disponibles en la aplicación: los mismos códigos que los desplegables de búsqueda.
// Para agregar uno nuevo, agréguelo aquí y en el servicio de vuelos (S3) si acepta vuelos reales.
const aeropuertos = <String, String>{
  'UIO': 'UIO • Quito, Mariscal Sucre',
  'GYE': 'GYE • Guayaquil, José Joaquín de Olmedo',
  'MAD': 'MAD • Madrid-Barajas Adolfo Suárez',
};

// Ciudad de un código de aeropuerto ("UIO" -> "Quito"). Vacío si el código no está en la lista.
String ciudadDe(String codigo) {
  final texto = aeropuertos[codigo.toUpperCase()];
  if (texto == null) return '';
  final partes = texto.split('•');
  final resto = (partes.length > 1 ? partes[1] : partes[0]).trim();
  return resto.split(',').first.trim();
}
