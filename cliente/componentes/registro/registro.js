// Componente de registro: consume POST /api/usuarios (S1).
// opciones.urlUsuarios: URL base del servicio de usuarios.
// opciones.onRegistrado(email): se llama cuando el registro termina con éxito.

const MINIMO_NOMBRE = 4; // regla de la interfaz; el servicio exige al menos 1 carácter
const MINIMO_CLAVE = 8; // igual que el servicio de usuarios

function puntuarClave(clave) {
  let puntos = 0;
  if (clave.length >= MINIMO_CLAVE) puntos++;
  if (/[A-Z]/.test(clave)) puntos++;
  if (/[0-9]/.test(clave)) puntos++;
  if (/[^A-Za-z0-9]/.test(clave)) puntos++;
  return puntos;
}

function pintarMedidor(raiz, clave) {
  const etiqueta = raiz.querySelector(".etiqueta-seguridad");
  const barras = raiz.querySelectorAll(".barra");
  const puntos = puntuarClave(clave);
  // Niveles según puntos (0 a 4): cuántas barras se pintan y con qué color.
  const niveles = [
    { texto: "Baja", color: "text-slate-500", fondo: null, barras: 0 },
    { texto: "Moderada", color: "text-amber-600", fondo: "bg-amber-500", barras: 2 },
    { texto: "Buena", color: "text-sky-600", fondo: "bg-sky-500", barras: 3 },
    { texto: "Excelente", color: "text-emerald-600", fondo: "bg-emerald-500", barras: 4 },
  ];
  const nivel = puntos === 0 ? niveles[0] : puntos === 1 ? niveles[1] : niveles[Math.min(puntos, 4) - 1];

  etiqueta.textContent = nivel.texto;
  etiqueta.className = `etiqueta-seguridad font-semibold font-mono ${nivel.color}`;
  barras.forEach((barra, indice) => {
    barra.className = "barra h-full transition-all duration-300 " + (indice < nivel.barras ? nivel.fondo : "bg-slate-200");
  });
}

function iniciarRegistro(raiz, opciones = {}) {
  const urlUsuarios = opciones.urlUsuarios || "http://localhost:5001";
  const formulario = raiz.querySelector("#form-registro");
  const alerta = raiz.querySelector(".alerta");
  const boton = raiz.querySelector("#registro-enviar");
  const botonMostrar = raiz.querySelector(".mostrar-clave");

  formulario.password.addEventListener("input", () => pintarMedidor(raiz, formulario.password.value));

  botonMostrar.addEventListener("click", () => {
    const campo = formulario.password;
    const visible = campo.type === "text";
    campo.type = visible ? "password" : "text";
    botonMostrar.querySelector(".material-symbols-outlined").textContent = visible ? "visibility" : "visibility_off";
  });

  formulario.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    const nombre = formulario.nombre.value.trim();
    const email = formulario.email.value.trim();
    const password = formulario.password.value;

    if (nombre.length < MINIMO_NOMBRE) {
      mostrarAlerta(alerta, "error", "Ingresa tu nombre completo tal como figura en tu identificación.");
      return;
    }
    if (!esEmailValido(email)) {
      mostrarAlerta(alerta, "error", "Por favor, ingresa un correo electrónico válido.");
      return;
    }
    if (password.length < MINIMO_CLAVE) {
      mostrarAlerta(alerta, "aviso", `La contraseña debe tener al menos ${MINIMO_CLAVE} caracteres.`);
      return;
    }

    boton.disabled = true;
    try {
      const respuesta = await fetch(`${urlUsuarios}/api/usuarios`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ nombre, email, password }),
      });
      const cuerpo = await respuesta.json().catch(() => null);

      if (respuesta.status === 201) {
        mostrarAlerta(alerta, "exito", `¡Registro completado! Bienvenido a bordo, ${cuerpo.nombre}. Tu cuenta ya está activa.`);
        formulario.reset();
        pintarMedidor(raiz, "");
        if (opciones.onRegistrado) opciones.onRegistrado(cuerpo.email);
      } else {
        mostrarAlerta(alerta, respuesta.status === 400 ? "aviso" : "error", cuerpo?.mensaje || "No se pudo completar el registro.");
      }
    } catch {
      mostrarAlerta(alerta, "error", "No se pudo conectar con el servicio de usuarios. ¿Está levantado?");
    } finally {
      boton.disabled = false;
    }
  });
}
