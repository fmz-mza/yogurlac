// Supabase Configuration
const SUPABASE_URL = 'https://kqwnqhayodtjhdksdmfr.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtxd25xaGF5b2R0amhka3NkbWZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxMDI1MzIsImV4cCI6MjEwMjY3ODUzMn0.HepjYgpZs3N4QUPNZzIj6Hkdqe9-vkZmvCedMJlQYp4';

// Initialize Supabase client
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
