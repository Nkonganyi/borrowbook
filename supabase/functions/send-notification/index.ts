import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  try {
    const { topic, title, body } = await req.json();

    if (!topic || !title || !body) {
      return new Response(
        JSON.stringify({
          error: "Missing topic, title or body",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    const serviceAccountString = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

    if (!serviceAccountString) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT secret not found.");
    }

    // Log the raw secret to see what Supabase has stored
    console.log("SECRET_LENGTH=" + serviceAccountString.length);
    
    // Get hex of first 100 bytes
    const encoder = new TextEncoder();
    const bytes = encoder.encode(serviceAccountString.substring(0, 100));
    let hexStart = "";
    for (let i = 0; i < Math.min(bytes.length, 100); i++) {
      hexStart += bytes[i].toString(16).padStart(2, "0") + " ";
    }
    console.log("SECRET_HEX_FIRST_100=" + hexStart);
    
    // Log a portion of the raw string to see if escaping is correct
    console.log("SECRET_SUBSTRING_0_100=" + serviceAccountString.substring(0, 100));
    console.log("SECRET_CONTAINS_LITERAL_BACKSLASH_N=" + serviceAccountString.includes("\\n"));
    console.log("SECRET_CONTAINS_ACTUAL_NEWLINE=" + serviceAccountString.includes("\n"));

    const serviceAccount = JSON.parse(serviceAccountString);
    const privateKey = serviceAccount.private_key;

    // Normalize private key: unescape any literal "\\n" sequences, then extract PEM
    const beginMarker = "-----BEGIN PRIVATE KEY-----";
    const endMarker = "-----END PRIVATE KEY-----";

    // Some upload paths double-escape newlines ("\\n"); convert those to real newlines first
    const unescaped = privateKey.replace(/\\n/g, "\n");


    // Extract the base64 block between the markers
    let base64Raw = unescaped
      .substring(unescaped.indexOf(beginMarker) + beginMarker.length, unescaped.indexOf(endMarker));

    // Log hex of the raw base64 block start for inspection
    try {
      const encoder2 = new TextEncoder();
      const rawBytes = encoder2.encode(base64Raw.substring(0, 200));
      let rawHex = "";
      for (let i = 0; i < rawBytes.length; i++) {
        rawHex += rawBytes[i].toString(16).padStart(2, "0") + " ";
      }
      console.log("BASE64_RAW_FIRST_200_HEX=" + rawHex);
    } catch (e) {
      console.log("FAILED_TO_PRINT_RAW_HEX: " + e.message);
    }

    // Find any non-base64 characters present in the raw block
    const bad = [];
    for (let i = 0; i < base64Raw.length; i++) {
      const ch = base64Raw[i];
      if (!/[A-Za-z0-9+/=\s]/.test(ch)) {
        bad.push({ i, ch, code: base64Raw.charCodeAt(i).toString(16).padStart(2, "0") });
        if (bad.length >= 10) break;
      }
    }
    if (bad.length > 0) {
      console.log("BASE64_RAW_NON_BASE64_CHARS=" + JSON.stringify(bad));
    } else {
      console.log("BASE64_RAW_NO_OBVIOUS_NON_BASE64_CHARS");
    }

    // Remove any whitespace (newlines, CRs, tabs, spaces) and any non-base64 characters
    let base64Content = base64Raw.replace(/\s+/g, "").replace(/[^A-Za-z0-9+/=]/g, "");

    console.log("BASE64_LENGTH_AFTER_CLEANING=" + base64Content.length);

    // Compute SHA-256 of the cleaned base64 block for byte-for-byte comparison
    try {
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(base64Content));
      const hashArray = Array.from(new Uint8Array(digest));
      const hashHex = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
      console.log("BASE64_CLEANED_SHA256=" + hashHex);
    } catch (e) {
      console.log("FAILED_TO_COMPUTE_SHA256: " + e.message);
    }

    // If length isn't a multiple of 4, pad with '=' to satisfy base64 padding rules
    const mod4 = base64Content.length % 4;
    console.log("BASE64_MOD4=" + mod4);
    if (mod4 !== 0) {
      const padCount = 4 - mod4;
      base64Content = base64Content + "=".repeat(padCount);
      console.log("PADDED_BASE64_WITH=" + padCount + "_EQUALS");
    }

    // Decode base64 (now strictly cleaned and padded)
    let binaryString;
    try {
      binaryString = atob(base64Content);
      console.log("ATOB_FULL_SUCCESS_LEN=" + binaryString.length);
    } catch (e) {
      console.log("ATOB_FULL_FAILED: " + e.message + ", falling back to chunked decode");

      // Fallback: decode in chunks aligned to 4 characters to avoid large-single-call issues
      const chunkSize = 1024; // multiple of 4
      const parts = [];
      for (let i = 0; i < base64Content.length; i += chunkSize) {
        const slice = base64Content.slice(i, i + chunkSize);
        try {
          parts.push(atob(slice));
        } catch (inner) {
          console.log("ATOB_CHUNK_FAILED at offset " + i + ": " + inner.message);
          // Log hex of the problematic slice for inspection
          try {
            const enc = new TextEncoder();
            const sliceBytes = enc.encode(slice);
            let sliceHex = "";
            for (let j = 0; j < sliceBytes.length; j++) {
              sliceHex += sliceBytes[j].toString(16).padStart(2, "0") + " ";
            }
            console.log("ATOB_CHUNK_FAILED_HEX_AT_" + i + "=" + sliceHex);
          } catch (h) {
            console.log("FAILED_TO_PRINT_SLICE_HEX: " + h.message);
          }
          throw new Error("Failed to decode base64 in chunked fallback: " + inner.message);
        }
      }
      binaryString = parts.join("");
      console.log("ATOB_CHUNKED_SUCCESS_LEN=" + binaryString.length);
    }

    const keybytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      keybytes[i] = binaryString.charCodeAt(i);
    }

    // Import key
    const key = await crypto.subtle.importKey(
      "pkcs8",
      keybytes,
      {
        name: "RSASSA-PKCS1-v1_5",
        hash: "SHA-256",
      },
      false,
      ["sign"],
    );

    const now = Math.floor(Date.now() / 1000);
    
    // Create JWT manually using Web Crypto API
    const header = { alg: "RS256", typ: "JWT" };
    const payload = {
      iss: serviceAccount.client_email,
      aud: "https://oauth2.googleapis.com/token",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      iat: now,
      exp: now + 3600,
    };
    
    // Helper to base64url encode
    const base64urlEncode = (obj) => {
      const json = JSON.stringify(obj);
      const bytes = new TextEncoder().encode(json);
      let binary = "";
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
    };
    
    const headerEncoded = base64urlEncode(header);
    const payloadEncoded = base64urlEncode(payload);
    const signatureInput = headerEncoded + "." + payloadEncoded;
    
    // Sign using Web Crypto
    const signatureBytes = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signatureInput),
    );
    
    const signatureArray = Array.from(new Uint8Array(signatureBytes));
    const signatureBinary = String.fromCharCode(...signatureArray);
    const signatureEncoded = btoa(signatureBinary)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=/g, "");
    
    const jwt = signatureInput + "." + signatureEncoded;
    console.log("JWT_CREATED=SUCCESS");

    const tokenResponse = await fetch(
      "https://oauth2.googleapis.com/token",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion: jwt,
        }),
      },
    );

    const tokenData = await tokenResponse.json();
    if (!tokenResponse.ok) {
      throw new Error(
        `Failed to obtain access token: ${JSON.stringify(tokenData)}`,
      );
    }

    const accessToken = tokenData.access_token;
    if (!accessToken) {
      throw new Error("Failed to obtain Firebase access token.");
    }

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

            notification: {
              title,
              body,
            },

            android: {
              priority: "HIGH",

              notification: {
                sound: "default",
                channel_id: "high_importance_channel",
              },
            },

            data: {
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        }),
      },
    );

    const result = await response.text();

    console.log("Firebase Response:", result);

    return new Response(result, {
      status: response.status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (err) {
    console.error(err);

    return new Response(
      JSON.stringify({
        error: err.message,
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  }
});