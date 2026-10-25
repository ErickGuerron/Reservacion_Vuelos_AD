// Pestañas Iniciar Sesión / Crear Cuenta.
// No cambia la vista por sí mismo: avisa al index global con el evento "vista:cambiar".

function iniciarPestanas(raiz, opciones = {}) {
  const pestanas = raiz.querySelectorAll(".pestana");

  function marcar(vista) {
    for (const pestana of pestanas) {
      pestana.setAttribute("aria-selected", String(pestana.dataset.vista === vista));
    }
  }

  for (const pestana of pestanas) {
    pestana.addEventListener("click", () => {
      marcar(pestana.dataset.vista);
      document.dispatchEvent(new CustomEvent("vista:cambiar", { detail: { vista: pestana.dataset.vista } }));
    });
  }

  marcar(opciones.activa || "login");
}
