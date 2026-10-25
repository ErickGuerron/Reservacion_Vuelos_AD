// Modal de confirmación de reserva: consume POST /api/reservas (S4).
// La vista de vuelos llama a window.abrirModalReserva(vuelo, { urlReservas, token, pasajero }).
// Al crear la reserva se emite el evento "reserva:creada" en document.

function iniciarModalReserva(raiz, opciones = {}) {
  const modal = raiz.querySelector("#modal-reserva");
  const boton = raiz.querySelector(".confirmar");
  const estadoEnvio = raiz.querySelector(".estado-envio");
  const resultadoOk = raiz.querySelector(".resultado-ok");
  const resultadoError = raiz.querySelector(".resultado-error");
  let reservaActiva = null;

  for (const cerrar of raiz.querySelectorAll(".cerrar")) {
    cerrar.addEventListener("click", () => modal.classList.add("hidden"));
  }

  function mostrarEstado(estado) {
    estadoEnvio.classList.toggle("hidden", estado !== "enviando");
    resultadoOk.classList.toggle("hidden", estado !== "ok");
    resultadoError.classList.toggle("hidden", estado !== "error");
    boton.classList.toggle("hidden", estado === "ok");
    boton.disabled = estado === "enviando";
  }

  window.abrirModalReserva = (vuelo, { urlReservas: url, token, pasajero }) => {
    reservaActiva = { vuelo, token, pasajero, url: url || opciones.urlReservas || "http://localhost:5004" };
    raiz.querySelector("#modal-pasajero").textContent = pasajero;
    raiz.querySelector("#modal-ruta").textContent = `${vuelo.origen} → ${vuelo.destino}`;
    raiz.querySelector("#modal-fecha").textContent = vuelo.fecha;
    raiz.querySelector("#modal-asientos").textContent = `${vuelo.asientosDisponibles}`;
    raiz.querySelector("#modal-precio").textContent = `$${vuelo.precio.toFixed(2)} USD`;
    mostrarEstado("inicial");
    modal.classList.remove("hidden");
  };

  boton.addEventListener("click", async () => {
    if (!reservaActiva) return;
    const { vuelo, token, pasajero, url } = reservaActiva;
    mostrarEstado("enviando");
    try {
      const respuesta = await fetch(`${url}/api/reservas`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ vueloId: vuelo.id, pasajero }),
      });
      const cuerpo = await respuesta.json().catch(() => null);

      if (respuesta.status === 201) {
        raiz.querySelector("#modal-reserva-id").textContent = `#${cuerpo.id}`;
        raiz.querySelector("#modal-estado").textContent = cuerpo.estado;
        mostrarEstado("ok");
        document.dispatchEvent(new CustomEvent("reserva:creada", { detail: cuerpo }));
      } else {
        raiz.querySelector(".texto-error").textContent = cuerpo?.mensaje || "No se pudo crear la reserva.";
        mostrarEstado("error");
      }
    } catch {
      raiz.querySelector(".texto-error").textContent = "No se pudo conectar con el servicio de reservas (:5004).";
      mostrarEstado("error");
    }
  });
}
