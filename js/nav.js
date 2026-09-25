// Barra de navegación única para todas las páginas (excepto el login).
// Cada página la incluye con <script src="js/nav.js"></script> en el lugar donde va la barra:
// se dibuja ahí mismo, de forma síncrona, así los scripts de página encuentran #mobile-menu-btn y #mobile-menu.
// Para agregar o renombrar una pestaña, editar SOLO la lista PAGINAS.
(function () {
    const PAGINAS = [
        { href: 'index.html',       texto: 'Dashboard' },
        { href: 'pedidos.html',     texto: 'Pedidos' },
        { href: 'compras.html',     texto: 'Compras' },
        { href: 'ventas.html',      texto: 'Nueva Venta', movil: '🛒 Nueva Venta', destacada: true },
        { href: 'clientes.html',    texto: 'Clientes' },
        { href: 'precios.html',     texto: 'Precios' },
        { href: 'proveedores.html', texto: 'Proveedores' }
    ];

    const actual = location.pathname.split('/').pop() || 'index.html';

    const escritorio = PAGINAS.map(p => {
        const clases = p.href === actual
            ? 'text-blue-600 font-semibold border-b-2 border-blue-600'
            : 'text-gray-700 hover:text-blue-600';
        return `<a href="${p.href}" class="${clases}">${p.texto}</a>`;
    }).join('\n                    ');

    const movil = PAGINAS.map(p => {
        let clases = 'block px-4 py-2 text-gray-700 hover:bg-gray-50';
        if (p.href === actual) clases = 'block px-4 py-2 text-blue-600 font-semibold bg-blue-50';
        else if (p.destacada) clases = 'block px-4 py-2 text-green-600 font-semibold bg-green-50 hover:bg-green-100';
        return `<a href="${p.href}" class="${clases}">${p.movil || p.texto}</a>`;
    }).join('\n            ');

    const html = `
    <nav class="bg-white shadow-md sticky top-0 z-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex justify-between h-16">
                <div class="flex items-center">
                    <h1 class="text-xl font-bold text-blue-600">🥛 YogurLac</h1>
                </div>
                <div class="hidden md:flex space-x-8">
                    ${escritorio}
                </div>
                <button id="mobile-menu-btn" class="md:hidden flex items-center" aria-label="Menú">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/>
                    </svg>
                </button>
            </div>
        </div>
        <div id="mobile-menu" class="hidden md:hidden bg-white border-t">
            ${movil}
        </div>
    </nav>`;

    document.currentScript.insertAdjacentHTML('beforebegin', html);
})();
