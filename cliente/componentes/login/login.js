// Componente de inicio de sesión: consume POST /api/auth/login (S2).
// opciones.urlAuth: URL base del servicio de autenticación.
// opciones.onSesion(email, respuesta): se llama al iniciar sesión con éxito.

function iniciarLogin(raiz, opciones = {}) {
  const urlAuth = opciones.urlAuth || "http://localhost:5002";
  const formulario = raiz.querySelector("#form-login");
  const alerta = raiz.querySelector(".alerta");
  const boton = raiz.querySelector("#login-enviar");
  const botonMostrar = raiz.querySelector(".mostrar-clave");

  botonMostrar.addEventListener("click", () => {
    const campo = raiz.querySelector("#login-password");
    const visible = campo.type === "text";
    campo.type = visible ? "password" : "text";
    botonMostrar.querySelector(".material-symbols-outlined").textContent = visible ? "visibility" : "visibility_off";
  });

  formulario.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    const email = formulario.email.value.trim();
    const password = formulario.password.value;

    if (!esEmailValido(email)) {
      mostrarAlerta(alerta, "error", "Por favor, ingresa una dirección de correo válida.");
      return;
    }
    if (!password) {
      mostrarAlerta(alerta, "error", "Ingresa tu contraseña.");
      return;
    }

    boton.disabled = true;
    try {
      const respuesta = await fetch(`${urlAuth}/api/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ email, password }),
      });
      const cuerpo = await respuesta.json().catch(() => null);

      if (respuesta.ok) {
        sessionStorage.setItem("aerovuelo_token", cuerpo.token);
        mostrarAlerta(alerta, "exito", "¡Sesión iniciada con éxito! Sincronizando tus reservas de vuelo...");
        if (opciones.onSesion) opciones.onSesion(email.toLowerCase(), cuerpo);
      } else {
        mostrarAlerta(alerta, "error", cuerpo?.mensaje || "No se pudo iniciar sesión.");
      }
    } catch {
      mostrarAlerta(alerta, "error", "No se pudo conectar con el servicio de autenticación. ¿Está levantado?");
    } finally {
      boton.disabled = false;
    }
  });
}
