// Configuración de Supabase corregida para evitar conflictos
const SUPABASE_URL = 'https://kqwnqhayodtjhdksdmfr.supabase.co'; // <--- PEGA TU URL AQUÍ
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtxd25xaGF5b2R0amhka3NkbWZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxMDI1MzIsImV4cCI6MjEwMjY3ODUzMn0.HepjYgpZs3N4QUPNZzIj6Hkdqe9-vkZmvCedMJlQYp4'; // <--- PEGA TU KEY AQUÍ

// Inicializar cliente con nombre seguro
window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
