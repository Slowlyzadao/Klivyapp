# Página de diagnóstico — HTML puro sem Vue/Vite. Acessível em qualquer host
# (sem constraint), ajuda a debug de "load failed" em celulares onde DevTools
# não está disponível. Mostra na tela o resultado de cada teste de rede.
class PatientPortalDiagController < ActionController::Base
  layout false
  protect_from_forgery with: :null_session

  def index
    render html: html.html_safe, content_type: 'text/html'
  end

  private

  def html
    <<~HTML
      <!doctype html>
      <html lang="pt-br">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Diag · Patient Portal</title>
        <style>
          * { box-sizing: border-box; -webkit-text-size-adjust: 100%; }
          body { margin: 0; font: 14px/1.4 system-ui, -apple-system, Segoe UI, sans-serif; background: #f8fafc; color: #0f172a; padding: 16px; }
          h1 { font-size: 18px; margin: 0 0 12px; }
          .row { background: #fff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 12px; margin-bottom: 10px; word-break: break-all; }
          .row strong { display: block; font-size: 12px; color: #475569; text-transform: uppercase; letter-spacing: .5px; margin-bottom: 4px; }
          .row code { background: #f1f5f9; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
          button { width: 100%; padding: 14px; border: none; border-radius: 10px; background: #2563eb; color: #fff; font-weight: 700; font-size: 16px; margin: 10px 0; cursor: pointer; }
          button:disabled { opacity: .6; }
          .ok    { background: #d1fae5; border-color: #6ee7b7; color: #047857; }
          .err   { background: #fee2e2; border-color: #fca5a5; color: #991b1b; }
          pre { white-space: pre-wrap; word-break: break-all; font-size: 12px; margin: 0; }
        </style>
      </head>
      <body>
        <h1>🔍 Diagnóstico de rede</h1>

        <div class="row"><strong>URL atual</strong><span id="here"></span></div>
        <div class="row"><strong>User agent</strong><span id="ua"></span></div>
        <div class="row"><strong>online</strong><span id="online"></span></div>

        <button id="run">▶ Rodar bateria de testes</button>

        <div id="results"></div>

        <script>
          document.getElementById('here').textContent  = location.href;
          document.getElementById('ua').textContent    = navigator.userAgent;
          document.getElementById('online').textContent = navigator.onLine ? 'true' : 'false';

          const results = document.getElementById('results');
          function add(label, ok, detail) {
            const div = document.createElement('div');
            div.className = 'row ' + (ok ? 'ok' : 'err');
            div.innerHTML = '<strong>' + (ok ? '✓ ' : '✗ ') + label + '</strong><pre>' + detail + '</pre>';
            results.appendChild(div);
          }

          async function tryFetch(label, url, opts = {}) {
            const t0 = performance.now();
            try {
              const r = await fetch(url, opts);
              const text = await r.text();
              const ms = (performance.now() - t0).toFixed(0);
              add(label, r.ok, 'status=' + r.status + ' tempo=' + ms + 'ms\\nbody=' + text.slice(0, 300));
              return { ok: r.ok, status: r.status, text };
            } catch (e) {
              const ms = (performance.now() - t0).toFixed(0);
              add(label, false, 'EXCEÇÃO após ' + ms + 'ms\\nname=' + e.name + '\\nmessage=' + e.message);
              return { ok: false, error: e };
            }
          }

          document.getElementById('run').addEventListener('click', async () => {
            results.innerHTML = '';
            const btn = document.getElementById('run');
            btn.disabled = true; btn.textContent = 'Rodando…';

            // 1. Same-origin GET (rota relativa, vai pra mesma URL)
            await tryFetch('1. GET /portal-diag/ping (mesma origem, relativo)', '/portal-diag/ping');

            // 2. Same-origin POST (a chamada que falha)
            await tryFetch('2. POST /api/v1/patient_portal/auth/request_otp (relativo)', '/api/v1/patient_portal/auth/request_otp', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ identifier: 'diag@example.com', channel: 'email' })
            });

            // 3. Absolute via location.origin (caso o relativo esteja resolvendo errado)
            await tryFetch('3. POST com URL absoluta (location.origin)', location.origin + '/api/v1/patient_portal/auth/request_otp', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ identifier: 'diag@example.com', channel: 'email' })
            });

            // 4. Hardcoded trycloudflare URL
            await tryFetch('4. POST direto na URL do tunnel', 'https://sheer-redhead-life-replied.trycloudflare.com/api/v1/patient_portal/auth/request_otp', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ identifier: 'diag@example.com', channel: 'email' })
            });

            btn.disabled = false; btn.textContent = '▶ Rodar bateria de testes';
          });
        </script>
      </body>
      </html>
    HTML
  end
end
