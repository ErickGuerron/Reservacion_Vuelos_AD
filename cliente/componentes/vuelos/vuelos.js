// Vista de vuelos: consume GET /api/vuelos (S3) y abre el modal de reserva (S4).
// opciones.urlVuelos y opciones.urlReservas: URL base de cada servicio.

const CIUDADES = { UIO: "Quito", GYE: "Guayaquil", MAD: "Madrid" };
const UMBRAL_ULTIMOS_CUPOS = 15; // criterio de la interfaz para resaltar pocos asientos

function el(etiqueta, clase, texto) {
  const nodo = document.createElement(etiqueta);
  if (clase) nodo.className = clase;
  if (texto !== undefined) nodo.textContent = texto;
  return nodo;
}

function insigniaEstado(vuelo) {
  if (vuelo.asientosDisponibles === 0) {
    return el("span", "inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-error-container text-on-error-container font-telemetry-code text-telemetry-code font-bold", "AGOTADO");
  }
  if (vuelo.asientosDisponibles <= UMBRAL_ULTIMOS_CUPOS) {
    return el("span", "inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-tertiary-fixed text-on-tertiary-fixed font-telemetry-code text-telemetry-code font-bold", "ÚLTIMOS CUPOS");
  }
  return el("span", "inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-surface-container-low text-secondary font-telemetry-code text-telemetry-code font-bold", "DISPONIBLE");
}

function iniciarVuelos(raiz, opciones = {}) {
  const urlVuelos = opciones.urlVuelos || "http://localhost:5003";
  const urlReservas = opciones.urlReservas || "http://localhost:5004";
  const formulario = raiz.querySelector("#form-buscar");
  const contador = raiz.querySelector("#contador-vuelos");
  const alerta = raiz.querySelector(".alerta");
  const listaTarjetas = raiz.querySelector("#lista-tarjetas");
  const listaTabla = raiz.querySelector("#lista-tabla");
  const cuerpoTabla = raiz.querySelector("#tabla-vuelos");

  // Carga los componentes anidados.
  cargarComponente("hub-estaciones", raiz.querySelector("#slot-hub")).catch(console.error);
  cargarComponente("modal-reserva", raiz.querySelector("#slot-modal"), { urlReservas }).catch(console.error);

  raiz.querySelector("#boton-intercambiar").addEventListener("click", () => {
    const origen = formulario.origen;
    const destino = formulario.destino;
    if (destino.value === "ALL") return; // "Todos los destinos" no tiene par inverso
    [origen.value, destino.value] = [destino.value, origen.value];
  });

  for (const boton of raiz.querySelectorAll("[data-vista-lista]")) {
    boton.addEventListener("click", () => cambiarVistaLista(boton.dataset.vistaLista));
  }

  formulario.addEventListener("submit", (evento) => {
    evento.preventDefault();
    buscar();
  });

  function cambiarVistaLista(vista) {
    const tarjetas = vista === "tarjetas";
    listaTarjetas.classList.toggle("hidden", !tarjetas);
    listaTabla.classList.toggle("hidden", tarjetas);
    for (const boton of raiz.querySelectorAll("[data-vista-lista]")) {
      boton.setAttribute("aria-pressed", String(boton.dataset.vistaLista === vista));
    }
  }

  async function buscar() {
    const parametros = new URLSearchParams({ origen: formulario.origen.value });
    if (formulario.destino.value !== "ALL") parametros.set("destino", formulario.destino.value);
    if (formulario.fecha.value) parametros.set("fecha", formulario.fecha.value);

    contador.textContent = "Consultando el servicio S3...";
    try {
      const respuesta = await fetch(`${urlVuelos}/api/vuelos?${parametros}`, { headers: { Accept: "application/json" } });
      const cuerpo = await respuesta.json().catch(() => null);
      if (!respuesta.ok) {
        contador.textContent = "No se pudo consultar los vuelos.";
        mostrarAlerta(alerta, "error", cuerpo?.mensaje || "No se pudo consultar los vuelos.");
        pintar([]);
        return;
      }
      alerta.classList.add("hidden");
      pintar(cuerpo);
    } catch {
      contador.textContent = "Servicio de vuelos no disponible.";
      mostrarAlerta(alerta, "error", "No se pudo conectar con el servicio de vuelos. ¿Está levantado en :5003?");
      pintar([]);
    }
  }

  function pintar(vuelos) {
    listaTarjetas.replaceChildren();
    cuerpoTabla.replaceChildren();
    raiz.querySelector("#telemetria-rutas").textContent = `${new Set(vuelos.map((v) => `${v.origen}-${v.destino}`)).size} Rutas`;

    const texto = vuelos.length === 1 ? "vuelo encontrado" : "vuelos encontrados";
    contador.textContent = `${vuelos.length} ${texto}`;

    if (vuelos.length === 0) {
      listaTarjetas.append(el("p", "vacio text-on-surface-variant", "No hay vuelos con esos filtros."));
      cuerpoTabla.append(crearFilaVacia());
      return;
    }
    for (const vuelo of vuelos) {
      listaTarjetas.append(crearTarjeta(vuelo));
      cuerpoTabla.append(crearFila(vuelo));
    }
  }

  function crearFilaVacia() {
    const fila = el("tr");
    const celda = el("td", "py-space-md px-space-md text-on-surface-variant", "No hay vuelos con esos filtros.");
    celda.colSpan = 6;
    fila.append(celda);
    return fila;
  }

  function crearTarjeta(vuelo) {
    const agotado = vuelo.asientosDisponibles === 0;
    const tarjeta = el("article", "boleto w-full bg-surface-container-lowest rounded-xl shadow-md hover:shadow-xl transition-all flex flex-col lg:flex-row overflow-hidden");
    tarjeta.dataset.agotado = String(agotado);

    const cuerpo = el("div", "flex-1 p-space-lg flex flex-col justify-between");
    const cabecera = el("div", "flex flex-wrap items-center justify-between gap-space-sm mb-space-md");
    const grupo = el("div", "flex items-center gap-space-sm");
    grupo.append(el("span", "px-2 py-0.5 rounded-full bg-surface-container-high font-telemetry-code text-[11px] font-bold text-on-surface", `VUELO #${vuelo.id}`), insigniaEstado(vuelo));
    cabecera.append(grupo);

    const ruta = el("div", "grid grid-cols-1 md:grid-cols-12 gap-space-md items-center py-space-sm");
    ruta.append(
      bloqueCiudad(vuelo.origen, "md:col-span-4"),
      bloqueTrayecto(vuelo.fecha),
      bloqueCiudad(vuelo.destino, "md:col-span-4 text-left md:text-right"),
    );

    const disponibilidad = el(
      "div",
      "mt-space-md pt-space-sm bg-surface-container-low p-space-sm rounded-lg flex items-center gap-space-sm",
      agotado ? "Sin asientos disponibles" : `${vuelo.asientosDisponibles} asientos disponibles`,
    );
    cuerpo.append(cabecera, ruta, disponibilidad);

    const lateral = el("div", "relative bg-surface-container-low lg:w-72 p-space-lg flex flex-col justify-between items-center text-center");
    const precio = el("div", "w-full flex flex-col items-center");
    precio.append(
      el("span", "font-label-sm text-label-sm uppercase tracking-widest text-on-surface-variant", "Tarifa por pasajero"),
      el("span", "font-headline-xl text-headline-xl font-extrabold text-on-surface", `$${vuelo.precio.toFixed(2)}`),
      el("span", "font-telemetry-code text-[11px] text-on-surface-variant", "USD"),
    );

    const boton = el("button", "boton-reservar w-full py-2.5 rounded-lg bg-primary hover:bg-on-surface-variant text-on-primary font-label-lg text-label-lg font-bold shadow-md transition-all active:scale-95", agotado ? "Agotado" : "Reservar vuelo");
    boton.type = "button";
    boton.disabled = agotado;
    boton.addEventListener("click", () => reservar(vuelo));

    lateral.append(precio, boton);
    tarjeta.append(cuerpo, lateral);
    return tarjeta;
  }

  // Trayecto en SVG: el viewBox fijo escala de forma uniforme, así que no se deforma.
  function bloqueTrayecto(fecha) {
    const bloque = el("div", "md:col-span-4 flex flex-col items-center gap-2");
    const contenedor = el("div", "w-full text-secondary");
    contenedor.innerHTML = `
      <svg viewBox="0 0 320 64" class="w-full h-16" role="img" aria-label="Trayecto directo">
        <line x1="16" y1="32" x2="304" y2="32" stroke="currentColor" stroke-width="2" stroke-dasharray="6 6" opacity="0.5"></line>
        <circle cx="16" cy="32" r="6" fill="currentColor"></circle>
        <circle cx="304" cy="32" r="6" fill="currentColor"></circle>
        <g transform="translate(160 32)">
          <circle r="17" fill="#ffffff" stroke="currentColor" stroke-width="1.5"></circle>
          <path transform="translate(-9 -9) scale(0.75)" fill="currentColor" d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z"></path>
        </g>
      </svg>`;
    bloque.append(contenedor, el("span", "font-body-md text-body-md font-semibold text-on-surface-variant", `Salida ${fecha}`));
    return bloque;
  }

  function bloqueCiudad(codigo, clase) {
    const bloque = el("div", clase);
    bloque.append(
      el("span", "font-headline-lg text-headline-lg font-extrabold text-on-surface tracking-tight", codigo),
      el("p", "font-body-sm text-body-sm font-semibold text-on-surface", CIUDADES[codigo] || codigo),
    );
    return bloque;
  }

  function crearFila(vuelo) {
    const agotado = vuelo.asientosDisponibles === 0;
    const fila = el("tr", "hover:bg-surface-container-low transition-colors");
    const ruta = el("td", "py-space-md px-space-md font-bold", `${vuelo.origen} → ${vuelo.destino}`);
    const boton = el("button", "px-3 py-1.5 rounded-lg bg-primary hover:bg-on-surface-variant text-on-primary font-label-md text-label-md font-semibold", agotado ? "Sin cupo" : "Reservar");
    boton.type = "button";
    boton.disabled = agotado;
    boton.addEventListener("click", () => reservar(vuelo));

    const celdaAccion = el("td", "py-space-md px-space-md text-right");
    celdaAccion.append(boton);
    fila.append(
      el("td", "py-space-md px-space-md font-telemetry-code font-bold", `#${vuelo.id}`),
      ruta,
      el("td", "py-space-md px-space-md font-telemetry-code", vuelo.fecha),
      el("td", "py-space-md px-space-md font-bold", `$${vuelo.precio.toFixed(2)}`),
      el("td", "py-space-md px-space-md", `${vuelo.asientosDisponibles} libres`),
      celdaAccion,
    );
    return fila;
  }

  function reservar(vuelo) {
    const token = sessionStorage.getItem("aerovuelo_token");
    if (!token) {
      mostrarAlerta(alerta, "aviso", "Inicie sesión para reservar un vuelo.");
      document.dispatchEvent(new CustomEvent("vista:cambiar", { detail: { vista: "login" } }));
      return;
    }
    const pasajero = raiz.querySelector("#pasajero").value.trim();
    if (!pasajero) {
      mostrarAlerta(alerta, "aviso", "Ingresa el nombre del titular del pasaje antes de reservar.");
      raiz.querySelector("#pasajero").focus();
      return;
    }
    window.abrirModalReserva(vuelo, { urlReservas, token, pasajero });
  }

  buscar();
}
