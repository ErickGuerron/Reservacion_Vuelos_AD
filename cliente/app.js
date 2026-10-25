// Shell de la aplicación: enrutado por hash, cabecera con estado de sesión y montaje de componentes.
// Cada ruta carga un componente de cliente/componentes/ con cargarComponente (cargador.js).

const URLS = {
  usuarios: "http://localhost:5001",
  autenticacion: "http://localhost:5002",
  vuelos: "http://localhost:5003",
  reservas: "http://localhost:5004",
  gestion: "http://localhost:5005",
};

const CLAVE_SESION = "aerovuelo_token";
const RUTA_INICIAL = "vuelos";

// tipo "componente": se carga tal cual. tipo "acceso": se arma la tarjeta de login o registro.
const RUTAS = {
  vuelos: { tipo: "componente", componente: "vuelos", opciones: { urlVuelos: URLS.vuelos, urlReservas: URLS.reservas } },
  reservas: { tipo: "componente", componente: "mis-reservas", opciones: { urlGestion: URLS.gestion, urlVuelos: URLS.vuelos } },
  consola: { tipo: "componente", componente: "consola-api", opciones: {} },
  login: { tipo: "acceso" },
  registro: { tipo: "acceso" },
};

const vistaPrincipal = document.getElementById("vista");

function emailDeSesion() {
  const token = sessionStorage.getItem(CLAVE_SESION);
  if (!token) return null;
  try {
    const base64 = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(base64)).sub || null;
  } catch {
    return null;
  }
}

function rutaActual() {
  const nombre = location.hash.replace("#", "");
  return RUTAS[nombre] ? nombre : RUTA_INICIAL;
}

function marcarNavegacion(ruta) {
  for (const enlace of document.querySelectorAll(".enlace-ruta")) {
    const activo = enlace.dataset.ruta === ruta;
    enlace.classList.toggle("bg-surface-container-high", activo);
    enlace.classList.toggle("text-on-surface", activo);
    enlace.classList.toggle("font-semibold", activo);
    enlace.classList.toggle("shadow-sm", activo);
    enlace.classList.toggle("text-on-surface-variant", !activo);
    if (activo) enlace.setAttribute("aria-current", "page");
    else enlace.removeAttribute("aria-current");
  }
}

// ----- Cabecera -----

function actualizarCabecera() {
  const email = emailDeSesion();
  document.getElementById("sesion-texto").textContent = email ? email : "Sin sesión";
  document.getElementById("cerrar-sesion").classList.toggle("hidden", !email);
  document.getElementById("cerrar-sesion").classList.toggle("flex", !!email);
  document.getElementById("ir-login-movil").classList.toggle("hidden", !!email);
  actualizarContadorReservas();
}

async function actualizarContadorReservas() {
  const contador = document.getElementById("contador-reservas");
  const token = sessionStorage.getItem(CLAVE_SESION);
  const ocultar = () => contador.classList.add("hidden");
  if (!token) return ocultar();
  try {
    const respuesta = await fetch(`${URLS.gestion}/api/reservas`, {
      headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    });
    if (!respuesta.ok) return ocultar();
    const confirmadas = (await respuesta.json()).filter((r) => r.estado === "confirmada").length;
    contador.textContent = confirmadas;
    contador.classList.toggle("hidden", confirmadas === 0);
  } catch {
    ocultar();
  }
}

document.getElementById("cerrar-sesion").addEventListener("click", (evento) => {
  evento.preventDefault();
  sessionStorage.removeItem(CLAVE_SESION);
  actualizarCabecera();
  location.hash = "#login";
});

// ----- Vistas -----

async function mostrarVista() {
  const ruta = rutaActual();
  const configuracion = RUTAS[ruta];
  marcarNavegacion(ruta);
  try {
    if (configuracion.tipo === "acceso") {
      await montarAcceso(ruta);
    } else {
      await cargarComponente(configuracion.componente, vistaPrincipal, configuracion.opciones);
    }
  } catch (error) {
    vistaPrincipal.replaceChildren();
    const aviso = document.createElement("p");
    aviso.className = "p-margin text-error";
    aviso.textContent = error.message;
    vistaPrincipal.append(aviso);
  }
}

// Login y registro comparten la tarjeta: panel de marca, pestañas y el formulario de la ruta.
async function montarAcceso(vista) {
  await cargarComponente("vista-acceso", vistaPrincipal);
  await cargarComponente("panel-hero", document.getElementById("acceso-hero"));
  await cargarComponente("pestanas", document.getElementById("acceso-pestanas"), { activa: vista });
  await cargarComponente(vista, document.getElementById("acceso-formulario"), {
    urlAuth: URLS.autenticacion,
    urlUsuarios: URLS.usuarios,
    onSesion: () => {
      actualizarCabecera();
      location.hash = "#reservas";
    },
    onRegistrado: () => {},
  });
}

// Las pestañas de login y registro avisan con este evento; aquí se traduce a navegación.
document.addEventListener("vista:cambiar", (evento) => {
  location.hash = `#${evento.detail.vista}`;
});

// Una reserva creada desde Explorar Vuelos actualiza el contador de Mis Reservas.
document.addEventListener("reserva:creada", () => actualizarContadorReservas());

window.addEventListener("hashchange", mostrarVista);

if (!location.hash) history.replaceState(null, "", `#${RUTA_INICIAL}`);
actualizarCabecera();
mostrarVista();
