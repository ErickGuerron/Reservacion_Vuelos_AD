import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/lotes.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/scroll_por_teclado.dart';
import 'cambiar_asiento_dialog.dart';
import 'factura_archivos.dart';
import 'factura_dialog.dart';
import 'tarjeta_lote.dart';

// Vista de Mis Reservas: GET /api/reservas (S5). Las reservas de una misma compra se muestran
// como un lote; cada lote trae el detalle de sus pasajeros, el cambio de asiento y la factura.
class MisReservasView extends StatefulWidget {
  const MisReservasView({super.key, required this.onIrALogin});

  final VoidCallback onIrALogin;

  @override
  State<MisReservasView> createState() => _MisReservasViewState();
}

// Detalles de vuelo ya consultados, compartidos entre aperturas de la vista. Vencen en pocos minutos
// para que un cambio de hora o precio del administrador llegue sin recargar la app.
const _vigenciaVuelo = Duration(minutes: 5);
final Map<int, ({Vuelo? vuelo, DateTime at})> _cacheVuelos = {};

class _MisReservasViewState extends State<MisReservasView> {
  List<Reserva> _reservas = const [];
  final Map<int, Vuelo?> _vuelos = {};
  String _filtro = 'todas';
  String _busqueda = '';
  String? _sincronizado;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    session.addListener(_alCambiarSesion);
    reservaCreadaVersion.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    session.removeListener(_alCambiarSesion);
    reservaCreadaVersion.removeListener(_cargar);
    super.dispose();
  }

  void _alCambiarSesion() {
    if (!session.activa) {
      setState(() => _reservas = const []);
    } else {
      _cargar();
    }
    if (mounted) setState(() {});
  }

  Future<void> _cargar() async {
    final token = session.token;
    if (token == null) {
      setState(() => _reservas = const []);
      return;
    }
    setState(() => _cargando = true);
    try {
      final reservas = await ReservasService.listar(token: token);
      await _cargarVuelos(reservas);
      if (!mounted) return;
      setState(() {
        _reservas = reservas;
        _sincronizado = _horaActual();
      });
    } on SesionExpirada catch (e) {
      session.cerrar();
      if (!mounted) return;
      setState(() => _reservas = const []);
      _toast(e.mensaje, error: true);
    } on ApiException catch (e) {
      _toast(e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Lazy: usa la caché compartida y pide a S3 solo los vuelos que faltan o ya vencieron.
  Future<void> _cargarVuelos(List<Reserva> reservas) async {
    final ahora = DateTime.now();
    final faltan = <int>{};
    for (final r in reservas) {
      final guardado = _cacheVuelos[r.vueloId];
      if (guardado != null && ahora.difference(guardado.at) < _vigenciaVuelo) {
        _vuelos[r.vueloId] = guardado.vuelo;
      } else {
        faltan.add(r.vueloId);
      }
    }
    await Future.wait(faltan.map((id) async {
      final vuelo = await VuelosService.obtener(id);
      _cacheVuelos[id] = (vuelo: vuelo, at: DateTime.now());
      _vuelos[id] = vuelo;
    }));
  }

  String _horaActual() {
    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(ahora.hour)}:${dos(ahora.minute)}:${dos(ahora.second)}';
  }

  void _toast(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.inverseSurface,
          content: Row(
            children: [
              Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: AppColors.inverseOnSurface, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(texto, style: AppTheme.bodySm(color: AppColors.inverseOnSurface))),
            ],
          ),
          duration: const Duration(milliseconds: 3500),
        ),
      );
  }

  Future<void> _cambiarAsiento(Reserva reserva) async {
    final token = session.token;
    if (token == null) return;
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => ScrollDialogo(child: CambiarAsientoDialog(reserva: reserva, token: token)),
    );
    if (nuevo == null) return;
    _toast('Asiento de ${reserva.pasajero} cambiado a $nuevo.');
    await _cargar();
  }

  Future<void> _cancelar(Reserva reserva) async {
    final confirmada = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pasajero'),
        content: Text('Se cancelará el asiento ${reserva.asiento ?? ''} de ${reserva.pasajero}. El asiento queda libre para otro pasajero.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Mantener')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmada != true) return;
    final token = session.token;
    if (token == null) return;
    try {
      await ReservasService.cancelar(id: reserva.id, token: token);
      _toast('Asiento de ${reserva.pasajero} cancelado.');
      await _cargar();
    } on ApiException catch (e) {
      _toast(e.mensaje, error: true);
    }
  }

  void _verFactura(GrupoReserva grupo) {
    final token = session.token;
    final loteId = grupo.loteId;
    if (token == null || loteId == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => ScrollDialogo(
        child: FacturaDialog(
          loteId: loteId,
          token: token,
          grupo: grupo,
          vuelo: _vuelos[grupo.vueloId],
          correo: session.email,
        ),
      ),
    );
  }

  // Descarga directa desde la tarjeta: pide la factura a S5 y guarda el XML tal cual o arma el PDF.
  Future<void> _descargar(GrupoReserva grupo, {required bool pdf}) async {
    final token = session.token;
    final loteId = grupo.loteId;
    if (token == null || loteId == null) return;
    try {
      final xml = await FacturasService.obtener(loteId: loteId, token: token);
      final factura = Factura.desde(xml);
      if (factura == null) {
        _toast('La factura recibida no tiene el formato esperado.', error: true);
        return;
      }
      if (pdf) {
        await guardarFacturaPdf(
          DatosFactura.desde(factura: factura, grupo: grupo, vuelo: _vuelos[grupo.vueloId], correo: session.email),
        );
      } else {
        await guardarFacturaXml(xml: xml, numero: factura.numero);
      }
      _toast('Factura ${factura.numero} descargada en ${pdf ? 'PDF' : 'XML'}.');
    } on SesionExpirada catch (e) {
      session.cerrar();
      if (!mounted) return;
      setState(() => _reservas = const []);
      _toast(e.mensaje, error: true);
    } on ApiException catch (e) {
      _toast(e.mensaje, error: true);
    } catch (_) {
      _toast('No se pudo descargar el archivo.', error: true);
    }
  }

  // Busca por número de reserva, ruta, asiento o nombre del pasajero.
  bool _coincide(GrupoReserva grupo) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    final vuelo = _vuelos[grupo.vueloId];
    final texto = [
      '${grupo.loteId ?? grupo.reservas.first.id}',
      vuelo?.origen ?? '',
      vuelo?.destino ?? '',
      ...grupo.asientos,
      ...grupo.reservas.map((r) => r.pasajero),
    ].join(' ').toLowerCase();
    return texto.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile;
    final grupos = agruparPorLote(_reservas);
    final visibles = grupos
        .where((g) => (_filtro == 'todas' || (_filtro == 'confirmada' ? g.confirmada : !g.confirmada)) && _coincide(g))
        .toList();
    final confirmados = grupos.where((g) => g.confirmada).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Encabezado(sincronizado: _sincronizado, cargando: _cargando, onActualizar: _cargar),
          const SizedBox(height: AppSpacing.lg),
          if (!session.activa) ...[
            _Aviso(texto: 'Inicie sesión para ver sus reservas.', onAccion: widget.onIrALogin, accion: 'Iniciar sesión'),
            const SizedBox(height: AppSpacing.lg),
          ],
          _Resumen(confirmados: confirmados, canceladas: grupos.length - confirmados.length, vuelos: _vuelos),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Filtros(
                filtro: _filtro,
                total: grupos.length,
                confirmadas: confirmados.length,
                canceladas: grupos.length - confirmados.length,
                onCambiar: (f) => setState(() => _filtro = f),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (v) => setState(() => _busqueda = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por ruta o N.º de reserva',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!session.activa)
            const SizedBox.shrink()
          else if (_reservas.isEmpty)
            _Mensaje('Todavía no tiene reservas.')
          else if (visibles.isEmpty)
            _Mensaje('No hay reservas con ese filtro.')
          else
            LayoutBuilder(
              builder: (context, restricciones) {
                final columnas = restricciones.maxWidth >= 1000 ? 3 : (restricciones.maxWidth >= 640 ? 2 : 1);
                return _Filas(
                  columnas: columnas,
                  hijos: [
                    for (final grupo in visibles)
                      TarjetaLote(
                        grupo: grupo,
                        vuelo: _vuelos[grupo.vueloId],
                        onCambiarAsiento: _cambiarAsiento,
                        onCancelar: _cancelar,
                        onVerFactura: () => _verFactura(grupo),
                        onDescargarPdf: () => _descargar(grupo, pdf: true),
                        onDescargarXml: () => _descargar(grupo, pdf: false),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// Cuadrícula de celdas del mismo ancho y, dentro de cada fila, del mismo alto. Las celdas que faltan en la
// última fila quedan vacías para que las tarjetas conserven el mismo tamaño en todas las filas.
class _Filas extends StatelessWidget {
  const _Filas({required this.hijos, required this.columnas, this.separacion = AppSpacing.lg});

  final List<Widget> hijos;
  final int columnas;
  final double separacion;

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];
    for (var i = 0; i < hijos.length; i += columnas) {
      final fin = i + columnas > hijos.length ? hijos.length : i + columnas;
      final fila = hijos.sublist(i, fin);
      filas.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columnas; j++) ...[
                if (j > 0) SizedBox(width: separacion),
                Expanded(child: j < fila.length ? fila[j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
      if (fin < hijos.length) filas.add(SizedBox(height: separacion));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filas);
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant));
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.sincronizado, required this.cargando, required this.onActualizar});

  final String? sincronizado;
  final bool cargando;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mis reservas', style: AppTheme.headlineLg()),
            const SizedBox(height: 4),
            Text(
              'Asientos, pasajeros y facturas de cada compra.',
              style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (sincronizado != null)
              Text('Actualizado $sincronizado', style: AppTheme.telemetry(size: 11, color: AppColors.onSurfaceVariant)),
            FilledButton.icon(
              onPressed: cargando ? null : onActualizar,
              icon: cargando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, size: 18),
              label: const Text('Actualizar'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.onAccion, this.accion});

  final String texto;
  final VoidCallback? onAccion;
  final String? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(texto, style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant)),
          if (onAccion != null && accion != null) FilledButton(onPressed: onAccion, child: Text(accion!)),
        ],
      ),
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.filtro,
    required this.total,
    required this.confirmadas,
    required this.canceladas,
    required this.onCambiar,
  });

  final String filtro;
  final int total;
  final int confirmadas;
  final int canceladas;
  final ValueChanged<String> onCambiar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Chip(texto: 'Todas', contador: total, activo: filtro == 'todas', onTap: () => onCambiar('todas')),
        _Chip(texto: 'Confirmadas', contador: confirmadas, activo: filtro == 'confirmada', onTap: () => onCambiar('confirmada')),
        _Chip(texto: 'Canceladas', contador: canceladas, activo: filtro == 'cancelada', onTap: () => onCambiar('cancelada')),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.contador, required this.activo, required this.onTap});

  final String texto;
  final int contador;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$texto · $contador'),
      selected: activo,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryContainer,
      labelStyle: AppTheme.labelMd(color: activo ? AppColors.onPrimary : AppColors.onSurfaceVariant),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.confirmados, required this.canceladas, required this.vuelos});

  final List<GrupoReserva> confirmados;
  final int canceladas;
  final Map<int, Vuelo?> vuelos;

  @override
  Widget build(BuildContext context) {
    final monto = confirmados.fold<double>(0, (suma, g) => suma + g.totalConIva);
    final pasajeros = confirmados.fold<int>(0, (suma, g) => suma + g.confirmadas.length);
    final proximos = confirmados.map((g) => vuelos[g.vueloId]).whereType<Vuelo>().toList()
      ..sort((a, b) => '${a.fecha} ${a.hora}'.compareTo('${b.fecha} ${b.hora}'));
    final proximo = proximos.isEmpty ? null : proximos.first;

    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = restricciones.maxWidth >= 960 ? 4 : (restricciones.maxWidth >= 520 ? 2 : 1);
        return _Filas(
          columnas: columnas,
          separacion: AppSpacing.md,
          hijos: [
            _Indicador(
              titulo: 'Próximo vuelo',
              valor: proximo == null ? '—' : '${proximo.origen} → ${proximo.destino}',
              detalle: proximo == null ? 'Sin vuelos próximos' : '${proximo.fecha} · ${proximo.hora} h',
              oscuro: true,
            ),
            _Indicador(
              titulo: 'Compras confirmadas',
              valor: '${confirmados.length}',
              detalle: '$canceladas cancelada${canceladas == 1 ? '' : 's'}',
            ),
            _Indicador(titulo: 'Pasajeros', valor: '$pasajeros', detalle: 'en compras confirmadas'),
            _Indicador(titulo: 'Monto total', valor: '\$${monto.toStringAsFixed(2)}', detalle: 'IVA $ivaPorcentaje % incluido'),
          ],
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.titulo, required this.valor, required this.detalle, this.oscuro = false});

  final String titulo;
  final String valor;
  final String detalle;
  final bool oscuro;

  @override
  Widget build(BuildContext context) {
    final fondo = oscuro ? AppColors.slate900 : AppColors.surfaceContainerLowest;
    final texto = oscuro ? Colors.white : AppColors.onSurface;
    final suave = oscuro ? AppColors.slate300 : AppColors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
        border: oscuro ? null : Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo.toUpperCase(), style: AppTheme.labelSm(color: suave)),
          const SizedBox(height: 4),
          Text(valor, style: AppTheme.headlineMd(color: texto).copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
          Text(detalle, style: AppTheme.bodySm(color: suave), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
