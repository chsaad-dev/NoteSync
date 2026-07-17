// Cloudflare Worker backend proxy for NoteSync
// Implements Firebase ID token JWT verification, rate limiting via KV, Cloudinary signing/deletions, Firestore purging,
// Cloudinary storage limits validation, multi-device sessions, and worker-mediated public note sharing.

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
      const firebaseProjectId = env.FIREBASE_PROJECT_ID;

      // --- Bypassed Routes ---
      // GET /public/note/:publicUrlId
      if (url.pathname.startsWith('/public/note/') && request.method === 'GET') {
        const publicUrlId = url.pathname.split('/public/note/')[1];
        if (!publicUrlId || publicUrlId.trim() === '') {
          return new Response('Note Not Found', { status: 404, headers: corsHeaders });
        }

        const publicNoteUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/public_notes/${publicUrlId}`;
        const firestoreResp = await fetch(publicNoteUrl);

        if (!firestoreResp.ok) {
          return new Response('Note Not Found', { status: 404, headers: corsHeaders });
        }

        const docData = await firestoreResp.json();
        const title = docData.fields.title?.stringValue || "Untitled Note";
        const contentHtml = docData.fields.contentHtml?.stringValue || "";
        const mediaUrls = docData.fields.mediaUrls?.arrayValue?.values?.map(v => v.stringValue) || [];
        const createdAt = docData.fields.createdAt?.timestampValue || docData.fields.createdAt?.stringValue || "";

        // Premium Light/Dark Web View Page
        const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)} - NoteSync</title>
  <style>
    :root {
      --bg-color: #f5f6fa;
      --text-color: #2f3640;
      --card-bg: #ffffff;
      --card-border: #dcdde1;
      --primary-color: #4834BF;
      --date-color: #718093;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg-color: #121212;
        --text-color: #e0e0e0;
        --card-bg: #1e1e1e;
        --card-border: #2c2c2c;
        --primary-color: #6c5ce7;
        --date-color: #a0a0a0;
      }
    }
    body {
      background-color: var(--bg-color);
      color: var(--text-color);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      min-height: 100vh;
    }
    .container {
      width: 100%;
      max-width: 680px;
      padding: 32px 24px;
      margin: 24px 16px;
      background-color: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.05);
      box-sizing: border-box;
      height: fit-content;
    }
    h1 {
      margin-top: 0;
      margin-bottom: 12px;
      font-size: 32px;
      font-weight: 700;
      color: var(--primary-color);
      line-height: 1.25;
    }
    .date {
      font-size: 13px;
      color: var(--date-color);
      margin-bottom: 32px;
      border-bottom: 1px solid var(--card-border);
      padding-bottom: 16px;
    }
    .content {
      line-height: 1.8;
      font-size: 16px;
    }
    .content p {
      margin-top: 0;
      margin-bottom: 16px;
    }
    .media-gallery {
      margin-top: 32px;
      display: grid;
      grid-template-columns: 1fr;
      gap: 16px;
    }
    .media-gallery img, .media-gallery video {
      width: 100%;
      max-height: 450px;
      object-fit: contain;
      border-radius: 12px;
      border: 1px solid var(--card-border);
      background-color: #000;
    }
    .footer {
      margin-top: 48px;
      border-top: 1px solid var(--card-border);
      padding-top: 24px;
      text-align: center;
      font-size: 12px;
      color: var(--date-color);
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>${escapeHtml(title)}</h1>
    <div class="date">Shared via NoteSync • Published on ${createdAt ? new Date(createdAt).toLocaleDateString() : 'N/A'}</div>
    <div class="content">
      ${contentHtml}
    </div>
    ${mediaUrls.length > 0 ? `
    <div class="media-gallery">
      ${mediaUrls.map(url => {
        const isVideo = url.toLowerCase().includes('.mp4') || url.toLowerCase().includes('.mov');
        return isVideo 
          ? `<video src="${url}" controls></video>`
          : `<img src="${url}" alt="Attachment" />`;
      }).join('')}
    </div>
    ` : ''}
    <div class="footer">
      This is a secure read-only note shared via NoteSync.
    </div>
  </div>
</body>
</html>`;

        return new Response(html, {
          status: 200,
          headers: {
            'Content-Type': 'text/html; charset=utf-8',
            ...corsHeaders,
          }
        });
      }

      // --- Authenticated Routes ---
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

      // Fetch service account access token for administrative calls
      const serviceAccountToken = await getServiceAccountToken(
        env.FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL,
        env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
      );

      // 5. Route Handling
      if (url.pathname === '/sign-upload') {
        const body = await request.json().catch(() => ({}));
        const fileSize = parseInt(body.fileSize, 10) || 0;

        // Fetch config limits
        const configUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/config/storage_limits`;
        const configResp = await fetch(configUrl, {
          headers: { 'Authorization': `Bearer ${serviceAccountToken}` }
        });
        let defaultMaxStorageBytes = 314572800; // 300MB default
        if (configResp.ok) {
          const configData = await configResp.json();
          defaultMaxStorageBytes = parseInt(configData.fields.defaultMaxStorageBytes?.integerValue, 10) || defaultMaxStorageBytes;
        }

        // Get user profile
        const userProfileUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}`;
        const profileResp = await fetch(userProfileUrl, {
          headers: { 'Authorization': `Bearer ${serviceAccountToken}` }
        });

        let usedStorage = 0;
        let maxStorage = defaultMaxStorageBytes;

        if (profileResp.ok) {
          const profileData = await profileResp.json();
          usedStorage = parseInt(profileData.fields.usedStorage?.integerValue, 10) || 0;
          maxStorage = parseInt(profileData.fields.maxStorage?.integerValue, 10) || defaultMaxStorageBytes;
        } else if (profileResp.status === 404) {
          // Initialize user profile
          const initProfile = {
            fields: {
              email: { stringValue: decodedToken.email || "" },
              usedStorage: { integerValue: "0" },
              maxStorage: { integerValue: defaultMaxStorageBytes.toString() }
            }
          };
          await fetch(userProfileUrl, {
            method: 'PATCH',
            headers: {
              'Authorization': `Bearer ${serviceAccountToken}`,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify(initProfile)
          });
        }

        // Validate limits
        if (usedStorage + fileSize > maxStorage) {
          return new Response(
            JSON.stringify({ 
              error: `Storage limit exceeded. Uploading ${formatMB(fileSize)} MB requires more than your ${formatMB(maxStorage - usedStorage)} MB available space.` 
            }), 
            {
              status: 403,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

        // Validate that all required Cloudinary env vars are present
        if (!env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET || !env.CLOUDINARY_CLOUD_NAME) {
          return new Response(JSON.stringify({ 
            error: 'Server misconfiguration: Cloudinary secrets not bound.'
          }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const timestamp = Math.floor(Date.now() / 1000);
        const folder = `notesync/${userId}`;
        
        // Generate signature for 'folder' and 'timestamp' alphabetically
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

      if (url.pathname === '/commit-upload') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        const body = await request.json().catch(() => ({}));
        const fileSize = parseInt(body.fileSize, 10) || 0;
        if (fileSize <= 0) {
          return new Response(JSON.stringify({ error: 'Invalid file size' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        // Fetch User Profile
        const userProfileUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}`;
        const profileResp = await fetch(userProfileUrl, {
          headers: { 'Authorization': `Bearer ${serviceAccountToken}` }
        });

        let currentUsed = 0;
        let maxStorage = 314572800;
        let email = decodedToken.email || "";

        if (profileResp.ok) {
          const profileData = await profileResp.json();
          currentUsed = parseInt(profileData.fields.usedStorage?.integerValue, 10) || 0;
          maxStorage = parseInt(profileData.fields.maxStorage?.integerValue, 10) || maxStorage;
          email = profileData.fields.email?.stringValue || email;
        }

        // Server-side calculation to increment usedStorage
        const newUsed = currentUsed + fileSize;
        const updatePayload = {
          fields: {
            email: { stringValue: email },
            usedStorage: { integerValue: newUsed.toString() },
            maxStorage: { integerValue: maxStorage.toString() }
          }
        };

        await fetch(userProfileUrl, {
          method: 'PATCH',
          headers: {
            'Authorization': `Bearer ${serviceAccountToken}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(updatePayload)
        });

        return new Response(JSON.stringify({ success: true, usedStorage: newUsed }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      if (url.pathname === '/delete-media') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        const body = await request.json();
        const publicId = body.public_id;
        const fileSize = parseInt(body.file_size, 10) || 0;

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

        const isVideo = publicId.endsWith('.mp4') || publicId.endsWith('.mov');
        const resourceType = isVideo ? 'video' : 'image';

        const cloudName = env.CLOUDINARY_CLOUD_NAME;
        const destroyUrl = `https://api.cloudinary.com/v1_1/${cloudName}/${resourceType}/destroy`;

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

        // Decrement user's usedStorage on successful Cloudinary deletion confirmation
        if (cloudinaryResp.ok && fileSize > 0) {
          const userProfileUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}`;
          const profileResp = await fetch(userProfileUrl, {
            headers: { 'Authorization': `Bearer ${serviceAccountToken}` }
          });

          if (profileResp.ok) {
            const profileData = await profileResp.json();
            const currentUsed = parseInt(profileData.fields.usedStorage?.integerValue, 10) || 0;
            const maxStorage = parseInt(profileData.fields.maxStorage?.integerValue, 10) || 314572800;
            const email = profileData.fields.email?.stringValue || "";

            const newUsed = Math.max(0, currentUsed - fileSize);
            const updatePayload = {
              fields: {
                email: { stringValue: email },
                usedStorage: { integerValue: newUsed.toString() },
                maxStorage: { integerValue: maxStorage.toString() }
              }
            };

            await fetch(userProfileUrl, {
              method: 'PATCH',
              headers: {
                'Authorization': `Bearer ${serviceAccountToken}`,
                'Content-Type': 'application/json'
              },
              body: JSON.stringify(updatePayload)
            });
          }
        }
        
        return new Response(JSON.stringify(cloudinaryResult), {
          status: cloudinaryResp.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (url.pathname === '/publish-note') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        const body = await request.json().catch(() => ({}));
        const { noteId, publicUrlId, title, contentHtml, mediaUrls, createdAt } = body;

        if (!noteId || !publicUrlId || !title || !contentHtml) {
          return new Response(JSON.stringify({ error: 'Missing required note parameters' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        // Verify Note Ownership: fetch note from user's notes collection using user's idToken
        const noteUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}/notes/${noteId}`;
        const noteResp = await fetch(noteUrl, {
          headers: { 'Authorization': `Bearer ${idToken}` }
        });

        if (!noteResp.ok) {
          return new Response(JSON.stringify({ error: 'Unauthorized note access or note does not exist' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        // Write decrypted note content to public_notes/{publicUrlId} using Service Account token
        const publicNoteUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/public_notes/${publicUrlId}`;
        
        const publicPayload = {
          fields: {
            title: { stringValue: title },
            contentHtml: { stringValue: contentHtml },
            mediaUrls: {
              arrayValue: {
                values: (mediaUrls || []).map(url => ({ stringValue: url }))
              }
            },
            createdAt: { timestampValue: new Date(createdAt).toISOString() }
          }
        };

        const publishResp = await fetch(publicNoteUrl, {
          method: 'PATCH',
          headers: {
            'Authorization': `Bearer ${serviceAccountToken}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(publicPayload)
        });

        if (!publishResp.ok) {
          const errMsg = await publishResp.text();
          return new Response(JSON.stringify({ error: `Worker publish failed: ${errMsg}` }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        return new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      if (url.pathname === '/unpublish-note') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        const body = await request.json().catch(() => ({}));
        const { noteId, publicUrlId } = body;

        if (!noteId || !publicUrlId) {
          return new Response(JSON.stringify({ error: 'Missing noteId or publicUrlId' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        // Verify Note Ownership
        const noteUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}/notes/${noteId}`;
        const noteResp = await fetch(noteUrl, {
          headers: { 'Authorization': `Bearer ${idToken}` }
        });

        if (!noteResp.ok) {
          return new Response(JSON.stringify({ error: 'Unauthorized note access or note does not exist' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        // Delete public_notes/{publicUrlId} using Service Account token
        const publicNoteUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/public_notes/${publicUrlId}`;
        const deleteResp = await fetch(publicNoteUrl, {
          method: 'DELETE',
          headers: {
            'Authorization': `Bearer ${serviceAccountToken}`
          }
        });

        if (!deleteResp.ok && deleteResp.status !== 404) {
          const errMsg = await deleteResp.text();
          return new Response(JSON.stringify({ error: `Worker delete failed: ${errMsg}` }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }

        return new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      if (url.pathname === '/delete-account') {
        if (request.method !== 'POST') {
          return new Response('Method not allowed', { status: 405, headers: corsHeaders });
        }

        // 1. Fetch user's notes from Firestore
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

        // 2. Loop notes and delete associated Cloudinary assets and any active public web links
        for (const doc of documents) {
          const fields = doc.fields || {};
          const mediaUrlsValue = fields.mediaUrls || {};
          const mediaUrls = (mediaUrlsValue.arrayValue && mediaUrlsValue.arrayValue.values) || [];
          
          for (const urlVal of mediaUrls) {
            const url = urlVal.stringValue;
            if (!url) continue;

            const publicId = extractPublicId(url);
            if (publicId && publicId.startsWith(`notesync/${userId}/`)) {
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

          // If note is public, unpublish it
          const publicUrlId = fields.publicUrlId?.stringValue;
          if (publicUrlId) {
            const publicNoteUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/public_notes/${publicUrlId}`;
            await fetch(publicNoteUrl, {
              method: 'DELETE',
              headers: { 'Authorization': `Bearer ${serviceAccountToken}` }
            });
          }

          // Delete note document in Firestore
          const docName = doc.name; 
          const deleteDocUrl = `https://firestore.googleapis.com/v1/${docName}`;
          await fetch(deleteDocUrl, {
            method: 'DELETE',
            headers: {
              'Authorization': `Bearer ${idToken}`,
            },
          });
        }

        // Delete user sessions collection and user profile document
        const userProfileUrl = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${userId}`;
        await fetch(userProfileUrl, {
          method: 'DELETE',
          headers: { 'Authorization': `Bearer ${serviceAccountToken}` }
        });

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

function formatMB(bytes) {
  return (bytes / (1024 * 1024)).toFixed(1);
}

function escapeHtml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

async function sha1(message) {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest('SHA-1', msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padLeft(2, '0')).join('');
}

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

// Signs a RS256 assertion JWT using Firebase Service Account private key PEM
async function getServiceAccountToken(clientEmail, privateKeyPEM) {
  if (!clientEmail || !privateKeyPEM) {
    throw new Error('Service account client email or private key is missing from environment bindings');
  }

  // Convert PKCS#8 PEM string to ArrayBuffer
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = privateKeyPEM
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\s/g, "");
  
  const binaryDerString = atob(pemContents);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: { name: "SHA-256" },
    },
    false,
    ["sign"]
  );

  const header = {
    alg: "RS256",
    typ: "JWT"
  };

  const now = Math.floor(Date.now() / 1000);
  const claimSet = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now
  };

  const encodedHeader = btoa(JSON.stringify(header)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const encodedClaimSet = btoa(JSON.stringify(claimSet)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const signInput = `${encodedHeader}.${encodedClaimSet}`;
  const signInputBuffer = new TextEncoder().encode(signInput);

  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    signInputBuffer
  );

  const signature = btoa(String.fromCharCode(...new Uint8Array(signatureBuffer)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${signInput}.${signature}`;

  // Exchange JWT assertion for OAuth token
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Google OAuth exchange failed: ${errorText}`);
  }

  const data = await response.json();
  return data.access_token;
}
