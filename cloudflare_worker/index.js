// Cloudflare Worker backend proxy for NoteSync
// Implements Firebase ID token JWT verification, rate limiting via KV, Cloudinary signing/deletions, and Firestore purging.

export default {
  async fetch(request, env) {
    // 1. CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS, DELETE',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response('OK', { headers: corsHeaders });
    }

    try {
      const url = new URL(request.url);
      
      // 2. Extract Firebase ID token
      const authHeader = request.headers.get('Authorization');
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return new Response(JSON.stringify({ error: 'Missing or malformed Authorization header' }), {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      
      const idToken = authHeader.split('Bearer ')[1];
      
      // 3. Verify Token
      const firebaseProjectId = env.FIREBASE_PROJECT_ID;
      const decodedToken = await verifyFirebaseToken(idToken, firebaseProjectId);
      if (!decodedToken) {
        return new Response(JSON.stringify({ error: 'Invalid or expired authentication token' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const userId = decodedToken.sub; // Firebase UID

      // 4. Rate Limiting via Cloudflare KV
      if (env.RATE_LIMIT_KV) {
        const currentMinute = Math.floor(Date.now() / 60000);
        const limitKey = `rate:${userId}:${currentMinute}`;
        const countStr = await env.RATE_LIMIT_KV.get(limitKey);
        const count = countStr ? parseInt(countStr, 10) : 0;
        
        if (count >= 30) {
          return new Response(JSON.stringify({ error: 'Rate limit exceeded. Max 30 operations per minute.' }), {
            status: 429,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        
        await env.RATE_LIMIT_KV.put(limitKey, (count + 1).toString(), { expirationTtl: 60 });
      }

      // 5. Route Handling
      if (url.pathname === '/sign-upload') {
        // Validate that all required Cloudinary env vars are present
        if (!env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET || !env.CLOUDINARY_CLOUD_NAME) {
          return new Response(JSON.stringify({ 
            error: 'Server misconfiguration: Cloudinary secrets not bound.',
            debug: {
              hasApiKey: !!env.CLOUDINARY_API_KEY,
              hasApiSecret: !!env.CLOUDINARY_API_SECRET,
              hasCloudName: !!env.CLOUDINARY_CLOUD_NAME,
            }
          }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const timestamp = Math.floor(Date.now() / 1000);
        const folder = `notesync/${userId}`;
        
        // Generate signature for 'folder' and 'timestamp' alphabetically: "folder=<folder>&timestamp=<timestamp>"
        const signatureStr = `folder=${folder}&timestamp=${timestamp}${env.CLOUDINARY_API_SECRET}`;
        const signature = await sha1(signatureStr);

        return new Response(
          JSON.stringify({
            signature,
            timestamp,
            apiKey: env.CLOUDINARY_API_KEY,
            cloudName: env.CLOUDINARY_CLOUD_NAME,
            folder,
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      if (url.pathname === '/delete-media') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        const body = await request.json();
        const publicId = body.public_id;
        if (!publicId) {
          return new Response(JSON.stringify({ error: 'Missing public_id' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        // Validate publicId starts with the user's folder to prevent deleting other users' assets
        if (!publicId.startsWith(`notesync/${userId}/`)) {
          return new Response(JSON.stringify({ error: 'Unauthorized to delete this media asset' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const timestamp = Math.floor(Date.now() / 1000);
        const signatureStr = `public_id=${publicId}&timestamp=${timestamp}${env.CLOUDINARY_API_SECRET}`;
        const signature = await sha1(signatureStr);

        // Determine resource type based on file path or fallback to image/video
        const isVideo = publicId.endsWith('.mp4') || publicId.endsWith('.mov');
        const resourceType = isVideo ? 'video' : 'image';

        const cloudName = env.CLOUDINARY_CLOUD_NAME;
        const destroyUrl = `https://api.cloudinary.com/v1_1/${cloudName}/${resourceType}/destroy`;

        // POST multipart/form-data to Cloudinary
        const formData = new FormData();
        formData.append('public_id', publicId);
        formData.append('api_key', env.CLOUDINARY_API_KEY);
        formData.append('timestamp', timestamp.toString());
        formData.append('signature', signature);

        const cloudinaryResp = await fetch(destroyUrl, {
          method: 'POST',
          body: formData,
        });

        const cloudinaryResult = await cloudinaryResp.json();
        
        return new Response(JSON.stringify(cloudinaryResult), {
          status: cloudinaryResp.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (url.pathname === '/delete-account') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        // 1. Fetch user's notes from Firestore using the user's auth token
        const listNotesUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}/notes?pageSize=100`;
        const firestoreListResp = await fetch(listNotesUrl, {
          headers: {
            'Authorization': `Bearer ${idToken}`,
          },
        });

        if (!firestoreListResp.ok) {
          const errMsg = await firestoreListResp.text();
          return new Response(JSON.stringify({ error: `Failed to fetch notes: ${errMsg}` }), {
            status: firestoreListResp.status,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const listData = await firestoreListResp.json();
        const documents = listData.documents || [];

        // 2. Loop notes and delete associated Cloudinary assets
        for (const doc of documents) {
          const fields = doc.fields || {};
          const mediaUrlsValue = fields.mediaUrls || {};
          const mediaUrls = (mediaUrlsValue.arrayValue && mediaUrlsValue.arrayValue.values) || [];
          
          for (const urlVal of mediaUrls) {
            const url = urlVal.stringValue;
            if (!url) continue;

            const publicId = extractPublicId(url);
            if (publicId && publicId.startsWith(`notesync/${userId}/`)) {
              // Delete Cloudinary asset
              const timestamp = Math.floor(Date.now() / 1000);
              const signatureStr = `public_id=${publicId}&timestamp=${timestamp}${env.CLOUDINARY_API_SECRET}`;
              const signature = await sha1(signatureStr);

              const isVideo = publicId.endsWith('.mp4') || publicId.endsWith('.mov');
              const resourceType = isVideo ? 'video' : 'image';
              const destroyUrl = `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/${resourceType}/destroy`;

              const formData = new FormData();
              formData.append('public_id', publicId);
              formData.append('api_key', env.CLOUDINARY_API_KEY);
              formData.append('timestamp', timestamp.toString());
              formData.append('signature', signature);

              await fetch(destroyUrl, {
                method: 'POST',
                body: formData,
              });
            }
          }

          // Delete note document in Firestore
          const docName = doc.name; // Full document path
          const deleteDocUrl = `https://firestore.googleapis.com/v1/${docName}`;
          await fetch(deleteDocUrl, {
            method: 'DELETE',
            headers: {
              'Authorization': `Bearer ${idToken}`,
            },
          });
        }

        return new Response(JSON.stringify({ success: true, message: 'All account data deleted successfully' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      return new Response('Not found', { status: 404, headers: corsHeaders });
    } catch (e) {
      return new Response(JSON.stringify({ error: `Internal Server Error: ${e.message}` }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
  },
};

// --- Helper Functions ---

async function sha1(message) {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest('SHA-1', msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padLeft(2, '0')).join('');
}

// Ensure padLeft functions correctly in JS environment
String.prototype.padLeft = function(length, character) {
  return this.padStart(length, character);
};

function extractPublicId(url) {
  try {
    const uploadIndex = url.indexOf('/upload/');
    if (uploadIndex === -1) return null;
    const afterUpload = url.substring(uploadIndex + 8);
    let pathWithoutVersion = afterUpload;
    const firstSlash = afterUpload.indexOf('/');
    if (firstSlash !== -1) {
      const versionSegment = afterUpload.substring(0, firstSlash);
      if (versionSegment.startsWith('v')) {
        pathWithoutVersion = afterUpload.substring(firstSlash + 1);
      }
    }
    const dotIndex = pathWithoutVersion.lastIndexOf('.');
    if (dotIndex !== -1) {
      pathWithoutVersion = pathWithoutVersion.substring(0, dotIndex);
    }
    return pathWithoutVersion;
  } catch (_) {
    return null;
  }
}

// Validates the JWT structure and signature using Google's public JWK certs
async function verifyFirebaseToken(token, projectId) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    // 1. Decode Payload
    const payload = JSON.parse(base64UrlDecode(parts[1]));
    
    // 2. Validate standard Claims
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp < now) return null; // Expired
    if (payload.aud !== projectId) return null; // Wrong audience
    if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null; // Wrong issuer

    // 3. Fetch Google public JWKs to verify signature
    const certsResp = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
    const jwks = await certsResp.json();
    
    // Parse JWT header to find key ID (kid)
    const header = JSON.parse(base64UrlDecode(parts[0]));
    const kid = header.kid;
    
    const keyData = jwks.keys.find((k) => k.kid === kid);
    if (!keyData) return null;

    // Convert JWK to CryptoKey
    const cryptoKey = await crypto.subtle.importKey(
      'jwk',
      keyData,
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: { name: 'SHA-256' },
      },
      false,
      ['verify']
    );

    // Verify signature
    const encoder = new TextEncoder();
    const dataBuffer = encoder.encode(`${parts[0]}.${parts[1]}`);
    const signatureBuffer = base64UrlToBuffer(parts[2]);

    const isValid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      cryptoKey,
      signatureBuffer,
      dataBuffer
    );

    return isValid ? payload : null;
  } catch (_) {
    return null;
  }
}

function base64UrlDecode(str) {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  return atob(base64);
}

function base64UrlToBuffer(base64url) {
  let base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
