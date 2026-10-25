// Consola de auditoría: muestra los intercambios HTTP reales del cliente (window.registroHttp)
// y el estado de cada servicio con un sondeo real a GET /openapi.json.

const SERVICIOS_CONSOLA = [
  { clave: "5001", nombre: "Registro de usuarios", codigo: "S1", url: "http://localhost:5001" },
  { clave: "5002", nombre: "Autenticación", codigo: "S2", url: "http://localhost:5002" },
  { clave: "5003", nombre: "Consulta de vuelos", codigo: "S3", url: "http://localhost:5003" },
  { clave: "5004", nombre: "Reserva de vuelos", codigo: "S4", url: "http://localhost:5004" },
  { clave: "5005", nombre: "Gestión de reservas", codigo: "S5", url: "http://localhost:5005" },
];

function claveDeServicio(url) {
  const coincidencia = url.match(/:(\d{4})\//);
  return coincidencia ? coincidencia[1] : null;
}

function claveDeIntercambio(evento) {
  return `${evento.fecha}|${evento.metodo}|${evento.url}`;
}

function iniciarConsolaApi(raiz) {
  const feed = raiz.querySelector("#feed");
  const malla = raiz.querySelector("#malla-servicios");
  const botonPausa = raiz.querySelector("#boton-pausa");
  const estadoCaptura = raiz.querySelector("#estado-captura");
  const intercambiosAbiertos = new Set();
  let filtro = "todos";
  let enPausa = false;

  // ----- Malla de servicios -----

  for (const servicio of SERVICIOS_CONSOLA) {
    const tarjeta = document.createElement("div");
    tarjeta.className = "relative bg-surface-container-lowest p-space-md rounded-xl shadow-sm flex flex-col justify-between overflow-hidden";
    tarjeta.dataset.clave = servicio.clave;
    tarjeta.innerHTML = `
      <div class="barra-estado absolute top-0 left-0 right-0 h-1 bg-outline-variant"></div>
      <div class="flex items-start justify-between mb-2">
        <div>
          <span class="font-telemetry-code text-headline-sm font-bold text-on-surface">${servicio.codigo}</span>
          <span class="block font-label-md text-label-md text-on-surface-variant">${servicio.nombre}</span>
        </div>
        <span class="px-2 py-0.5 rounded-full bg-surface-container-high text-on-surface font-telemetry-code text-[11px] font-bold">:${servicio.clave}</span>
      </div>
      <div class="flex items-center justify-between pt-2 mt-2 bg-surface-container-low -mx-space-md -mb-space-md p-space-sm">
        <span class="estado font-telemetry-code text-[11px] text-on-surface-variant">Sin verificar</span>
        <span class="tiempo font-telemetry-code text-[10px] text-on-surface-variant"></span>
      </div>`;
    malla.append(tarjeta);
  }

  async function verificarServicios() {
    for (const servicio of SERVICIOS_CONSOLA) {
      const tarjeta = malla.querySelector(`[data-clave="${servicio.clave}"]`);
      const inicio = performance.now();
      try {
        const respuesta = await fetch(`${servicio.url}/openapi.json`, { headers: { Accept: "application/json" } });
        const ms = Math.round(performance.now() - inicio);
        pintarEstado(tarjeta, respuesta.ok ? "ACTIVO" : `HTTP ${respuesta.status}`, respuesta.ok, ms);
      } catch {
        pintarEstado(tarjeta, "SIN RESPUESTA", false, null);
      }
    }
  }

  function pintarEstado(tarjeta, texto, activo, ms) {
    tarjeta.querySelector(".estado").textContent = texto;
    tarjeta.querySelector(".estado").className = "estado font-telemetry-code text-[11px] font-semibold " + (activo ? "text-secondary" : "text-error");
    tarjeta.querySelector(".tiempo").textContent = ms === null ? "" : `${ms} ms`;
    tarjeta.querySelector(".barra-estado").className = "barra-estado absolute top-0 left-0 right-0 h-1 " + (activo ? "bg-secondary" : "bg-error");
  }

  // ----- Terminal -----

  function crearIntercambio(evento) {
    const clave = claveDeIntercambio(evento);
    const conError = evento.status === 0 || evento.status >= 400;
    const detalle = document.createElement("details");
    detalle.className = "intercambio bg-primary/60 rounded-xl overflow-hidden";
    detalle.dataset.error = String(conError);
    detalle.open = intercambiosAbiertos.has(clave);
    detalle.addEventListener("toggle", () => {
      if (detalle.open) intercambiosAbiertos.add(clave);
      else intercambiosAbiertos.delete(clave);
    });

    const insignia = evento.status === 0
      ? "SIN CONEXIÓN"
      : `${evento.status} ${evento.status < 300 ? "OK" : evento.status < 400 ? "REDIRECCIÓN" : "ERROR"}`;
    const colorInsignia = conError ? "bg-error-container text-on-error-container" : "bg-secondary text-on-secondary";

    const resumen = document.createElement("summary");
    resumen.className = "resumen flex flex-wrap items-center justify-between gap-space-sm p-space-md bg-primary-container/80 cursor-pointer list-none";
    resumen.innerHTML = `
      <div class="flex flex-wrap items-center gap-2 min-w-0">
        <span class="insignia px-2.5 py-1 rounded font-telemetry-code text-label-sm font-bold ${colorInsignia}"></span>
        <span class="metodo px-2 py-0.5 rounded bg-tertiary-fixed-dim text-on-tertiary-fixed font-telemetry-code text-label-sm font-bold"></span>
        <span class="url font-telemetry-code text-body-sm text-surface-bright font-semibold break-all"></span>
      </div>
      <div class="flex items-center gap-space-md font-telemetry-code text-telemetry-code text-on-primary-container">
        <span class="duracion"></span>
        <span class="fecha"></span>
        <button class="copiar p-1 text-on-primary-container hover:text-on-primary transition-colors" title="Copiar este intercambio" type="button">
          <span class="material-symbols-outlined text-[16px]">copy_all</span>
        </button>
        <span class="flecha material-symbols-outlined text-[18px]">expand_more</span>
      </div>`;
    resumen.querySelector(".insignia").textContent = insignia;
    resumen.querySelector(".metodo").textContent = evento.metodo;
    resumen.querySelector(".url").textContent = evento.url;
    resumen.querySelector(".duracion").textContent = `${evento.ms} ms`;
    resumen.querySelector(".fecha").textContent = new Date(evento.fecha).toLocaleTimeString("es-EC");

    // El botón de copiar no debe abrir ni cerrar el intercambio.
    const botonCopiar = resumen.querySelector(".copiar");
    botonCopiar.addEventListener("click", (clic) => {
      clic.preventDefault();
      clic.stopPropagation();
      navigator.clipboard.writeText(JSON.stringify(evento, null, 2)).then(() => notificar("Intercambio copiado", false));
    });

    const cuerpo = document.createElement("div");
    cuerpo.className = "p-space-md flex flex-col gap-space-md";
    cuerpo.append(
      bloque("Petición", evento.autorizacion ? { Authorization: evento.autorizacion, cuerpo: evento.peticion } : evento.peticion),
      bloque("Respuesta", evento.error ? { error: evento.error } : evento.respuesta),
    );

    detalle.append(resumen, cuerpo);
    return detalle;
  }

  function bloque(titulo, contenido) {
    const caja = document.createElement("div");
    const etiqueta = document.createElement("span");
    etiqueta.className = "font-telemetry-code text-[11px] uppercase tracking-wider text-on-primary-container";
    etiqueta.textContent = titulo;
    const pre = document.createElement("pre");
    pre.className = "mt-1 p-space-md rounded-lg bg-black/35 text-secondary-fixed font-telemetry-code text-[12px] leading-relaxed whitespace-pre-wrap break-words";
    pre.textContent = contenido === null || contenido === undefined ? "(sin cuerpo)" : JSON.stringify(contenido, null, 2);
    caja.append(etiqueta, pre);
    return caja;
  }

  function coincideConFiltro(evento) {
    return filtro === "todos" || claveDeServicio(evento.url) === filtro;
  }

  function pintarTerminal() {
    const registros = window.registroHttp.filter(coincideConFiltro).slice().reverse();
    feed.replaceChildren();
    if (registros.length === 0) {
      const vacio = document.createElement("p");
      vacio.className = "font-body-md text-on-primary-container";
      vacio.textContent = "Sin intercambios todavía. Use la vista de vuelos, reservas o el login para verlos aquí.";
      feed.append(vacio);
    } else {
      for (const evento of registros) feed.append(crearIntercambio(evento));
    }
    raiz.querySelector("#contador-registros").textContent = `${window.registroHttp.length} eventos`;
    pintarLatencia();
  }

  function pintarLatencia() {
    const validos = window.registroHttp.filter((e) => e.status !== 0);
    const promedio = validos.length ? Math.round(validos.reduce((s, e) => s + e.ms, 0) / validos.length) : null;
    raiz.querySelector("#latencia-promedio").textContent = promedio === null ? "—" : `${promedio} ms`;
  }

  // ----- Eventos -----

  document.addEventListener("http:intercambio", (evento) => {
    if (!raiz.isConnected || enPausa) return;
    const filtroActivo = filtro === "todos" || claveDeServicio(evento.detail.url) === filtro;
    if (filtroActivo) pintarTerminal();
    else pintarLatencia();
    raiz.querySelector("#contador-registros").textContent = `${window.registroHttp.length} eventos`;
  });

  for (const boton of raiz.querySelectorAll(".filtro")) {
    boton.addEventListener("click", () => {
      filtro = boton.dataset.filtro;
      for (const otro of raiz.querySelectorAll(".filtro")) {
        otro.setAttribute("aria-pressed", String(otro === boton));
      }
      pintarTerminal();
    });
  }

  botonPausa.addEventListener("click", () => {
    enPausa = !enPausa;
    botonPausa.querySelector("span:last-child").textContent = enPausa ? "En pausa" : "En vivo";
    botonPausa.querySelector("span:first-child").className = "w-2 h-2 rounded-full " + (enPausa ? "bg-outline" : "bg-secondary");
    estadoCaptura.textContent = enPausa ? "Captura en pausa" : "Captura activa";
    if (!enPausa) pintarTerminal();
    notificar(enPausa ? "Captura en pausa" : "Captura reanudada", false);
  });

  raiz.querySelector("#boton-limpiar").addEventListener("click", () => {
    window.registroHttp.length = 0;
    intercambiosAbiertos.clear();
    pintarTerminal();
    notificar("Consola vaciada", false);
  });

  raiz.querySelector("#boton-copiar").addEventListener("click", () => {
    const datos = JSON.stringify(window.registroHttp, null, 2);
    navigator.clipboard.writeText(datos).then(() => notificar("Registro completo copiado", false));
  });

  raiz.querySelector("#boton-verificar").addEventListener("click", verificarServicios);

  function notificar(texto, error) {
    const toast = raiz.querySelector("#toast");
    raiz.querySelector("#toast-texto").textContent = texto;
    raiz.querySelector("#toast-icono").textContent = error ? "error" : "check_circle";
    toast.classList.add("visible");
    clearTimeout(toast._temporizador);
    toast._temporizador = setTimeout(() => toast.classList.remove("visible"), 2500);
  }

  pintarTerminal();
  verificarServicios();
}
