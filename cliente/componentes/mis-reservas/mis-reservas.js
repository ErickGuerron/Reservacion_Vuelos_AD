// Vista de Mis Reservas: lista GET /api/reservas (S5), completa cada reserva con GET /api/vuelos/{id}
// (S3) y permite cancelar con DELETE /api/reservas/{id} (S5).
// opciones.urlGestion y opciones.urlVuelos: URL base de cada servicio.

const TOKEN_KEY = "aerovuelo_token";

function leerEmailDelToken(token) {
  try {
    const base64 = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(base64)).sub || "";
  } catch {
    return "";
  }
}

function iniciarMisReservas(raiz, opciones = {}) {
  const urlGestion = opciones.urlGestion || "http://localhost:5005";
  const urlVuelos = opciones.urlVuelos || "http://localhost:5003";
  const lista = raiz.querySelector("#lista-reservas");
  const modalCancelar = raiz.querySelector("#modal-cancelar");
  const modalJson = raiz.querySelector("#modal-json");

  let reservas = [];
  let vuelos = new Map();
  let filtro = "todas";
  let reservaPendiente = null;

  // ----- Eventos -----

  for (const boton of raiz.querySelectorAll(".filtro")) {
    boton.addEventListener("click", () => {
      filtro = boton.dataset.filtro;
      for (const otro of raiz.querySelectorAll(".filtro")) {
        otro.setAttribute("aria-pressed", String(otro === boton));
      }
      pintar();
    });
  }

  raiz.querySelector("#boton-actualizar").addEventListener("click", () => cargar());
  raiz.querySelector(".ir-login").addEventListener("click", () => irALogin());

  for (const cerrar of raiz.querySelectorAll(".cerrar")) {
    cerrar.addEventListener("click", () => {
      modalCancelar.classList.remove("abierto");
      modalJson.classList.remove("abierto");
    });
  }

  raiz.querySelector(".confirmar-cancelar").addEventListener("click", () => {
    if (reservaPendiente) cancelar(reservaPendiente);
  });

  raiz.querySelector(".copiar-json").addEventListener("click", () => {
    navigator.clipboard.writeText(raiz.querySelector("#json-contenido").textContent)
      .then(() => notificar("JSON copiado al portapapeles", "exito"));
  });

  // Al reservar desde Explorar Vuelos, la lista se actualiza sola.
  document.addEventListener("reserva:creada", () => {
    if (raiz.isConnected && sessionStorage.getItem(TOKEN_KEY)) cargar();
  });

  // ----- Sesión -----

  function irALogin() {
    document.dispatchEvent(new CustomEvent("vista:cambiar", { detail: { vista: "login" } }));
  }

  function pintarSesion() {
    const token = sessionStorage.getItem(TOKEN_KEY);
    raiz.querySelector(".banner-sesion").classList.toggle("hidden", !token);
    raiz.querySelector(".banner-invitado").classList.toggle("hidden", !!token);
    raiz.querySelector(".banner-invitado").classList.toggle("flex", !token);
    raiz.querySelector("#email-sesion").textContent = token ? leerEmailDelToken(token) : "";
    return !!token;
  }

  // ----- Carga -----

  async function cargar() {
    const token = sessionStorage.getItem(TOKEN_KEY);
    if (!pintarSesion()) {
      reservas = [];
      lista.replaceChildren(mensajeVacio("Inicie sesión para ver sus reservas."));
      pintarContadores();
      return;
    }

    const icono = raiz.querySelector("#icono-actualizar");
    icono.classList.add("icono-girando");
    try {
      const respuesta = await fetch(`${urlGestion}/api/reservas`, {
        headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
      });
      if (respuesta.status === 401) {
        sessionStorage.removeItem(TOKEN_KEY);
        pintarSesion();
        reservas = [];
        lista.replaceChildren(mensajeVacio("Su sesión expiró. Inicie sesión de nuevo."));
        pintarContadores();
        return;
      }
      const cuerpo = await respuesta.json().catch(() => null);
      if (!respuesta.ok) {
        notificar(cuerpo?.mensaje || "No se pudieron cargar las reservas.", "error");
        return;
      }
      reservas = cuerpo;
      await cargarVuelos();
      raiz.querySelector("#sync-hora").textContent = new Date().toLocaleTimeString("es-EC");
      pintar();
    } catch {
      notificar("No se pudo conectar con el servicio de gestión (:5005).", "error");
    } finally {
      icono.classList.remove("icono-girando");
    }
  }

  async function cargarVuelos() {
    const ids = [...new Set(reservas.map((r) => r.vueloId))];
    await Promise.all(ids.map(async (id) => {
      if (vuelos.has(id)) return;
      try {
        const respuesta = await fetch(`${urlVuelos}/api/vuelos/${id}`, { headers: { Accept: "application/json" } });
        vuelos.set(id, respuesta.ok ? await respuesta.json() : null);
      } catch {
        vuelos.set(id, null);
      }
    }));
  }

  // ----- Pintado -----

  function pintar() {
    const visibles = reservas.filter((r) => filtro === "todas" || r.estado === filtro);
    lista.replaceChildren();
    if (visibles.length === 0) {
      lista.append(mensajeVacio(reservas.length === 0 ? "Todavía no tiene reservas." : "No hay reservas con ese filtro."));
    } else {
      for (const reserva of visibles) lista.append(crearTarjeta(reserva));
    }
    pintarContadores();
  }

  function pintarContadores() {
    const total = reservas.length;
    const confirmadas = reservas.filter((r) => r.estado === "confirmada");
    const canceladas = reservas.filter((r) => r.estado === "cancelada");

    raiz.querySelector('[data-contador="todas"]').textContent = total;
    raiz.querySelector('[data-contador="confirmada"]').textContent = confirmadas.length;
    raiz.querySelector('[data-contador="cancelada"]').textContent = canceladas.length;
    raiz.querySelector("#total-registros").textContent = total;

    const monto = confirmadas.reduce((suma, r) => suma + (vuelos.get(r.vueloId)?.precio || 0), 0);
    raiz.querySelector("#resumen-confirmadas").textContent = confirmadas.length;
    raiz.querySelector("#resumen-monto").textContent = `$${monto.toFixed(2)}`;

    const proximas = confirmadas
      .map((r) => vuelos.get(r.vueloId))
      .filter(Boolean)
      .sort((a, b) => a.fecha.localeCompare(b.fecha));
    const proxima = proximas[0];
    raiz.querySelector("#resumen-proxima").textContent = proxima ? proxima.fecha : "—";
    raiz.querySelector("#resumen-proxima-ruta").textContent = proxima ? `Vuelo #${proxima.id}: ${proxima.origen} → ${proxima.destino}` : "";
  }

  function mensajeVacio(texto) {
    const p = document.createElement("p");
    p.className = "font-body-md text-on-surface-variant";
    p.textContent = texto;
    return p;
  }

  function crearTarjeta(reserva) {
    const vuelo = vuelos.get(reserva.vueloId);
    const confirmada = reserva.estado === "confirmada";
    const tarjeta = document.createElement("article");
    tarjeta.className = "reserva w-full bg-surface-container-lowest rounded-xl shadow-md border border-surface-variant overflow-hidden flex flex-col";
    tarjeta.dataset.estado = reserva.estado;

    const cabecera = el("div", "flex flex-col sm:flex-row sm:items-center justify-between gap-space-sm p-space-md md:px-space-lg bg-surface-container-low/60 border-b border-surface-variant");
    const titulo = el("div", "flex items-center gap-space-sm");
    titulo.append(
      el("span", "font-headline-sm text-headline-sm text-on-surface font-bold", `Reserva #${reserva.id}`),
      el("span", "font-telemetry-code text-[12px] text-secondary font-semibold", vuelo ? `Vuelo #${vuelo.id}` : `Vuelo #${reserva.vueloId} (no disponible)`),
    );
    const estado = el("span", "px-3 py-1 rounded-full font-telemetry-code text-telemetry-code font-bold " + (confirmada ? "bg-secondary-fixed text-on-secondary-fixed" : "bg-surface-container-high text-on-surface-variant"), confirmada ? "CONFIRMADA" : "CANCELADA");
    cabecera.append(titulo, estado);

    const cuerpo = el("div", "p-space-md md:p-space-lg flex flex-col gap-space-lg");
    if (vuelo) {
      cuerpo.append(bloqueRuta(vuelo));
    }

    const datos = el("div", "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-space-sm bg-surface-container-low rounded-xl p-space-md");
    datos.append(
      dato("Pasajero", reserva.pasajero),
      dato("Fecha", vuelo?.fecha || "—"),
      dato("Precio", vuelo ? `$${vuelo.precio.toFixed(2)} USD` : "—"),
      dato("Asientos disponibles", vuelo ? String(vuelo.asientosDisponibles) : "—"),
    );
    cuerpo.append(datos);

    const pie = el("div", "flex flex-col sm:flex-row items-center justify-between gap-space-sm pt-space-xs border-t border-surface-variant/60");
    pie.append(el("span", "font-telemetry-code text-[12px] text-on-surface-variant", `ID reserva: ${reserva.id} · ID vuelo: ${reserva.vueloId}`));

    const acciones = el("div", "flex items-center gap-space-sm w-full sm:w-auto");
    const botonJson = el("button", "flex-1 sm:flex-none py-2 px-space-md rounded-lg bg-surface-container-highest hover:bg-surface-variant text-on-surface font-label-md text-label-md transition-colors", "Ver JSON");
    botonJson.type = "button";
    botonJson.addEventListener("click", () => verJson(reserva));
    acciones.append(botonJson);

    if (confirmada) {
      const botonCancelar = el("button", "flex-1 sm:flex-none py-2 px-space-md rounded-lg bg-error-container hover:bg-error hover:text-on-error text-on-error-container font-label-md text-label-md transition-colors", "Cancelar reserva");
      botonCancelar.type = "button";
      botonCancelar.addEventListener("click", () => abrirCancelar(reserva, vuelo));
      acciones.append(botonCancelar);
    }
    pie.append(acciones);
    cuerpo.append(pie);

    tarjeta.append(cabecera, cuerpo);
    return tarjeta;
  }

  function bloqueRuta(vuelo) {
    const ruta = el("div", "grid grid-cols-1 md:grid-cols-12 gap-space-md items-center");
    const origen = el("div", "md:col-span-5 flex flex-col");
    origen.append(
      el("span", "font-telemetry-code text-telemetry-code text-on-surface-variant uppercase tracking-widest", "Origen"),
      el("span", "font-headline-xl text-headline-xl text-on-surface font-extrabold leading-none", vuelo.origen),
    );
    const destino = el("div", "md:col-span-5 flex flex-col md:text-right");
    destino.append(
      el("span", "font-telemetry-code text-telemetry-code text-on-surface-variant uppercase tracking-widest", "Destino"),
      el("span", "font-headline-xl text-headline-xl text-on-surface font-extrabold leading-none", vuelo.destino),
    );
    ruta.append(origen, el("div", "md:col-span-2 text-center font-telemetry-code text-secondary", "→"), destino);
    return ruta;
  }

  function dato(etiqueta, valor) {
    const bloque = el("div", "flex flex-col");
    bloque.append(
      el("span", "font-label-sm text-label-sm text-on-surface-variant uppercase", etiqueta),
      el("span", "font-headline-sm text-headline-sm text-on-surface font-bold truncate", valor),
    );
    return bloque;
  }

  function el(etiqueta, clase, texto) {
    const nodo = document.createElement(etiqueta);
    if (clase) nodo.className = clase;
    if (texto !== undefined) nodo.textContent = texto;
    return nodo;
  }

  // ----- Acciones -----

  function verJson(reserva) {
    const payload = { reserva, vuelo: vuelos.get(reserva.vueloId) || null };
    raiz.querySelector("#json-titulo").textContent = `Reserva #${reserva.id} · GET /api/reservas`;
    raiz.querySelector("#json-contenido").textContent = JSON.stringify(payload, null, 2);
    modalJson.classList.add("abierto");
  }

  function abrirCancelar(reserva, vuelo) {
    reservaPendiente = reserva;
    const ruta = vuelo ? `${vuelo.origen} → ${vuelo.destino}` : `vuelo #${reserva.vueloId}`;
    raiz.querySelector("#cancelar-texto").textContent = `#${reserva.id} (${ruta})`;
    modalCancelar.classList.add("abierto");
  }

  async function cancelar(reserva) {
    const token = sessionStorage.getItem(TOKEN_KEY);
    try {
      const respuesta = await fetch(`${urlGestion}/api/reservas/${reserva.id}`, {
        method: "DELETE",
        headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
      });
      const cuerpo = await respuesta.json().catch(() => null);
      modalCancelar.classList.remove("abierto");
      reservaPendiente = null;
      if (respuesta.ok) {
        notificar(`Reserva #${reserva.id} cancelada.`, "exito");
        await cargar();
      } else {
        notificar(cuerpo?.mensaje || "No se pudo cancelar la reserva.", "error");
      }
    } catch {
      modalCancelar.classList.remove("abierto");
      notificar("No se pudo conectar con el servicio de gestión (:5005).", "error");
    }
  }

  function notificar(texto, tipo) {
    const toast = raiz.querySelector("#toast");
    raiz.querySelector("#toast-texto").textContent = texto;
    raiz.querySelector("#toast-icono").textContent = tipo === "error" ? "error" : "check_circle";
    toast.classList.add("visible");
    clearTimeout(toast._temporizador);
    toast._temporizador = setTimeout(() => toast.classList.remove("visible"), 3500);
  }

  cargar();
}
