// Utilidades compartidas. Se carga después de js/auth.js en cada página (menos login).

// Escapa texto de usuario (nombres, conceptos, etc.) antes de insertarlo con innerHTML.
// Cubre & < > " ' para que sea seguro tanto en contenido como dentro de atributos.
window.escapeHtml = function(valor) {
    return String(valor ?? '').replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
};
