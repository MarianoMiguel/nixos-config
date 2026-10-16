#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Local-only WebAuthn acceptance test; all state disappears when stopped."""
import json
import secrets
from http.server import BaseHTTPRequestHandler, HTTPServer
from fido2.server import Fido2Server
from fido2.webauthn import PublicKeyCredentialRpEntity, PublicKeyCredentialUserEntity

PORT = 8790
ORIGIN = f"http://localhost:{PORT}"
server = Fido2Server(PublicKeyCredentialRpEntity(id="localhost", name="Bonhart relay check"),
                    verify_origin=lambda origin: origin == ORIGIN)
state = {}
credentials = []
results = {"registration": False, "authentication": False}
PAGE = b'''<!doctype html><meta charset="utf-8"><title>Bonhart YubiKey bridge check</title>
<style>body{font:18px system-ui;max-width:680px;margin:10vh auto;padding:24px;color:#21456a;background:#faf7ee}
h1{font-size:30px}button{padding:14px 18px;margin:12px 12px 12px 0;background:#21456a;color:#faf7ee;border:0;border-radius:4px;font:inherit;cursor:pointer}
pre{white-space:pre-wrap;padding:20px;background:#eee9dc;min-height:70px}</style>
<h1>Bonhart &harr; Mac YubiKey</h1><p>This checks a real browser authentication through your physical key on the Mac.</p>
<p>Choose <b>Security key</b> if Chrome asks, then touch the YubiKey beside your Mac.</p>
<button id="register">1. Create test credential</button><button id="authenticate">2. Verify sign-in</button>
<pre id="result">Ready. The bridge must be connected.</pre>
<p>No external service or real account is involved. This requests a non-discoverable test credential; the server keeps only its public data in memory.</p>
<script>
const result=document.querySelector('#result');
async function post(path,data={}){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const j=await r.json();if(!r.ok)throw Error(j.error);return j}
async function run(kind){try{result.textContent='Waiting for your key. Choose Security key and touch it on the Mac.';
const options=await post('/'+kind+'/begin');
const publicKey=kind==='register'?PublicKeyCredential.parseCreationOptionsFromJSON(options.publicKey):PublicKeyCredential.parseRequestOptionsFromJSON(options.publicKey);
const credential=await navigator.credentials[kind==='register'?'create':'get']({publicKey});
const answer=await post('/'+kind+'/complete',credential.toJSON());
result.textContent=answer.message;
}catch(e){result.textContent=e.name+': '+e.message}}
document.querySelector('#register').onclick=()=>run('register');document.querySelector('#authenticate').onclick=()=>run('authenticate');
</script>'''


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log request bodies or credential data.

    def respond(self, data, code=200, content_type="application/json"):
        payload = data if isinstance(data, bytes) else json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.headers.get("Host") != f"localhost:{PORT}":
            self.respond({"error": "Wrong host"}, 403)
        elif self.path == "/":
            self.respond(PAGE, content_type="text/html; charset=utf-8")
        elif self.path == "/status":
            self.respond(results)
        else:
            self.respond({"error": "Not found"}, 404)

    def do_POST(self):
        if self.headers.get("Origin") != ORIGIN or self.headers.get("Content-Type") != "application/json":
            self.respond({"error": "Wrong origin"}, 403)
            return
        length = int(self.headers.get("Content-Length", 0))
        if not 0 < length < 65536:
            self.respond({"error": "Invalid request size"}, 400)
            return
        try:
            data = json.loads(self.rfile.read(length))
            if self.path == "/register/begin":
                options, state["register"] = server.register_begin(
                    PublicKeyCredentialUserEntity(id=secrets.token_bytes(16), name="relay-check", display_name="Relay check"),
                    resident_key_requirement="discouraged", user_verification="discouraged",
                    authenticator_attachment="cross-platform")
                self.respond(dict(options))
            elif self.path == "/register/complete":
                auth_data = server.register_complete(state.pop("register"), data)
                credentials[:] = [auth_data.credential_data]
                results["registration"] = True
                results["authentication"] = False
                print("PASS: real browser registration with user presence", flush=True)
                self.respond({"message": "Registration passed. Now choose Verify sign-in and touch the key again."})
            elif self.path == "/authenticate/begin" and credentials:
                options, state["authenticate"] = server.authenticate_begin(credentials, user_verification="discouraged")
                self.respond(dict(options))
            elif self.path == "/authenticate/complete" and credentials:
                server.authenticate_complete(state.pop("authenticate"), credentials, data)
                results["authentication"] = True
                print("PASS: browser assertion signature, challenge, origin and user presence verified", flush=True)
                self.respond({"message": "Sign-in verified. Bonhart's browser authenticated using the physical key on your Mac."})
            else:
                self.respond({"error": "Create a test credential first"}, 400)
        except Exception as error:
            self.respond({"error": f"Verification failed ({type(error).__name__})"}, 400)


if __name__ == "__main__":
    print(f"Local WebAuthn test: {ORIGIN}", flush=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
