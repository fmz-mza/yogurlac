// Guardia de autenticación: se carga en todas las páginas después de supabase.js.
// Las páginas arrancan ocultas (<style id="auth-oculto">) y solo se muestran si hay sesión.
// Ojo: esto protege la interfaz; los datos los protege RLS en Supabase.
(async () => {
    const esLogin = location.pathname.endsWith('login.html');
    const mostrarPagina = () => document.getElementById('auth-oculto')?.remove();

    const { data: { session } } = await window.supabaseClient.auth.getSession();

    if (!session && !esLogin) {
        location.replace('login.html');
        return;
    }
    if (session && esLogin) {
        location.replace('index.html');
        return;
    }

    // Si la sesión se cierra (en esta u otra pestaña), volver al login
    window.supabaseClient.auth.onAuthStateChange((evento) => {
        if (evento === 'SIGNED_OUT' && !esLogin) location.replace('login.html');
    });

    if (session) agregarSalir(session.user.email);
    mostrarPagina();
})();

// Agrega email + botón "Salir" a la navbar (escritorio y móvil) sin tocar el HTML de cada página
function agregarSalir(email) {
    const salir = async () => {
        await window.supabaseClient.auth.signOut();
        location.replace('login.html');
    };

    const escritorio = document.querySelector('nav .hidden.md\:flex');
    if (escritorio) {
        const span = document.createElement('span');
        span.className = 'text-sm text-gray-500 self-center';
        span.textContent = email;
        const btn = document.createElement('button');
        btn.textContent = 'Salir';
        btn.className = 'text-sm text-red-600 hover:text-red-800 self-center';
        btn.addEventListener('click', salir);
        escritorio.append(span, btn);
    }

    const movil = document.getElementById('mobile-menu');
    if (movil) {
        const btn = document.createElement('button');
        btn.textContent = `Salir (${email})`;
        btn.className = 'block w-full text-left px-4 py-2 text-red-600 hover:bg-gray-50';
        btn.addEventListener('click', salir);
        movil.appendChild(btn);
    }
}
