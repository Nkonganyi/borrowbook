import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Decode a base64url string (the format produced by e.g. `.toString('base64url')`
// in Node or `base64.urlsafe_b64encode` in Python) into a UTF-8 string.
// base64url only ever contains A-Z a-z 0-9 - _ so it survives any URL/form/shell
// encoding layer untouched, unlike raw JSON with +, /, and newlines in it.
function decodeBase64Url(b64url: string): string {
  let b64 = b64url.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4;
  if (pad === 2) b64 += "==";
  else if (pad === 3) b64 += "=";
  else if (pad !== 0) {
    throw new Error(
      `FIREBASE_SERVICE_ACCOUNT_B64 has invalid length (${b64url.length}); secret looks truncated or corrupted`,
    );
  }
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder("utf-8").decode(bytes);
}

function pemToKeyBytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64urlEncodeJson(obj: unknown): string {
  const bytes = new TextEncoder().encode(JSON.stringify(obj));
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function getAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const keyBytes = pemToKeyBytes(serviceAccount.private_key);

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    aud: "https://oauth2.googleapis.com/token",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    iat: now,
    exp: now + 3600,
  };

  const signatureInput =
    base64urlEncodeJson(header) + "." + base64urlEncodeJson(payload);

  const signatureBytes = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signatureInput),
  );

  const signatureArray = Array.from(new Uint8Array(signatureBytes));
  const signatureEncoded = btoa(String.fromCharCode(...signatureArray))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");

  const jwt = signatureInput + "." + signatureEncoded;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenResponse.json();
  if (!tokenResponse.ok || !tokenData.access_token) {
    throw new Error(
      `Failed to obtain access token: ${JSON.stringify(tokenData)}`,
    );
  }

  return tokenData.access_token;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { topic, title, body } = await req.json();

    if (!topic || !title || !body) {
      return new Response(
        JSON.stringify({ error: "Missing topic, title or body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const secretB64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64");
    if (!secretB64) {
      throw new Error(
        "FIREBASE_SERVICE_ACCOUNT_B64 secret not found. Set it with the base64url-encoded service account JSON (see README).",
      );
    }

    const serviceAccountString = decodeBase64Url(secretB64);
    const serviceAccount = JSON.parse(serviceAccountString);

    const accessToken = await getAccessToken(serviceAccount);
    const projectId = serviceAccount.project_id;

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            topic,
            notification: { title, body },
            android: {
              priority: "HIGH",
              notification: {
                sound: "default",
                channel_id: "high_importance_channel",
              },
            },
            data: { click_action: "FLUTTER_NOTIFICATION_CLICK" },
          },
        }),
      },
    );

    const result = await response.text();
    console.log("Firebase Response:", result);

    return new Response(result, {
      status: response.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
