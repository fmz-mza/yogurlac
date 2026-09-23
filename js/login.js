document.getElementById('form-login').addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = document.getElementById('btn-login');
    const error = document.getElementById('login-error');
    error.classList.add('hidden');
    btn.disabled = true;
    btn.textContent = 'Ingresando...';

    const { error: err } = await window.supabaseClient.auth.signInWithPassword({
        email: document.getElementById('login-email').value.trim(),
        password: document.getElementById('login-password').value
    });

    if (err) {
        error.textContent = 'Email o contraseña incorrectos.';
        error.classList.remove('hidden');
        btn.disabled = false;
        btn.textContent = 'Ingresar';
        return;
    }
    location.replace('index.html');
});
