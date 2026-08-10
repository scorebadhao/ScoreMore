import { createClient } from '@supabase/supabase-js';
import { APP_CONFIG, isConfigured } from './config.js';

export const supabase = isConfigured
  ? createClient(APP_CONFIG.supabaseUrl, APP_CONFIG.supabasePublishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;

export function requireSupabase() {
  if (!supabase) {
    throw new Error(`${APP_CONFIG.name} is not configured. Add the Supabase environment variables.`);
  }
  return supabase;
}
