/**
 * Firebase-to-Supabase Auth Bridge
 *
 * This edge function exchanges a verified Firebase ID token for a
 * Supabase-compatible JWT. This bridges the authentication gap between
 * Firebase Auth (used for user identity) and Supabase RLS (which relies
 * on `auth.uid()` from the JWT `sub` claim).
 *
 * Flow:
 *   1. Client sends Firebase ID token in the request body.
 *   2. This function verifies the token against Google's public JWKS.
 *   3. On success, mints a Supabase HS256 JWT with the Firebase UID as `sub`.
 *   4. Returns the Supabase token to the client.
 *
 * Required env vars:
 *   - SUPABASE_JWT_SECRET  (auto-set by Supabase)
 *   - FIREBASE_PROJECT_ID  (set in Edge Function secrets)
 */

import * as jose from 'https://esm.sh/jose@5.2.0'

const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'

/** Token validity period — 1 hour. */
const TOKEN_TTL_SECONDS = 3600

Deno.serve(async (request: Request) => {
  // ── CORS preflight ──────────────────────────────────────────────
  // Mobile apps don't send Origin headers, so CORS is mainly relevant for
  // web/debug usage. Restrict to the Supabase project URL rather than '*'.
  const ALLOWED_ORIGINS = [
    Deno.env.get('SUPABASE_URL') ?? 'https://ilwxanuvttrhxkgmaphq.supabase.co',
  ]
  const origin = request.headers.get('Origin') ?? ''
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]
  const corsHeaders = {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
  }

  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ── Parse request ───────────────────────────────────────────────
    const body = await request.json().catch(() => null)
    const firebaseToken = body?.firebaseToken as string | undefined

    if (!firebaseToken || typeof firebaseToken !== 'string') {
      return jsonResponse({ error: 'Missing firebaseToken in request body' }, 400)
    }

    // ── Load secrets ────────────────────────────────────────────────
    const jwtSecret = Deno.env.get('SUPABASE_JWT_SECRET') ?? ''
    const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') ?? ''

    if (!jwtSecret) {
      console.error('SUPABASE_JWT_SECRET is not set')
      return jsonResponse({ error: 'Server misconfiguration' }, 500)
    }
    if (!firebaseProjectId) {
      console.error('FIREBASE_PROJECT_ID is not set')
      return jsonResponse({ error: 'Server misconfiguration' }, 500)
    }

    // ── Step 1: Verify Firebase ID token ────────────────────────────
    const jwks = jose.createRemoteJWKSet(new URL(FIREBASE_JWKS_URL))

    const { payload } = await jose.jwtVerify(firebaseToken, jwks, {
      issuer: `https://securetoken.google.com/${firebaseProjectId}`,
      audience: firebaseProjectId,
    })

    const firebaseUid = payload.sub
    if (!firebaseUid) {
      return jsonResponse({ error: 'Firebase token missing sub claim' }, 401)
    }

    // ── Step 2: Mint Supabase-compatible HS256 JWT ──────────────────
    const now = Math.floor(Date.now() / 1000)
    const expiresAt = now + TOKEN_TTL_SECONDS

    const supabasePayload = {
      // `sub` becomes `auth.uid()` in Supabase RLS policies.
      sub: firebaseUid,
      role: 'authenticated',
      iss: 'supabase',
      aud: 'authenticated',
      iat: now,
      exp: expiresAt,
    }

    const supabaseToken = await signHS256JWT(supabasePayload, jwtSecret)

    return jsonResponse({
      access_token: supabaseToken,
      token_type: 'bearer',
      expires_at: expiresAt,
      user_id: firebaseUid,
    }, 200, corsHeaders)
  } catch (error) {
    // Log only the error type — never the UID, token, or payload.
    const errorType = error instanceof Error ? error.constructor.name : 'unknown'
    console.error(`firebase-auth-bridge: ${errorType}`)

    // Return specific errors for known JWT failures so the client can
    // distinguish between "token expired" (re-fetch) and "invalid" (sign out).
    if (error instanceof jose.errors.JWTExpired) {
      return jsonResponse({ error: 'Firebase token expired' }, 401, corsHeaders)
    }
    if (error instanceof jose.errors.JWTClaimValidationFailed) {
      return jsonResponse({ error: 'Firebase token validation failed' }, 401, corsHeaders)
    }
    if (error instanceof jose.errors.JWSSignatureVerificationFailed) {
      return jsonResponse({ error: 'Firebase token signature invalid' }, 401, corsHeaders)
    }

    return jsonResponse({ error: 'Authentication failed' }, 401, corsHeaders)
  }
})

// ── Helpers ─────────────────────────────────────────────────────────

async function signHS256JWT(
  payload: Record<string, unknown>,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder()

  const header = base64UrlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const body = base64UrlEncode(JSON.stringify(payload))
  const signingInput = `${header}.${body}`

  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(signingInput),
  )

  return `${signingInput}.${base64UrlEncode(signature)}`
}

function base64UrlEncode(value: string | ArrayBuffer): string {
  const bytes =
    typeof value === 'string'
      ? new TextEncoder().encode(value)
      : new Uint8Array(value)
  const binary = String.fromCharCode(...bytes)
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '')
}

function jsonResponse(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  })
}
