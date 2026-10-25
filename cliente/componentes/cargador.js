// Cargador de componentes para el index.html global.
//
// Cada componente vive en componentes/<nombre>/ con tres archivos del mismo nombre:
//   <nombre>.html  fragmento de marcado (sin <html> ni <body>)
//   <nombre>.css   estilos propios del componente
//   <nombre>.js    función iniciar<Nombre>(raiz, opciones) que conecta el componente
//
// Uso desde el index global:
//   await cargarComponente("login", contenedor, { urlAuth: "http://localhost:5002" });

const RUTA_COMPONENTES = "componentes";
const recursosCargados = new Set();

function nombreDeFuncionInicial(nombre) {
  return "iniciar" + nombre.charAt(0).toUpperCase() + nombre.slice(1).replace(/-(\w)/g, (_, c) => c.toUpperCase());
}

function cargarEstilo(href) {
  if (recursosCargados.has(href)) return;
  recursosCargados.add(href);
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  document.head.append(link);
}

function cargarScript(src) {
  if (recursosCargados.has(src)) return Promise.resolve();
  recursosCargados.add(src);
  return new Promise((resolver, rechazar) => {
    const script = document.createElement("script");
    script.src = src;
    script.onload = resolver;
    script.onerror = () => rechazar(new Error(`No se pudo cargar ${src}.`));
    document.body.append(script);
  });
}

async function cargarComponente(nombre, contenedor, opciones = {}) {
  const base = `${RUTA_COMPONENTES}/${nombre}/${nombre}`;
  cargarEstilo(`${base}.css`);

  const respuesta = await fetch(`${base}.html`);
  if (!respuesta.ok) {
    throw new Error(`No se pudo cargar el componente ${nombre} (HTTP ${respuesta.status}).`);
  }
  contenedor.innerHTML = await respuesta.text();

  await cargarScript(`${base}.js`);
  const iniciar = window[nombreDeFuncionInicial(nombre)];
  if (typeof iniciar === "function") iniciar(contenedor, opciones);
  return contenedor;
}

// Alerta con el estilo del diseño: "exito", "error" o "aviso".
function mostrarAlerta(elemento, tipo, texto) {
  const estilos = {
    exito: { caja: "bg-emerald-50 text-emerald-800 border-emerald-200", icono: "check_circle", color: "text-emerald-600" },
    error: { caja: "bg-rose-50 text-rose-800 border-rose-200", icono: "error", color: "text-rose-600" },
    aviso: { caja: "bg-amber-50 text-amber-800 border-amber-200", icono: "warning", color: "text-amber-600" },
  };
  const estilo = estilos[tipo] || estilos.aviso;
  const icono = elemento?.querySelector(".alerta-icono");
  const textoAlerta = elemento?.querySelector(".alerta-texto");
  if (!icono || !textoAlerta) {
    console.warn("Alerta sin estructura (.alerta-icono / .alerta-texto):", texto);
    return;
  }
  elemento.className = `mb-6 p-4 rounded-xl text-sm flex items-start gap-3 border ${estilo.caja}`;
  icono.className = `alerta-icono material-symbols-outlined text-[20px] mt-0.5 ${estilo.color}`;
  icono.textContent = estilo.icono;
  textoAlerta.textContent = texto;
}

function esEmailValido(valor) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(valor);
}

// ---------- Registro de intercambios HTTP (para la consola de auditoría) ----------
// Cada fetch de la aplicación queda en window.registroHttp y se anuncia con el evento "http:intercambio".
// Las contraseñas se ocultan y el token nunca se registra.

const MAXIMO_REGISTROS_HTTP = 200;

function ocultarSecretos(cuerpo) {
  if (cuerpo && typeof cuerpo === "object" && "password" in cuerpo) {
    return { ...cuerpo, password: "********" };
  }
  return cuerpo;
}

function leerJson(texto) {
  if (!texto) return null;
  try {
    return JSON.parse(texto);
  } catch {
    return texto;
  }
}

function registrarIntercambio(evento) {
  window.registroHttp.push(evento);
  if (window.registroHttp.length > MAXIMO_REGISTROS_HTTP) window.registroHttp.shift();
  document.dispatchEvent(new CustomEvent("http:intercambio", { detail: evento }));
}

if (!window.registroHttp) {
  window.registroHttp = [];
  const fetchOriginal = window.fetch.bind(window);

  window.fetch = async (entrada, init = {}) => {
    const url = typeof entrada === "string" ? entrada : entrada.url;
    const metodo = (init.method || "GET").toUpperCase();
    const cabeceras = new Headers(init.headers || {});
    const autorizacion = cabeceras.has("Authorization") ? "Bearer (oculto)" : null;
    const peticion = init.body ? ocultarSecretos(leerJson(init.body)) : null;
    const inicio = performance.now();

    try {
      const respuesta = await fetchOriginal(entrada, init);
      const texto = await respuesta.clone().text();
      registrarIntercambio({
        fecha: new Date().toISOString(),
        metodo,
        url,
        status: respuesta.status,
        ms: Math.round(performance.now() - inicio),
        autorizacion,
        peticion,
        respuesta: leerJson(texto),
        error: null,
      });
      return respuesta;
    } catch (error) {
      registrarIntercambio({
        fecha: new Date().toISOString(),
        metodo,
        url,
        status: 0,
        ms: Math.round(performance.now() - inicio),
        autorizacion,
        peticion,
        respuesta: null,
        error: "No se pudo establecer la conexión.",
      });
      throw error;
    }
  };
}
