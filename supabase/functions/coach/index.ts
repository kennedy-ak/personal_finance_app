// Coach — authenticated proxy to the model provider.
//
// This function is deliberately dumb. It holds the API key and checks who is
// calling; it does no financial reasoning at all. All of that lives in the
// Dart money engine, which is tested and is the single source of truth — a
// second implementation here would drift from it within a week.
//
// Deploy:
//   supabase secrets set OPENAI_API_KEY=sk-...
//   supabase functions deploy coach
//
// The client calls it with supabase.functions.invoke('coach', ...), which
// attaches the user's JWT automatically.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions'

const DEFAULT_MODEL = Deno.env.get('COACH_MODEL') ?? 'gpt-4o-mini'

/// Ceiling on a single request, so a runaway client cannot burn the budget.
const MAX_TOKENS = 1500
const MAX_MESSAGES = 60

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Use POST.' }, 405)
  }

  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    return json(
      { error: 'The coach is not configured. Set OPENAI_API_KEY and redeploy.' },
      500,
    )
  }

  // Only signed-in users, and only ever on their own behalf.
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'Sign in to use the coach.' }, 401)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )

  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError || !userData?.user) {
    return json({ error: 'Sign in to use the coach.' }, 401)
  }

  let payload: {
    messages?: unknown
    tools?: unknown
    model?: string
    temperature?: number
    max_tokens?: number
  }

  try {
    payload = await req.json()
  } catch {
    return json({ error: 'Malformed request body.' }, 400)
  }

  const messages = payload.messages
  if (!Array.isArray(messages) || messages.length === 0) {
    return json({ error: 'No messages supplied.' }, 400)
  }
  if (messages.length > MAX_MESSAGES) {
    return json({ error: 'Conversation too long.' }, 413)
  }

  const body: Record<string, unknown> = {
    // The model is chosen server-side; the client does not get to pick
    // something expensive.
    model: DEFAULT_MODEL,
    messages,
    temperature: payload.temperature ?? 0.4,
    max_tokens: Math.min(payload.max_tokens ?? 900, MAX_TOKENS),
  }

  if (Array.isArray(payload.tools) && payload.tools.length > 0) {
    body.tools = payload.tools
    body.tool_choice = 'auto'
  }

  let upstream: Response
  try {
    upstream = await fetch(OPENAI_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })
  } catch (e) {
    return json({ error: `Could not reach the model: ${e}` }, 502)
  }

  const text = await upstream.text()

  if (!upstream.ok) {
    // Pass the provider's own explanation through — it is usually the useful
    // one (quota, bad key, model not available).
    let message = `Model error (${upstream.status})`
    try {
      const parsed = JSON.parse(text)
      if (parsed?.error?.message) message = parsed.error.message
    } catch {
      // keep the generic message
    }
    return json({ error: message }, upstream.status)
  }

  return new Response(text, {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
