// Utilidades compartidas. Se carga después de js/auth.js en cada página (menos login).

// Escapa texto de usuario (nombres, conceptos, etc.) antes de insertarlo con innerHTML.
// Cubre & < > " ' para que sea seguro tanto en contenido como dentro de atributos.
window.escapeHtml = function(valor) {
    return String(valor ?? '').replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
};

// Cantidades: pueden tener hasta 3 decimales (productos por kilo).
// redondearCantidad evita restos de punto flotante al sumar (0,1 + 0,2); formatCantidad las muestra en es-AR.
window.redondearCantidad = function(n) {
    return Math.round(Number(n) * 1000) / 1000;
};
window.formatCantidad = function(n) {
    return redondearCantidad(n).toLocaleString('es-AR', { maximumFractionDigits: 3 });
};
