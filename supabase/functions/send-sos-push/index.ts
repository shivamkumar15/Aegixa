import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8'

type SosAlertPushPayload = {
  alertId: number
  sessionId: string
  recipientUserId: string
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
    console.log('send-sos-push request received')
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const firebaseServiceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? ''

    if (!supabaseUrl || !supabaseServiceRoleKey || !firebaseServiceAccountJson) {
      throw new Error(
        'Missing Supabase or Firebase service account secrets. Set FIREBASE_SERVICE_ACCOUNT_JSON in Supabase Edge Function secrets.',
      )
    }

    // --- AUTH: Verify the caller is an authenticated Supabase user ---
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Missing or invalid Authorization header' }, 401, corsHeaders)
    }
    const userToken = authHeader.replace('Bearer ', '')
    const userSupabase = createClient(supabaseUrl, supabaseAnonKey || supabaseServiceRoleKey, {
      global: { headers: { Authorization: `Bearer ${userToken}` } },
    })
    const { data: { user }, error: authError } = await userSupabase.auth.getUser()
    if (authError || !user) {
      console.error('auth verification failed', authError)
      return jsonResponse({ error: 'Unauthorized' }, 401, corsHeaders)
    }
    const callerUserId = user.id
    console.log('authenticated caller', { callerUserId })

    const { alerts } = await request.json() as { alerts?: SosAlertPushPayload[] }
    const sanitizedAlerts = (alerts ?? []).filter(
      (alert) => alert && alert.recipientUserId && alert.senderName,
    )
    console.log('alerts received', { count: sanitizedAlerts.length })
    if (sanitizedAlerts.length === 0) {
      return jsonResponse({ sentCount: 0, skippedCount: 0 }, 200, corsHeaders)
    }

    const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)
    const recipientUserIds = [...new Set(sanitizedAlerts.map((alert) => alert.recipientUserId))]
    const { data: tokenRows, error: tokenError } = await supabase
      .from('push_notification_tokens')
      .select('user_id,fcm_token')
      .in('user_id', recipientUserIds)

    if (tokenError) {
      console.error('token lookup failed', tokenError)
      throw tokenError
    }
    console.log('tokens fetched', { count: tokenRows?.length ?? 0, recipientUserIds })

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
    console.log('google access token acquired')

    let sentCount = 0
    let skippedCount = 0
    for (const alert of sanitizedAlerts) {
      const tokens = tokensByUserId.get(alert.recipientUserId) ?? []
      if (tokens.length === 0) {
        skippedCount += 1
        console.warn('no tokens found for recipient', {
          recipientUserId: alert.recipientUserId,
          alertId: alert.alertId,
        })
        continue
      }

      for (const token of tokens) {
        console.log('sending FCM message', {
          alertId: alert.alertId,
          recipientUserId: alert.recipientUserId,
        })
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
          console.log('FCM message sent', {
            alertId: alert.alertId,
            recipientUserId: alert.recipientUserId,
          })
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
          console.warn('deleted unregistered token', {
            recipientUserId: alert.recipientUserId,
          })
        }
      }
    }

    console.log('send-sos-push completed', { sentCount, skippedCount })
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
