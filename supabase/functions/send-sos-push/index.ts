import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8'

type SosAlertPushPayload = {
  alertId: number
  sessionId: string
  recipientUserId: string
}

type VerifiedSosAlert = SosAlertPushPayload & {
  senderName: string
  alertMessage: string
}

const ALLOWED_ORIGINS = [
  'https://ilwxanuvttrhxkgmaphq.supabase.co',
]

function getCorsHeaders(request: Request) {
  const origin = request.headers.get('Origin') ?? ''
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

Deno.serve(async (request) => {
  const corsHeaders = getCorsHeaders(request)

  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const firebaseServiceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? ''

    if (!supabaseUrl || !supabaseServiceRoleKey || !firebaseServiceAccountJson) {
      throw new Error(
        'Missing Supabase or Firebase service account secrets. Set FIREBASE_SERVICE_ACCOUNT_JSON in Supabase Edge Function secrets.',
      )
    }

    // --- AUTH: Extract caller identity from the verified JWT ---
    // With verify_jwt = true in config.toml, the Supabase gateway has already
    // verified the HS256 signature against SUPABASE_JWT_SECRET before the
    // request reaches this function. We only need to decode the payload to
    // read the `sub` claim (the Firebase UID set by firebase-auth-bridge).
    //
    // We do NOT use supabase.auth.getUser() because our bridge-minted JWTs
    // have no corresponding row in GoTrue's auth.users table — getUser()
    // would always return an error.
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Missing or invalid Authorization header' }, 401, corsHeaders)
    }
    const callerUserId = extractSubFromJwt(authHeader.replace('Bearer ', ''))
    if (!callerUserId) {
      return jsonResponse({ error: 'Invalid token: missing sub claim' }, 401, corsHeaders)
    }

    const { alerts } = await request.json() as { alerts?: SosAlertPushPayload[] }
    const requestedAlerts = (alerts ?? [])
      .map((alert) => ({
        alertId: Number(alert?.alertId),
        sessionId: String(alert?.sessionId ?? '').trim(),
        recipientUserId: String(alert?.recipientUserId ?? '').trim(),
      }))
      .filter((alert) =>
        Number.isSafeInteger(alert.alertId) &&
        alert.alertId > 0 &&
        alert.sessionId.length > 0 &&
        alert.recipientUserId.length > 0
      )

    if (requestedAlerts.length === 0) {
      return jsonResponse({ sentCount: 0, skippedCount: 0 }, 200, corsHeaders)
    }

    const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)
    const verifiedAlerts = await verifyAlertsForCaller(
      supabase,
      callerUserId,
      requestedAlerts,
    )
    if (verifiedAlerts.length === 0) {
      return jsonResponse({ error: 'No authorized SOS alerts found' }, 403, corsHeaders)
    }

    const recipientUserIds = [...new Set(verifiedAlerts.map((alert) => alert.recipientUserId))]
    const { data: tokenRows, error: tokenError } = await supabase
      .from('push_notification_tokens')
      .select('user_id,fcm_token')
      .in('user_id', recipientUserIds)

    if (tokenError) {
      console.error('token lookup failed', tokenError)
      throw tokenError
    }

    const tokensByUserId = new Map<string, string[]>()
    for (const row of tokenRows ?? []) {
      const userId = String(row.user_id ?? '').trim()
      const token = String(row.fcm_token ?? '').trim()
      if (!userId || !token) continue
      const existing = tokensByUserId.get(userId) ?? []
      existing.push(token)
      tokensByUserId.set(userId, existing)
    }

    const firebaseAccount = JSON.parse(firebaseServiceAccountJson) as {
      client_email: string
      private_key: string
      project_id: string
      token_uri?: string
    }
    const accessToken = await getGoogleAccessToken(firebaseAccount)

    let sentCount = 0
    let skippedCount = 0
    for (const alert of verifiedAlerts) {
      const tokens = tokensByUserId.get(alert.recipientUserId) ?? []
      if (tokens.length === 0) {
        skippedCount += 1
        continue
      }

      for (const token of tokens) {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${firebaseAccount.project_id}/messages:send`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token,
                notification: {
                  title: 'PANIC ALERT',
                  body: `${alert.senderName} sent an emergency SOS. Open Aegixa now.`,
                },
                data: {
                  type: 'sos_alert',
                  alertId: String(alert.alertId),
                  sessionId: alert.sessionId,
                  senderName: alert.senderName,
                  alertMessage: alert.alertMessage,
                },
                android: {
                  priority: 'high',
                  notification: {
                    channel_id: 'panic_sos_alerts',
                    sound: 'default',
                    visibility: 'PUBLIC',
                    default_vibrate_timings: true,
                  },
                },
              },
            }),
          },
        )

        if (response.ok) {
          sentCount += 1
          continue
        }

        const errorText = await response.text()
        console.error('FCM send failed', {
          status: response.status,
          alertId: alert.alertId,
          recipientUserId: alert.recipientUserId,
          errorText,
        })
        if (
          response.status === 404 ||
          errorText.includes('UNREGISTERED') ||
          errorText.includes('registration-token-not-registered')
        ) {
          await supabase.from('push_notification_tokens').delete().eq('fcm_token', token)
        }
      }
    }

    return jsonResponse({ sentCount, skippedCount }, 200, corsHeaders)
  } catch (error) {
    console.error('send-sos-push crashed', error)
    return jsonResponse(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      500,
      corsHeaders,
    )
  }
})

function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...headers,
      'Content-Type': 'application/json',
    },
  })
}

async function verifyAlertsForCaller(
  supabase: ReturnType<typeof createClient>,
  callerUserId: string,
  requestedAlerts: SosAlertPushPayload[],
): Promise<VerifiedSosAlert[]> {
  const requestedById = new Map<number, SosAlertPushPayload>()
  for (const alert of requestedAlerts) {
    requestedById.set(alert.alertId, alert)
  }

  const { data, error } = await supabase
    .from('sos_alerts')
    .select('id,session_id,sender_user_id,recipient_user_id,sender_name,alert_message')
    .eq('sender_user_id', callerUserId)
    .in('id', [...requestedById.keys()])

  if (error) {
    console.error('alert authorization lookup failed', error)
    throw error
  }

  const verifiedAlerts: VerifiedSosAlert[] = []
  for (const row of data ?? []) {
    const alertId = Number(row.id)
    const requested = requestedById.get(alertId)
    if (!requested) continue

    const sessionId = String(row.session_id ?? '').trim()
    const recipientUserId = String(row.recipient_user_id ?? '').trim()
    if (
      sessionId !== requested.sessionId ||
      recipientUserId !== requested.recipientUserId
    ) {
      continue
    }

    verifiedAlerts.push({
      alertId,
      sessionId,
      recipientUserId,
      senderName: String(row.sender_name ?? '').trim() || 'Aegixa User',
      alertMessage: String(row.alert_message ?? '').trim(),
    })
  }

  return verifiedAlerts
}

async function getGoogleAccessToken(serviceAccount: {
  client_email: string
  private_key: string
  token_uri?: string
}) {
  const nowInSeconds = Math.floor(Date.now() / 1000)
  const jwtHeader = base64UrlEncode(
    JSON.stringify({ alg: 'RS256', typ: 'JWT' }),
  )
  const jwtClaimSet = base64UrlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat: nowInSeconds,
      exp: nowInSeconds + 3600,
    }),
  )
  const signingInput = `${jwtHeader}.${jwtClaimSet}`
  const signature = await signJwt(signingInput, serviceAccount.private_key)

  const response = await fetch(
    serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${signingInput}.${signature}`,
      }),
    },
  )

  if (!response.ok) {
    throw new Error(`Could not fetch Google access token: ${await response.text()}`)
  }

  const tokenResponse = await response.json() as { access_token?: string }
  if (!tokenResponse.access_token) {
    throw new Error('Google access token response was empty.')
  }

  return tokenResponse.access_token
}

async function signJwt(input: string, privateKeyPem: string) {
  const pemContents = privateKeyPem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '')
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    base64Decode(pemContents),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(input),
  )
  return base64UrlEncode(signature)
}

function base64UrlEncode(value: string | ArrayBuffer) {
  const bytes = typeof value === 'string'
    ? new TextEncoder().encode(value)
    : new Uint8Array(value)
  const binary = String.fromCharCode(...bytes)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function base64Decode(value: string) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
  const binary = atob(padded)
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

/**
 * Decode the `sub` claim from a JWT without verifying the signature.
 *
 * This is safe here because the Supabase gateway (`verify_jwt = true`) has
 * already validated the HS256 signature against SUPABASE_JWT_SECRET before
 * the request reaches this function. We only need to read the payload.
 */
function extractSubFromJwt(token: string): string | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const payloadJson = new TextDecoder().decode(base64Decode(parts[1]))
    const payload = JSON.parse(payloadJson) as { sub?: string }
    const sub = (payload.sub ?? '').trim()
    return sub.length > 0 ? sub : null
  } catch {
    return null
  }
}
