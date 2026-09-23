// Configuración de Supabase (proyecto Yogurlac, cuenta nueva, región sa-east-1).
// La anon key es pública por diseño: lo que protege los datos es RLS (solo dueños).
const SUPABASE_URL = 'https://jklsoynymbpwvlaqwzhy.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImprbHNveW55bWJwd3ZsYXF3emh5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxOTY0NDAsImV4cCI6MjEwNTc3MjQ0MH0.1iBFB_LkjfNaL0AaB8XlnRt89lijnj0p_ksRhdeqYrM';

// Inicializar cliente con nombre seguro
window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
