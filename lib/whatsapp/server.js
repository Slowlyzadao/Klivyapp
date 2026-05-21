/* eslint-disable no-console */
/* eslint-disable no-restricted-syntax */
/* eslint-disable no-await-in-loop */
/* eslint-disable no-continue */
/* eslint-disable no-plusplus */
/* eslint-disable no-empty */
/* eslint-disable consistent-return */
/* eslint-disable no-promise-executor-return */

const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  Browsers,
  downloadMediaMessage,
  fetchLatestBaileysVersion,
} = require('@whiskeysockets/baileys');
const express = require('express');
const QRCode = require('qrcode');
const pino = require('pino');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { exec } = require('child_process');
const fetch = require('node-fetch');

const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Middleware global para CORS
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader(
    'Access-Control-Allow-Methods',
    'GET, POST, OPTIONS, PUT, PATCH, DELETE'
  );
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-Requested-With,content-type,Authorization'
  );

  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

const port = process.env.WHATSAPP_BRIDGE_PORT || 3002;
const CHATWOOT_BASE_URL =
  process.env.CHATWOOT_BASE_URL || 'http://localhost:3000';
const BRIDGE_BASE_URL =
  process.env.BRIDGE_BASE_URL || `http://localhost:${port}`;
const bridgeStartTime = Math.floor(Date.now() / 1000);

// ─── GERENCIADOR DE SESSÕES MULTI-INSTÂNCIA ───────────────────────────────────
// Cada inbox WhatsApp QR tem sua própria sessão isolada neste Map.
// Map<inboxId (string), SessionObject>
const sessions = new Map();

// Caminhos parametrizáveis por env. Em Docker/Easypanel devem apontar para
// um VOLUME persistente — caso contrário o container perde tudo no rebuild.
const sessionsBaseDir =
  process.env.WHATSAPP_SESSIONS_DIR || path.resolve(__dirname, 'sessions');
const mediaPath =
  process.env.WHATSAPP_MEDIA_DIR || path.resolve(__dirname, 'media_cache');

function getSessionDir(inboxId) {
  return path.join(sessionsBaseDir, String(inboxId));
}

function getAuthPath(inboxId) {
  return path.join(getSessionDir(inboxId), 'auth_info');
}

function getConfigPath(inboxId) {
  return path.join(getSessionDir(inboxId), 'config.json');
}

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

/**
 * Retorna o objeto de sessão para um inboxId.
 * Se não existir, cria um novo objeto de estado inicial.
 */
// Códigos de desconexão que indicam sessão irrecuperável sem re-scan do QR
const UNRECOVERABLE_CODES = new Set([440, 408, 515]);
const MAX_RECONNECT_ATTEMPTS = 5;
const BASE_RECONNECT_DELAY_MS = 3000;

// Janela de aceitação de mensagens recebidas (timestamp original).
// Em RECONEXÃO (sessão já existia), aceitamos uma janela larga (default 7 dias)
// pra cobrir cenários de servidor offline durante a noite/fim-de-semana — o
// WhatsApp Web bufferiza queued messages e entrega tudo no reconnect.
// Em FIRST-SCAN (creds inexistentes ou pós-reset), usamos uma janela curta:
// o Baileys pode dumpar histórico antigo via `messages.upsert` e queremos
// evitar inundar o Chatwoot com conversas de meses atrás.
const RECONNECT_MAX_MESSAGE_AGE_HOURS = parseInt(
  process.env.WHATSAPP_MAX_MESSAGE_AGE_HOURS || '168', // 168h = 7 dias
  10
);
const FIRST_SCAN_MAX_AGE_HOURS = 2;
// Tempo após `connection: open` para considerar que o sync histórico inicial
// já passou — depois disso, novas mensagens vêm pela janela larga mesmo numa
// sessão recém-escaneada.
const FIRST_SCAN_GRACE_MS = 60 * 1000;

function getSession(inboxId) {
  const key = String(inboxId);
  if (!sessions.has(key)) {
    sessions.set(key, {
      inboxId: key,
      sock: null,
      status: 'disconnected',
      lastQR: null,
      isStarting: false,
      reconnectTimeout: null,
      reconnectAttempts: 0,
      stableConnectionTimer: null,
      channelPhoneNumber: null,
      lastLivenessOk: null,
      // True enquanto a sessão está no "first-scan window" — pós-QR ou
      // pós-reset, antes do FIRST_SCAN_GRACE_MS expirar. Aciona a janela
      // curta no filtro de timestamp pra evitar dump de histórico.
      wasFreshScan: false,
      // Cache: JID → nome exibido no WhatsApp (notify)
      contactNameCache: {},
    });
  }
  return sessions.get(key);
}

/**
 * Limpa sessões temporárias órfãs (tmp_xxx) que estão paradas há mais de 30 minutos
 */
function cleanupOrphanedSessions() {
  const now = Date.now();
  sessions.forEach((session, id) => {
    if (id.startsWith('tmp_')) {
      const timestamp = parseInt(id.replace('tmp_', ''), 10);
      if (now - timestamp > 1800000) {
        // 30 minutos
        console.log(`🧹 Removendo sessão temporária órfã: ${id}`);
        if (session.sock) {
          try {
            session.sock.ev.removeAllListeners();
          } catch (e) {}
          try {
            session.sock.end();
          } catch (e) {}
        }
        sessions.delete(id);
        // Tenta apagar a pasta também
        try {
          const dir = getSessionDir(id);
          if (fs.existsSync(dir)) {
            fs.rmSync(dir, { recursive: true, force: true });
          }
        } catch (e) {}
      }
    }
  });
}
setInterval(cleanupOrphanedSessions, 600000); // Roda a cada 10 min

// ─── WATCHDOG ATIVO ──────────────────────────────────────────────────────────
// Baileys pode ficar em estado "zumbi": o objeto `sock` existe e o flag interno
// continua "open", mas a websocket subjacente caiu silenciosamente (NAT timeout,
// rede flutuante, suspend do host). Sem um ping ativo, NUNCA detectamos isso —
// o status reportado fica `connected` para sempre, mensagens param de chegar e
// nenhum evento `connection.update` é disparado.
//
// Estratégia: a cada 30s, tenta enviar um `presence` próprio (no-op visível
// só pra sessão). Se falhar, força o socket a fechar — disparando o fluxo
// normal de reconnect que JÁ existe no `connection.update`.
const LIVENESS_INTERVAL_MS = 30000;
const LIVENESS_TIMEOUT_MS = 8000;

async function probeSession(session) {
  if (!session.sock || session.status !== 'connected') return;
  const sock = session.sock;
  const ownJid = sock?.user?.id;
  if (!ownJid) return;

  const probe = sock.sendPresenceUpdate('available').catch(err => {
    throw err;
  });
  const timeout = new Promise((_, reject) =>
    setTimeout(() => reject(new Error('liveness timeout')), LIVENESS_TIMEOUT_MS)
  );

  try {
    await Promise.race([probe, timeout]);
    session.lastLivenessOk = Date.now();
  } catch (err) {
    console.warn(
      `[${session.inboxId}] ⚠️ Socket zumbi detectado (${err.message}). Forçando reconexão...`
    );
    try {
      sock.end(new Error('liveness probe failed'));
    } catch (e) {
      /* ignore */
    }
    // O handler `connection.update` cuidará do reconnect com backoff.
  }
}

setInterval(() => {
  sessions.forEach(session => {
    probeSession(session).catch(() => {});
  });
}, LIVENESS_INTERVAL_MS);

// ─── CACHE DE GRUPOS (COMPARTILHADO) ─────────────────────────────────────────
const groupMetadataCache = {};

// ─── CACHE DE AVATARES (COMPARTILHADO) ───────────────────────────────────────
// Mapeia JID → { url, fetchedAt }. Foto de perfil raramente muda — TTL 24h
// é generoso o bastante pra não bater no WhatsApp toda mensagem mas curto
// pra refletir mudanças num horizonte razoável.
// `null` em `url` significa "consultamos e o contato não tem foto OU bloqueou
// privacidade" — evita refetch toda mensagem pra contatos sem avatar.
const profilePicCache = new Map();
const PROFILE_PIC_TTL_MS = 24 * 60 * 60 * 1000;

async function getProfilePictureUrl(sock, jid) {
  if (!jid || jid.endsWith('@lid')) return null;
  const now = Date.now();
  const cached = profilePicCache.get(jid);
  if (cached && now - cached.fetchedAt < PROFILE_PIC_TTL_MS) {
    return cached.url;
  }
  try {
    const url = await sock.profilePictureUrl(jid, 'image');
    profilePicCache.set(jid, { url: url || null, fetchedAt: now });
    return url || null;
  } catch (e) {
    // Erro comum: 401 (privacidade bloqueia), 404 (sem foto). Cachear `null`
    // pra não tentar de novo na próxima mensagem.
    profilePicCache.set(jid, { url: null, fetchedAt: now });
    return null;
  }
}

// ─── MAPEAMENTO LID → JID (COMPARTILHADO) ────────────────────────────────────
// Vive dentro do volume de sessões para sobreviver a rebuilds.
// Migra automaticamente o arquivo legado em __dirname/lid_map.json se existir.
const lidMapPath =
  process.env.WHATSAPP_LID_MAP_PATH ||
  path.join(sessionsBaseDir, 'lid_map.json');
const lidToJidMap = {};

(function migrateLegacyLidMap() {
  try {
    const legacyPath = path.resolve(__dirname, 'lid_map.json');
    if (
      legacyPath !== lidMapPath &&
      fs.existsSync(legacyPath) &&
      !fs.existsSync(lidMapPath)
    ) {
      ensureDir(path.dirname(lidMapPath));
      fs.copyFileSync(legacyPath, lidMapPath);
      console.log(
        `📦 lid_map.json migrado: ${legacyPath} → ${lidMapPath}`
      );
    }
  } catch (e) {
    /* ignorar */
  }
})();

function loadLidMap() {
  try {
    if (fs.existsSync(lidMapPath)) {
      const data = JSON.parse(fs.readFileSync(lidMapPath, 'utf8'));
      Object.assign(lidToJidMap, data);
      console.log(
        `📋 Mapeamento LID carregado: ${Object.keys(lidToJidMap).length} entradas`
      );
    }
  } catch (e) {
    /* ignorar */
  }
}

function saveLidMap() {
  try {
    fs.writeFileSync(lidMapPath, JSON.stringify(lidToJidMap, null, 2));
  } catch (e) {
    /* ignorar */
  }
}

function registerLidMapping(lid, jid) {
  if (!lid || !jid) return;
  const lidKey = lid.split('@')[0].split(':')[0];
  const jidValue = jid.split('@')[0].split(':')[0];
  if (lidKey === jidValue) return;
  if (lidToJidMap[lidKey] !== jidValue) {
    lidToJidMap[lidKey] = jidValue;
    console.log(`🔗 [LID→JID] ${lidKey} → +${jidValue}`);
  }
}

function resolveLidToJid(senderJid) {
  const rawId = senderJid.split('@')[0].split(':')[0];
  if (lidToJidMap[rawId]) {
    const realJid = `${lidToJidMap[rawId]}@s.whatsapp.net`;
    console.log(`🔄 [LID→JID] Traduzido: ${senderJid} → ${realJid}`);
    return realJid;
  }
  return senderJid;
}

// Resolução autoritativa via SignalRepository do Baileys (preferida sobre o
// cache local quando disponível). O cache local só sabe de contatos que
// estavam em grupos comuns escaneados; o SignalRepository sabe de qualquer
// mapping LID↔PN que o WhatsApp já tenha sincronizado para esta sessão.
async function resolveLidViaBaileys(sock, jid) {
  if (!jid || !jid.endsWith('@lid')) return null;
  try {
    const pn = await sock?.signalRepository?.lidMapping?.getPNForLID?.(jid);
    if (pn && pn !== jid) {
      // Atualiza nosso cache local para próximas chamadas usarem o caminho rápido
      registerLidMapping(jid, pn);
      console.log(`🔓 [LID→JID via Baileys] ${jid} → ${pn}`);
      return pn;
    }
  } catch (e) {
    /* ignore — best-effort */
  }
  return null;
}

// Pré-popula o LID mapping para um phone JID. Útil ao enviar a primeira
// mensagem para um contato novo: garante que quando ele responder (e o
// WhatsApp Web entregar a resposta com LID), nós conseguiremos resolver.
async function ensureLidMappingForPhone(sock, phoneJid) {
  if (!phoneJid || !phoneJid.endsWith('@s.whatsapp.net')) return;
  try {
    const lid = await sock?.signalRepository?.lidMapping?.getLIDForPN?.(phoneJid);
    if (lid) {
      registerLidMapping(lid, phoneJid);
      console.log(`📌 [PN→LID pré-cache] ${phoneJid} ↔ ${lid}`);
    }
  } catch (e) {
    /* ignore — best-effort */
  }
}

async function scanGroupForLidMappings(sock, groupJid) {
  try {
    const metadata = await sock.groupMetadata(groupJid);
    if (metadata?.participants) {
      for (const p of metadata.participants) {
        if (p.id?.endsWith('@lid') && p.phoneNumber) {
          registerLidMapping(p.id, p.phoneNumber);
        } else if (p.lid && p.id && !p.id.endsWith('@lid')) {
          registerLidMapping(p.lid, p.id);
        }
      }
    }
    return metadata;
  } catch (e) {
    console.warn(`⚠️ Falha ao escanear grupo ${groupJid}:`, e.message);
    return null;
  }
}

// ─── CACHE DE MÍDIA TEMPORÁRIA (COMPARTILHADO) ────────────────────────────────
ensureDir(mediaPath);
app.use('/media', express.static(mediaPath));

function cleanOldMedia() {
  const now = Date.now();
  try {
    const files = fs.readdirSync(mediaPath);
    for (const file of files) {
      const filePath = path.join(mediaPath, file);
      const stat = fs.statSync(filePath);
      if (now - stat.mtimeMs > 3600000) {
        fs.unlinkSync(filePath);
      }
    }
  } catch (e) {
    /* ignorar */
  }
}
setInterval(cleanOldMedia, 300000);

// ─── DOWNLOAD E CACHE TEMPORÁRIO DE MÍDIA ─────────────────────────────────────
async function downloadAndCacheMedia(sock, msg) {
  try {
    let type;
    let mimeType;
    let ext;

    if (msg.message?.imageMessage) {
      type = 'image';
      mimeType = msg.message.imageMessage.mimetype || 'image/jpeg';
      ext = mimeType.split('/')[1]?.split(';')[0] || 'jpg';
    } else if (msg.message?.audioMessage) {
      type = 'audio';
      mimeType = msg.message.audioMessage.mimetype || 'audio/ogg; codecs=opus';
      ext = 'ogg';
    } else if (msg.message?.stickerMessage) {
      type = 'sticker';
      mimeType = msg.message.stickerMessage.mimetype || 'image/webp';
      ext = 'webp';
    } else if (msg.message?.videoMessage) {
      type = 'video';
      mimeType = msg.message.videoMessage.mimetype || 'video/mp4';
      ext = 'mp4';
    } else if (msg.message?.documentMessage) {
      type = 'document';
      mimeType =
        msg.message.documentMessage.mimetype || 'application/octet-stream';
      const origName = msg.message.documentMessage.fileName || 'document';
      ext = origName.includes('.') ? origName.split('.').pop() : 'bin';
    } else {
      return null;
    }

    console.log(`⬇️  Baixando mídia tipo=${type} (${mimeType})...`);

    const buffer = await downloadMediaMessage(
      msg,
      'buffer',
      {},
      {
        logger: pino({ level: 'silent' }),
        reuploadRequest: sock?.updateMediaMessage,
      }
    );

    const fileId = crypto.randomUUID();
    const filename =
      msg.message?.documentMessage?.fileName || `${type}_${fileId}.${ext}`;
    const safeFilename = `${fileId}.${ext}`;
    const filePath = path.join(mediaPath, safeFilename);
    fs.writeFileSync(filePath, buffer);

    const mediaUrl = `${BRIDGE_BASE_URL}/media/${safeFilename}`;
    console.log(
      `✅ Mídia salva: ${(buffer.length / 1024).toFixed(1)} KB → ${mediaUrl}`
    );

    return {
      url: mediaUrl,
      mime_type: mimeType,
      type: type,
      filename: filename,
      size: buffer.length,
    };
  } catch (e) {
    console.error(`❌ Falha ao baixar mídia: ${e.message}`);
    return null;
  }
}

// ─── FORWARD PARA CHATWOOT ────────────────────────────────────────────────────
async function forwardMessageToChatwoot(session, messageData) {
  if (!session.channelPhoneNumber) {
    console.warn('[BRIDGE] Sem phone_number → mensagem descartada.');
    return;
  }
  const webhookUrl = `${CHATWOOT_BASE_URL}/webhooks/whatsapp_qr/${encodeURIComponent(session.channelPhoneNumber)}`;
  try {
    const ownNumber = session.sock?.user?.id?.split(':')[0];
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Forwarded-Proto': 'https',
      },
      body: JSON.stringify({
        message: messageData,
        own_number: ownNumber,
      }),
      timeout: 10000,
    });
    if (response.ok) {
      console.log(`✅ Mensagem encaminhada ao Chatwoot (${response.status})`);
    } else {
      console.error(
        `❌ Erro ao encaminhar: ${response.status} - ${await response.text()}`
      );
    }
  } catch (err) {
    console.error('❌ Falha HTTP para o Chatwoot:', err.message);
  }
}

// ─── UTILITÁRIOS DE SESSÃO ────────────────────────────────────────────────────
function loadSessionConfig(session, configPath) {
  if (fs.existsSync(configPath)) {
    try {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      session.channelPhoneNumber = config.phone_number;
      console.log(`📋 Canal configurado: ${session.channelPhoneNumber}`);
    } catch (e) {
      console.warn('⚠️  Falha ao ler config da sessão:', e.message);
    }
  }
}

function hasSavedCredentials(inboxId) {
  return fs.existsSync(path.join(getAuthPath(inboxId), 'creds.json'));
}

function wipeSessionAuth(inboxId) {
  const authPath = getAuthPath(inboxId);
  console.log(`🗑️  Limpando auth_info da sessão ${inboxId}...`);
  try {
    fs.rmSync(authPath, { recursive: true, force: true });
  } catch (e) {
    /* ignorar */
  }
  ensureDir(authPath);
  console.log(`✅ auth_info da sessão ${inboxId} limpo.`);
}

// ─── INICIALIZAÇÃO DO WHATSAPP POR SESSÃO ────────────────────────────────────
async function startWhatsApp(inboxId) {
  const session = getSession(inboxId);

  if (session.isStarting) {
    console.log(`⏳ [${inboxId}] Início já em andamento, ignorando.`);
    return;
  }
  session.isStarting = true;

  const authPath = getAuthPath(inboxId);
  const configPath = getConfigPath(inboxId);

  // Se NÃO há creds salvas, esta é uma sessão "fresh-scan" (primeiro QR ou
  // pós-reset). Janela curta de aceitação para evitar history dump.
  // Em rehydrate (creds existem), wasFreshScan permanece false → janela larga.
  session.wasFreshScan = !hasSavedCredentials(inboxId);

  try {
    ensureDir(authPath);
    loadSessionConfig(session, configPath);

    const { state, saveCreds } = await useMultiFileAuthState(authPath);

    // ╔══════════════════════════════════════════════════════════════╗
    // ║  OBRIGATÓRIO: Busca versão mais recente do WhatsApp Web      ║
    // ║  Sem isso, o WhatsApp rejeita a conexão com erro 405         ║
    // ╚══════════════════════════════════════════════════════════════╝
    let version;
    try {
      const versionPromise = fetchLatestBaileysVersion();
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('timeout')), 5000)
      );
      const versionInfo = await Promise.race([versionPromise, timeoutPromise]);
      version = versionInfo.version;
      console.log(
        `[${inboxId}] 📌 Usando versão WhatsApp Web: ${version.join('.')}`
      );
    } catch (e) {
      console.warn(
        `[${inboxId}] ⚠️  Tempo esgotado ou falha ao buscar versão mais recente do Baileys. Usando fallback seguro (2.3000.x).`
      );
      version = [2, 3000, 1033846690];
    }

    const sock = makeWASocket({
      auth: state,
      version,
      logger: pino({ level: 'silent' }),
      printQRInTerminal: false,
      browser: Browsers.ubuntu('Chrome'),
      connectTimeoutMs: 30000,
      keepAliveIntervalMs: 15000, // Ajuda a manter a conexão em redes instáveis
      retryRequestDelayMs: 250,
      maxMsgRetryCount: 5,
    });

    session.sock = sock;

    sock.ev.on('creds.update', saveCreds);

    // Rastreador de Identidade (LID → Número Real)
    sock.ev.on('contacts.update', updates => {
      for (const update of updates) {
        if (update.lid && update.id) {
          registerLidMapping(update.lid, update.id);
        }
        // Armazena o nome do WhatsApp (notify/name) no cache da sessão
        if (update.id && (update.notify || update.name)) {
          session.contactNameCache[update.id] = update.notify || update.name;
        }
      }
    });

    sock.ev.on('contacts.upsert', contacts => {
      for (const contact of contacts) {
        if (contact.lid && contact.id) {
          registerLidMapping(contact.lid, contact.id);
        }
        // Armazena o nome do WhatsApp (notify/name) no cache da sessão
        if (contact.id && (contact.notify || contact.name)) {
          session.contactNameCache[contact.id] = contact.notify || contact.name;
        }
      }
    });

    sock.ev.on('connection.update', async update => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        console.log(
          `[${session.inboxId}] 📱 Novo QR Code gerado — aguardando escaneamento...`
        );
        try {
          session.lastQR = await QRCode.toDataURL(qr);
          session.status = 'awaiting_qr';
          console.log(`[${session.inboxId}] ✅ QR pronto!`);
        } catch (qrErr) {
          console.error(
            `[${session.inboxId}] ❌ Erro QRCode.toDataURL:`,
            qrErr
          );
        }
      }

      if (connection === 'close') {
        const statusCode = lastDisconnect?.error?.output?.statusCode;
        console.log(`[${inboxId}] 🔌 Conexão fechada. Código: ${statusCode}`);

        // CRÍTICO: resetar isStarting ANTES de qualquer outra coisa
        // (previne deadlock de reconexão documentado no CHANGELOG)
        session.isStarting = false;

        // Cancela o timer de "conexão estável" se existir
        if (session.stableConnectionTimer) {
          clearTimeout(session.stableConnectionTimer);
          session.stableConnectionTimer = null;
        }

        if (session.sock) {
          try {
            session.sock.ev.removeAllListeners();
          } catch (e) {}
          try {
            session.sock.end();
          } catch (e) {}
          session.sock = null;
        }

        const isLoggedOut = statusCode === DisconnectReason.loggedOut;

        if (isLoggedOut && hasSavedCredentials(inboxId)) {
          console.log(
            `[${inboxId}] 🚪 Usuário desconectou pelo celular. Limpando sessão...`
          );
          wipeSessionAuth(inboxId);
          session.lastQR = null;
          session.status = 'disconnected';
          session.reconnectAttempts = 0;
          // Não reconecta automaticamente após logout — requer re-scan via UI
          return;
        }

        // Incrementa contador de tentativas
        session.reconnectAttempts = (session.reconnectAttempts || 0) + 1;

        // Para códigos irrecuperáveis (440=sessão expirada, 408=timeout, 515),
        // aplica limite de retries com backoff exponencial
        if (UNRECOVERABLE_CODES.has(statusCode)) {
          if (session.reconnectAttempts > MAX_RECONNECT_ATTEMPTS) {
            console.log(
              `[${inboxId}] ⛔ Máximo de ${MAX_RECONNECT_ATTEMPTS} tentativas atingido (código ${statusCode}). Sessão pausada — reconecte via UI.`
            );
            session.status = 'disconnected';
            session.lastQR = null;
            return;
          }
          const delay =
            BASE_RECONNECT_DELAY_MS * 2 ** (session.reconnectAttempts - 1);
          console.log(
            `[${inboxId}] 🔄 Reconectando em ${(delay / 1000).toFixed(0)}s (tentativa ${session.reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})...`
          );
          session.lastQR = null;
          session.status = 'disconnected';
          if (session.reconnectTimeout) clearTimeout(session.reconnectTimeout);
          session.reconnectTimeout = setTimeout(
            () => startWhatsApp(inboxId),
            delay
          );
        } else {
          // Para desconexões "normais" (rede, restart), reconecta rápido
          console.log(`[${inboxId}] 🔄 Reconectando...`);
          session.lastQR = null;
          session.status = 'disconnected';
          if (session.reconnectTimeout) clearTimeout(session.reconnectTimeout);
          session.reconnectTimeout = setTimeout(
            () => startWhatsApp(inboxId),
            3000
          );
        }
      } else if (connection === 'open') {
        session.isStarting = false;
        session.lastQR = null;
        session.status = 'connected';
        session.lastLivenessOk = Date.now();
        // Reseta o contador de tentativas APENAS se a conexão se mantiver
        // estável por 30s — impede que o loop 440 (conecta→desconecta em ~2s)
        // reinicie o contador infinitamente
        if (session.stableConnectionTimer) {
          clearTimeout(session.stableConnectionTimer);
        }
        session.stableConnectionTimer = setTimeout(() => {
          if (session.status === 'connected') {
            session.reconnectAttempts = 0;
          }
        }, 30000);

        // Fecha a janela "fresh-scan" após o grace period — depois disso,
        // mensagens serão aceitas dentro da janela larga de reconnect.
        if (session.wasFreshScan) {
          setTimeout(() => {
            if (session.wasFreshScan) {
              console.log(
                `[${inboxId}] 🔓 First-scan grace expirou. Filtro de timestamp agora usa janela ampla (${RECONNECT_MAX_MESSAGE_AGE_HOURS}h).`
              );
              session.wasFreshScan = false;
            }
          }, FIRST_SCAN_GRACE_MS);
        }
        console.log(`[${inboxId}] 🚀 WhatsApp Conectado com Sucesso!`);

        // Escaneia grupos para extrair mapeamentos LID→JID
        setTimeout(async () => {
          console.log(
            `[${inboxId}] 🔍 Escaneando grupos para mapeamentos LID→JID...`
          );
          try {
            const groups = await sock.groupFetchAllParticipating();
            const groupIds = Object.keys(groups);
            let foundMappings = 0;
            for (const gid of groupIds) {
              const g = groups[gid];
              if (g?.participants) {
                for (const p of g.participants) {
                  if (p.id?.endsWith('@lid') && p.phoneNumber) {
                    registerLidMapping(p.id, p.phoneNumber);
                    foundMappings++;
                  } else if (p.lid && p.id && !p.id.endsWith('@lid')) {
                    registerLidMapping(p.lid, p.id);
                    foundMappings++;
                  }
                }
              }
            }
            console.log(
              `[${inboxId}] ✅ ${foundMappings} participantes mapeados.`
            );
            saveLidMap();
          } catch (e) {
            console.warn(
              `[${inboxId}] ⚠️ Falha ao escanear grupos:`,
              e.message
            );
          }
        }, 5000);
      }
    });

    // ─── MAPEAMENTO LID→JID VIA CONTATOS (MENSAGENS PRIVADAS) ────────────
    sock.ev.on('contacts.upsert', contacts => {
      for (const c of contacts) {
        // c.id pode ser JID real ou LID
        if (c.lid && c.id && !c.id.endsWith('@lid')) {
          registerLidMapping(c.lid, c.id);
        } else if (c.id?.endsWith('@lid') && c.notify) {
          // Apenas registra se tiver algum identificador alternativo
        }
      }
      saveLidMap();
    });

    sock.ev.on('contacts.update', contacts => {
      for (const c of contacts) {
        if (c.lid && c.id && !c.id.endsWith('@lid')) {
          registerLidMapping(c.lid, c.id);
        }
      }
      saveLidMap();
    });

    // ─── RECEBIMENTO DE MENSAGENS ──────────────────────────────────────────
    sock.ev.on('messages.upsert', async ({ messages, type }) => {
      if (type !== 'notify') return;

      // Processa mensagens em PARALELO para não bloquear umas às outras
      const processMsg = async msg => {
        const isFromMe = !!msg.key.fromMe;

        // Filtro de idade da mensagem.
        // - First-scan (antes do grace expirar): janela curta — defesa contra
        //   o history dump que o Baileys pode fazer no primeiro QR scan.
        // - Reconnect (sessão rehidratada do volume): janela larga — cobre
        //   queued messages do WhatsApp Web após downtime longo do servidor.
        const maxAgeHours = session.wasFreshScan
          ? FIRST_SCAN_MAX_AGE_HOURS
          : RECONNECT_MAX_MESSAGE_AGE_HOURS;
        const cutoff = Math.floor(Date.now() / 1000) - maxAgeHours * 3600;
        if (msg.messageTimestamp < cutoff) {
          console.log(
            `[${session.inboxId}] ⏭️  Ignorando mensagem antiga (${Math.round((Date.now() / 1000 - msg.messageTimestamp) / 3600)}h, limite=${maxAgeHours}h, freshScan=${session.wasFreshScan})`
          );
          return;
        }
        if (msg.key.remoteJid === 'status@broadcast') return;

        // Aproveita o pushName de qualquer mensagem recebida para popular o cache de nomes
        if (!isFromMe && msg.pushName && msg.key.remoteJid) {
          session.contactNameCache[msg.key.remoteJid] = msg.pushName;
        }

        const isAudio = !!msg.message?.audioMessage;
        const isImage = !!msg.message?.imageMessage;
        const isVideo = !!msg.message?.videoMessage;
        const isSticker = !!msg.message?.stickerMessage;
        const isDocument = !!msg.message?.documentMessage;
        const isMedia =
          isAudio || isImage || isVideo || isSticker || isDocument;

        let senderJid = msg.key.participant || msg.key.remoteJid;
        const groupJid = msg.key.remoteJid.endsWith('@g.us')
          ? msg.key.remoteJid
          : null;
        let from = groupJid || msg.key.remoteJid;

        if (isFromMe) {
          const ownId = session.sock?.user?.id;
          if (ownId) {
            senderJid = `${ownId.split(':')[0]}@s.whatsapp.net`;
          }
        } else {
          // Tenta cache local primeiro; se não resolveu, consulta o
          // SignalRepository do Baileys que conhece mappings que o
          // cache local nunca viu (ex: contato 1:1 que respondeu pela
          // primeira vez).
          senderJid = resolveLidToJid(senderJid);
          if (senderJid.endsWith('@lid')) {
            const resolved = await resolveLidViaBaileys(sock, senderJid);
            if (resolved) senderJid = resolved;
          }
        }

        if (!groupJid) {
          from = resolveLidToJid(from);
          if (from.endsWith('@lid')) {
            const resolved = await resolveLidViaBaileys(sock, from);
            if (resolved) from = resolved;
          }
        }

        if (senderJid.endsWith('@lid') && !isFromMe) {
          console.warn(
            `[${session.inboxId}] ⚠️ LID não resolvido: ${senderJid}`
          );
        }

        let senderName = msg.pushName || '';
        if (isFromMe) {
          senderName = session.sock?.user?.name || senderName || 'Eu';
        }
        if (!senderName) {
          senderName =
            senderJid?.split('@')[0]?.split(':')[0] || 'Desconhecido';
        }

        let text =
          msg.message?.conversation ||
          msg.message?.extendedTextMessage?.text ||
          msg.message?.imageMessage?.caption ||
          msg.message?.videoMessage?.caption ||
          msg.message?.documentMessage?.caption ||
          null;

        if (!text && !isMedia) return;
        if (!text && isMedia) text = null;

        console.log(
          `[${session.inboxId}] ${isFromMe ? '📤' : '📩'} ${isFromMe ? '[Próprio]' : ''}${groupJid ? '[Grupo]' : ''} ${senderName}: ${text || '[mídia]'}`
        );

        let groupName = null;
        if (groupJid) {
          if (
            groupMetadataCache[groupJid] &&
            groupMetadataCache[groupJid].timestamp > Date.now() - 3600000
          ) {
            groupName = groupMetadataCache[groupJid].name;
          } else {
            try {
              const metadata = await scanGroupForLidMappings(sock, groupJid);
              if (metadata) {
                groupName = metadata.subject;
                groupMetadataCache[groupJid] = {
                  name: groupName,
                  timestamp: Date.now(),
                };
                senderJid = resolveLidToJid(senderJid);
              }
            } catch (err) {
              groupName = groupMetadataCache[groupJid]?.name || null;
            }
          }
        }

        let attachment = null;
        if (isMedia) {
          attachment = await downloadAndCacheMedia(sock, msg);
          if (!attachment) {
            if (isAudio) text = text || '[Áudio] 🎤';
            else if (isImage) text = text || '[Imagem] 📸';
            else if (isVideo) text = text || '[Vídeo] 🎥';
            else if (isSticker) text = text || '[Sticker] 🖼️';
            else if (isDocument) text = text || '[Documento] 📄';
          }
        }

        // Para mensagens from_me em privado, busca o nome do destinatário no cache
        let recipientName = null;
        if (isFromMe && !groupJid) {
          const recipientJid = msg.key.remoteJid;
          // Tenta pelo JID exato, depois por variantes (sem sufixo de dispositivo)
          recipientName =
            session.contactNameCache[recipientJid] ||
            session.contactNameCache[`${recipientJid.split('@')[0].split(':')[0]}@s.whatsapp.net`] ||
            null;
          if (recipientName) {
            console.log(`[${session.inboxId}] 👤 Nome do destinatário: ${recipientName}`);
          }
        }

        // Para 1:1: foto do remetente (ou destinatário, se from_me).
        // Para grupos: foto do participante real (já temos em senderJid).
        // Cache de 24h evita request a cada mensagem. URL retornada é
        // `https://pps.whatsapp.net/...` — pública, expira eventualmente,
        // mas o Rails baixa/anexa via ActiveStorage logo após receber.
        let senderAvatarUrl = null;
        try {
          const avatarTarget =
            isFromMe && !groupJid ? msg.key.remoteJid : senderJid;
          senderAvatarUrl = await getProfilePictureUrl(sock, avatarTarget);
        } catch (e) {
          // engolido — avatar é best-effort
        }

        // Para grupos: foto do próprio grupo (separada da foto do participante).
        let groupAvatarUrl = null;
        if (groupJid) {
          try {
            groupAvatarUrl = await getProfilePictureUrl(sock, groupJid);
          } catch (e) {
            // engolido — avatar é best-effort
          }
        }

        await forwardMessageToChatwoot(session, {
          id: msg.key.id,
          from,
          sender_jid: senderJid,
          sender_name: senderName,
          sender_avatar_url: senderAvatarUrl,
          recipient_name: recipientName,
          text,
          timestamp: msg.messageTimestamp,
          is_group: !!groupJid,
          group_name: groupName,
          group_avatar_url: groupAvatarUrl,
          attachment,
          from_me: isFromMe,
        });
      };

      await Promise.allSettled(
        messages.map(msg =>
          processMsg(msg).catch(err =>
            console.error(
              `[${inboxId}] ❌ Erro ao processar mensagem: ${err.message}`
            )
          )
        )
      );
    });
  } catch (err) {
    session.isStarting = false;
    console.error(`[${inboxId}] ❌ Erro ao iniciar WhatsApp:`, err.message);
    console.log(`[${inboxId}] 🔄 Tentando novamente em 5 segundos...`);
    if (session.reconnectTimeout) clearTimeout(session.reconnectTimeout);
    session.reconnectTimeout = setTimeout(() => startWhatsApp(inboxId), 5000);
  }
}

// ─── RE-HIDRATAR SESSÕES EXISTENTES AO INICIAR ───────────────────────────────
async function rehydrateSessions() {
  ensureDir(sessionsBaseDir);
  let entries = [];
  try {
    entries = fs
      .readdirSync(sessionsBaseDir, { withFileTypes: true })
      .filter(d => d.isDirectory() && !d.name.startsWith('tmp_'))
      .map(d => d.name);
  } catch (e) {
    console.warn('⚠️ Falha ao listar sessões existentes:', e.message);
    return;
  }

  if (entries.length === 0) {
    console.log('ℹ️  Nenhuma sessão existente para re-hidratar.');
    return;
  }

  // Filtra: só re-hidrata sessões com credenciais reais (auth_info com arquivos)
  const validEntries = entries.filter(inboxId => {
    const authDir = path.join(sessionsBaseDir, inboxId, 'auth_info');
    try {
      if (!fs.existsSync(authDir)) return false;
      const authFiles = fs.readdirSync(authDir);
      // Uma sessão válida tem pelo menos 2 arquivos de credencial
      if (authFiles.length < 2) {
        console.log(
          `⏭️  Sessão ${inboxId} pulada: auth_info tem ${authFiles.length} arquivo(s) (sem credenciais)`
        );
        // Limpa sessão fantasma automaticamente
        try {
          fs.rmSync(path.join(sessionsBaseDir, inboxId), { recursive: true, force: true });
          console.log(`🗑️  Sessão fantasma ${inboxId} removida do disco`);
        } catch (e2) { /* ignorar */ }
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  });

  if (validEntries.length === 0) {
    console.log('ℹ️  Nenhuma sessão com credenciais válidas para re-hidratar.');
    return;
  }

  console.log(
    `♻️  Re-hidratando ${validEntries.length} sessão(ões) válida(s): ${validEntries.join(', ')}`
  );
  for (const inboxId of validEntries) {
    const configPath = getConfigPath(inboxId);
    if (fs.existsSync(configPath)) {
      console.log(`♻️  Iniciando sessão: inbox ${inboxId}`);
      startWhatsApp(inboxId);
      // Pequeno delay para não sobrecarregar o startup
      await new Promise(r => setTimeout(r, 800));
    }
  }
}


// ─── ENDPOINTS ───────────────────────────────────────────────────────────────

// Listar todas as sessões ativas (útil para debug)
app.get('/sessions', (req, res) => {
  const list = [];
  sessions.forEach((session, id) => {
    list.push({
      inboxId: id,
      status: session.status,
      isStarting: session.isStarting,
      has_qr: !!session.lastQR,
      phone_number: session.channelPhoneNumber,
      socket_connected: !!session.sock,
      own_number: session.sock?.user?.id?.split(':')[0] || null,
    });
  });
  res.json({ sessions: list, total: list.length });
});

// ── QR Code de uma sessão específica
app.get('/sessions/:inboxId/qr', (req, res) => {
  const session = getSession(req.params.inboxId);

  // Se a sessão não foi iniciada ainda, iniciar agora
  if (!session.sock && !session.isStarting) {
    console.log(
      `[${req.params.inboxId}] 🆕 Sessão solicitada via /qr — iniciando...`
    );
    startWhatsApp(req.params.inboxId);
  }

  res.json({ qr: session.lastQR, status: session.status });
});

// ── Status de uma sessão específica
app.get('/sessions/:inboxId/status', (req, res) => {
  const session = getSession(req.params.inboxId);
  // "alive" = passou no último liveness probe nos últimos 90s.
  // É o sinal honesto a ser exposto na UI para evitar o estado falso
  // "UI conectado / backend morto".
  const alive =
    session.status === 'connected' &&
    !!session.sock &&
    session.lastLivenessOk &&
    Date.now() - session.lastLivenessOk < LIVENESS_INTERVAL_MS * 3;

  res.json({
    status: session.status,
    alive,
    has_qr: !!session.lastQR,
    phone_number_configured: session.channelPhoneNumber,
    socket_connected: !!session.sock,
    own_number: session.sock?.user?.id?.split(':')[0] || null,
    last_liveness_ok: session.lastLivenessOk
      ? new Date(session.lastLivenessOk).toISOString()
      : null,
    reconnect_attempts: session.reconnectAttempts || 0,
    bridge_start_time: new Date(bridgeStartTime * 1000).toISOString(),
    lid_mappings: Object.keys(lidToJidMap).length,
  });
});

// ── Healthz: usado pelo Docker healthcheck.
// Retorna 200 se o processo está vivo E todas as sessões com credenciais
// gravadas estão `connected`. Retorna 503 se houver sessão "fantasma"
// (creds no disco mas socket morto há mais de 90s) — isso fará o Docker
// marcar o container unhealthy e (se restart policy permitir) reiniciar.
app.get('/healthz', (req, res) => {
  const ghosts = [];
  sessions.forEach(session => {
    if (
      hasSavedCredentials(session.inboxId) &&
      session.status !== 'connected' &&
      !session.isStarting
    ) {
      ghosts.push({
        inboxId: session.inboxId,
        status: session.status,
        reconnect_attempts: session.reconnectAttempts || 0,
      });
    }
    if (
      session.status === 'connected' &&
      session.lastLivenessOk &&
      Date.now() - session.lastLivenessOk > LIVENESS_INTERVAL_MS * 4
    ) {
      ghosts.push({
        inboxId: session.inboxId,
        status: 'stale',
        last_liveness_ok: new Date(session.lastLivenessOk).toISOString(),
      });
    }
  });

  if (ghosts.length === 0) {
    return res.json({ ok: true, sessions: sessions.size });
  }
  res.status(503).json({ ok: false, ghosts });
});

// ── Registrar phone_number para uma sessão
app.post('/sessions/:inboxId/register', (req, res) => {
  const { phone_number } = req.body;
  if (!phone_number)
    return res.status(400).json({ error: 'phone_number obrigatório' });

  const inboxId = req.params.inboxId;
  const session = getSession(inboxId);
  session.channelPhoneNumber = phone_number;

  // Salvar config na pasta da sessão
  const sessionDir = getSessionDir(inboxId);
  ensureDir(sessionDir);
  fs.writeFileSync(getConfigPath(inboxId), JSON.stringify({ phone_number }));

  console.log(`[${inboxId}] 📋 Canal registrado: ${phone_number}`);
  res.json({ success: true });
});

// ── Verificar se um número tem WhatsApp (sem criar conversa).
// Usado pelo Rails antes de criar conversa via "Iniciar conversa por número"
// no empty state da lista. Resposta:
//   { exists: true, jid: "5511916019363@s.whatsapp.net" }
//   { exists: false }
//   { error: "not_connected" } com 503 quando o socket não está conectado
app.post('/sessions/:inboxId/check_number', async (req, res) => {
  const inboxId = req.params.inboxId;
  const session = getSession(inboxId);

  if (!session.sock || session.status !== 'connected') {
    return res.status(503).json({
      success: false,
      error: 'not_connected',
      message: `WhatsApp [${inboxId}] não está conectado`,
    });
  }

  const { phone_number } = req.body || {};
  if (!phone_number) {
    return res
      .status(400)
      .json({ success: false, error: 'phone_number obrigatório' });
  }

  const digits = String(phone_number).replace(/\D/g, '');
  if (digits.length < 8 || digits.length > 15) {
    return res
      .status(400)
      .json({ success: false, error: 'phone_number inválido' });
  }

  try {
    const probe = session.sock.onWhatsApp(`${digits}@s.whatsapp.net`);
    const timeout = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('check_number timeout')), 8000)
    );
    const results = await Promise.race([probe, timeout]);
    const first = Array.isArray(results) ? results[0] : null;

    if (first?.exists) {
      console.log(`[${inboxId}] ✅ Número ${digits} TEM WhatsApp (jid=${first.jid})`);
      // Pré-popula o LID mapping em paralelo. Quando o destinatário
      // responder pela primeira vez (já com `@lid`), nós já conheceremos
      // o phone real e não criaremos contato duplicado no Chatwoot.
      ensureLidMappingForPhone(session.sock, first.jid).catch(() => {});
      return res.json({ exists: true, jid: first.jid, digits });
    }
    console.log(`[${inboxId}] ❌ Número ${digits} NÃO tem WhatsApp`);
    return res.json({ exists: false, digits });
  } catch (err) {
    console.error(`[${inboxId}] ❌ Erro check_number ${digits}:`, err.message);
    return res
      .status(500)
      .json({ success: false, error: err.message });
  }
});

// ── Desconectar/resetar uma sessão específica
app.post('/sessions/:inboxId/disconnect', async (req, res) => {
  const inboxId = req.params.inboxId;
  const session = getSession(inboxId);

  console.log(`[${inboxId}] ⚠️  Reset completo solicitado...`);

  // Cancela reconexões pendentes
  if (session.reconnectTimeout) {
    clearTimeout(session.reconnectTimeout);
    session.reconnectTimeout = null;
  }

  // CRÍTICO: resetar isStarting ANTES de tudo
  session.isStarting = false;

  // Limpa socket
  if (session.sock) {
    try {
      session.sock.ev.removeAllListeners();
    } catch (e) {}
    try {
      session.sock.end();
    } catch (e) {}
    session.sock = null;
  }

  // Wipe da sessão de autenticação
  wipeSessionAuth(inboxId);

  // Reset estado
  session.lastQR = null;
  session.status = 'disconnected';

  console.log(`[${inboxId}] ♻️  Reiniciando para gerar novo QR...`);
  setTimeout(() => startWhatsApp(inboxId), 500);

  res.json({ success: true, message: 'Resetando...' });
});

// ── DESTRUIR completamente uma sessão (apagar TUDO do disco e memória)
app.delete('/sessions/:inboxId', async (req, res) => {
  const inboxId = String(req.params.inboxId);
  console.log(`[${inboxId}] 🗑️  DESTRUIÇÃO TOTAL da sessão solicitada...`);

  // 1. Para o socket e remove listeners
  if (sessions.has(inboxId)) {
    const session = sessions.get(inboxId);

    if (session.reconnectTimeout) {
      clearTimeout(session.reconnectTimeout);
      session.reconnectTimeout = null;
    }
    if (session.stableConnectionTimer) {
      clearTimeout(session.stableConnectionTimer);
      session.stableConnectionTimer = null;
    }
    session.isStarting = false;

    if (session.sock) {
      try { session.sock.ev.removeAllListeners(); } catch (e) {}
      try { session.sock.end(); } catch (e) {}
      session.sock = null;
    }

    // 2. Remove do Map de sessões ativas
    sessions.delete(inboxId);
    console.log(`[${inboxId}] ✅ Sessão removida da memória`);
  }

  // 3. Apaga TUDO do disco — pasta inteira
  const sessionDir = getSessionDir(inboxId);
  if (fs.existsSync(sessionDir)) {
    try {
      fs.rmSync(sessionDir, { recursive: true, force: true });
      console.log(`[${inboxId}] ✅ Pasta ${sessionDir} removida do disco`);
    } catch (e) {
      console.error(`[${inboxId}] ❌ Falha ao remover pasta: ${e.message}`);
      return res.status(500).json({
        error: `Falha ao remover arquivos: ${e.message}`,
      });
    }
  } else {
    console.log(`[${inboxId}] ℹ️  Nenhuma pasta encontrada no disco`);
  }

  console.log(`[${inboxId}] 💀 Sessão DESTRUÍDA permanentemente.`);
  res.json({
    success: true,
    message: `Sessão ${inboxId} destruída permanentemente`,
  });
});

// ── Migrar sessão temporária para inbox_id permanente
app.post('/sessions/:inboxId/migrate', async (req, res) => {
  const targetId = String(req.params.inboxId);
  const { migrate_from, phone_number } = req.body;

  if (!migrate_from) {
    return res.status(400).json({ error: 'migrate_from obrigatório' });
  }

  const fromId = String(migrate_from);
  console.log(`[MIGRATE] Preparando migração: ${fromId} → ${targetId}`);

  const fromDir = getSessionDir(fromId);
  const toDir = getSessionDir(targetId);

  // 1. Parar o socket antigo se existir para liberar arquivos
  if (sessions.has(fromId)) {
    const session = sessions.get(fromId);

    console.log(`[MIGRATE] Finalizando socket provisório de ${fromId}...`);
    if (session.reconnectTimeout) clearTimeout(session.reconnectTimeout);
    if (session.sock) {
      try {
        session.sock.ev.removeAllListeners();
        session.sock.end();
      } catch (e) {}
      session.sock = null;
    }
    session.status = 'disconnected';
    session.isStarting = false;
    session.inboxId = targetId; // Muda a identidade ANTES de mover os dados

    // 2. Mover arquivos da pasta de sessão
    if (fs.existsSync(fromDir)) {
      try {
        if (fs.existsSync(toDir)) {
          fs.rmSync(toDir, { recursive: true, force: true });
        }
        fs.renameSync(fromDir, toDir);
        console.log(`[MIGRATE] ✅ Pasta movida: ${fromDir} → ${toDir}`);
      } catch (e) {
        console.error(`[MIGRATE] ❌ Falha ao mover pasta:`, e.message);
        return res
          .status(500)
          .json({ error: 'Falha ao mover arquivos de sessão' });
      }
    }

    // 3. Atualizar phone_number e reposicionar no Map
    if (phone_number) {
      session.channelPhoneNumber = phone_number;
    }

    sessions.set(targetId, session);
    sessions.delete(fromId);
    console.log(
      `[MIGRATE] ✅ Objeto de sessão migrado: ${fromId} → ${targetId}`
    );

    // 4. Salvar config definitiva
    if (phone_number) {
      const targetConfigPath = getConfigPath(targetId);
      ensureDir(getSessionDir(targetId));
      fs.writeFileSync(targetConfigPath, JSON.stringify({ phone_number }));
    }

    // 5. Reiniciar o motor agora no ID definitivo (ID Real)
    console.log(`[MIGRATE] ♻️ Reiniciando motor para ID Real: ${targetId}`);
    startWhatsApp(targetId);

    res.json({
      success: true,
      message: `Sessão migrada e reiniciada para ${targetId}`,
    });
  } else {
    console.warn(`[MIGRATE] ⚠️ Sessão de origem ${fromId} não encontrada.`);
    res.status(404).json({ error: 'Sessão de origem não encontrada' });
  }
});

// ─── HELPER PARA CONVERSÃO DE ÁUDIO (PTT) ────────────────────────────────────
const FFMPEG_TIMEOUT_MS = 15000; // 15s máximo para converter

// WhatsApp Mobile exige o campo `seconds` no payload de PTT para tocar o áudio.
// Sem ele, o Web toca (decodifica client-side) mas o Mobile não reproduz.
function getAudioDurationSeconds(filePath) {
  return new Promise(resolve => {
    exec(
      `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${filePath}"`,
      { timeout: 5000 },
      (err, stdout) => {
        if (err) return resolve(null);
        const seconds = parseFloat(String(stdout).trim());
        resolve(Number.isFinite(seconds) && seconds > 0 ? Math.round(seconds) : null);
      }
    );
  });
}

async function downloadAndConvertAudio(url, fileId, outputDir) {
  const startMs = Date.now();
  const isLoopback = /^https?:\/\/(localhost|127\.0\.0\.1)(:|\/)/i.test(url);
  const res = await fetch(url, {
    timeout: 10000,
    headers: isLoopback ? { 'X-Forwarded-Proto': 'https' } : undefined,
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const buffer = Buffer.from(await res.arrayBuffer());
  console.log(
    `[AUDIO] Download: ${(buffer.length / 1024).toFixed(0)}KB em ${Date.now() - startMs}ms`
  );

  // Se já é OGG/Opus, não precisa converter — envia direto
  const isAlreadyOpus =
    buffer.length > 4 &&
    buffer[0] === 0x4f &&
    buffer[1] === 0x67 &&
    buffer[2] === 0x67 &&
    buffer[3] === 0x53;
  if (isAlreadyOpus) {
    const directPath = path.join(outputDir, `out_${fileId}.ogg`);
    fs.writeFileSync(directPath, buffer);
    console.log(`[AUDIO] Já é OGG/Opus — skip conversão (${Date.now() - startMs}ms total)`);
    return directPath;
  }

  const inputPath = path.join(outputDir, `in_${fileId}.tmp`);
  const outputPath = path.join(outputDir, `out_${fileId}.ogg`);
  fs.writeFileSync(inputPath, buffer);

  return new Promise((resolve, reject) => {
    exec(
      `ffmpeg -i "${inputPath}" -vn -c:a libopus -b:a 48k -application voip -vbr on "${outputPath}" -y`,
      { timeout: FFMPEG_TIMEOUT_MS },
      err => {
        try {
          fs.unlinkSync(inputPath);
        } catch (e) {
          // arquivo temporário pode já ter sido removido
        }
        if (err) {
          console.error(`[AUDIO] ffmpeg falhou em ${Date.now() - startMs}ms: ${err.message}`);
          reject(err);
        } else {
          console.log(`[AUDIO] Conversão concluída em ${Date.now() - startMs}ms`);
          resolve(outputPath);
        }
      }
    );
  });
}

// ── Enviar mensagem por uma sessão específica
app.post('/sessions/:inboxId/send', async (req, res) => {
  const inboxId = req.params.inboxId;
  const session = getSession(inboxId);

  if (!session.sock || session.status !== 'connected') {
    return res.status(503).json({
      success: false,
      error: `WhatsApp [${inboxId}] não está conectado`,
    });
  }

  let { to, type, text, url, filename, caption } = req.body || {};

  // Convert localhost to IPv4 loopback to avoid Node 18+ fetching via IPv6 (::1) and failing
  if (url && typeof url === 'string') {
    url = url.replace('http://localhost:', 'http://127.0.0.1:');
  }

  if (!to)
    return res.status(400).json({ success: false, error: '"to" obrigatório' });

  try {
    let message;
    switch (type) {
      case 'text':
        message = { text: text || '' };
        break;
      case 'image':
        message = { image: { url }, caption: caption || '' };
        break;
      case 'audio': {
        const audioStartMs = Date.now();
        console.log(`[${inboxId}] 🎵 Processando áudio...`);
        try {
          const fileId = crypto.randomUUID();
          const localOggPath = await downloadAndConvertAudio(
            url,
            fileId,
            mediaPath
          );
          const audioBuffer = fs.readFileSync(localOggPath);
          const seconds = await getAudioDurationSeconds(localOggPath);

          message = {
            audio: audioBuffer,
            mimetype: 'audio/ogg; codecs=opus',
            ptt: true,
            ...(seconds ? { seconds } : {}),
          };

          // Limpa o arquivo temporário após enviar
          setTimeout(() => {
            try {
              fs.unlinkSync(localOggPath);
            } catch (e) {}
          }, 5000);
          console.log(
            `[${inboxId}] ✅ Áudio pronto em ${Date.now() - audioStartMs}ms (${(audioBuffer.length / 1024).toFixed(0)}KB)`
          );
        } catch (audioErr) {
          console.error(
            `[${inboxId}] ❌ Falha na conversão (${Date.now() - audioStartMs}ms):`,
            audioErr.message
          );
          // Fallback: envia o áudio original como arquivo de áudio (NÃO como PTT).
          // Como PTT, o WhatsApp Mobile rejeita qualquer coisa que não seja OGG/Opus
          // com duração. Melhor entregar como arquivo que toca em qualquer cliente
          // do que uma nota de voz quebrada.
          try {
            const isLoopback = /^https?:\/\/(localhost|127\.0\.0\.1)(:|\/)/i.test(url);
            const audioRes = await fetch(url, {
              timeout: 10000,
              headers: isLoopback ? { 'X-Forwarded-Proto': 'https' } : undefined,
            });
            if (audioRes.ok) {
              const rawBuf = Buffer.from(await audioRes.arrayBuffer());
              message = {
                audio: rawBuf,
                mimetype: 'audio/mp4',
                ptt: false,
              };
              console.log(
                `[${inboxId}] 🔄 Fallback: enviando áudio original como arquivo (${(rawBuf.length / 1024).toFixed(0)}KB)`
              );
            } else {
              message = { audio: { url }, mimetype: 'audio/mp4', ptt: false };
            }
          } catch (fallbackErr) {
            message = { audio: { url }, mimetype: 'audio/mp4', ptt: false };
          }
        }
        break;
      }
      case 'video':
        message = { video: { url }, caption: caption || '' };
        break;
      case 'document':
        message = {
          document: { url },
          fileName: filename || 'arquivo',
          caption: caption || '',
        };
        break;
      default:
        message = { text: text || caption || '' };
    }

    const result = await session.sock.sendMessage(to, message);
    const msgId = result?.key?.id;
    console.log(
      `[${inboxId}] 📤 Enviado para ${to}: tipo=${type}, id=${msgId}`
    );

    // Pré-popula o LID mapping desse phone, em paralelo (best-effort).
    // Isso garante que, quando o destinatário responder, o evento
    // `messages.upsert` com sender LID seja resolvido pra phone real
    // ANTES de criar contato no Chatwoot — evitando duplicação.
    if (typeof to === 'string' && to.endsWith('@s.whatsapp.net')) {
      ensureLidMappingForPhone(session.sock, to).catch(() => {});
    }

    res.json({ success: true, id: msgId });
  } catch (err) {
    console.error(`[${inboxId}] ❌ Erro envio ${to}:`, err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─── ENDPOINT LEGADO DE COMPATIBILIDADE ──────────────────────────────────────
// Mantido para não quebrar o webhook do Chatwoot durante a transição
app.get('/status', (req, res) => {
  const sessionList = [];
  sessions.forEach((s, id) =>
    sessionList.push({ inboxId: id, status: s.status })
  );
  res.json({
    status: 'multi-instance',
    sessions: sessionList,
    total_sessions: sessionList.length,
    bridge_start_time: new Date(bridgeStartTime * 1000).toISOString(),
    lid_mappings: Object.keys(lidToJidMap).length,
  });
});

// ─── START ────────────────────────────────────────────────────────────────────
const server = app.listen(port, '0.0.0.0', () => {
  console.log(
    `\n🚀 Motor WhatsApp Bridge (Multi-Instância): http://localhost:${port}`
  );
  console.log(
    `📡 Chatwoot webhook base: ${CHATWOOT_BASE_URL}/webhooks/whatsapp_qr/<phone>`
  );
  console.log(`📂 Sessões armazenadas em: ${sessionsBaseDir}\n`);
  loadLidMap();
  rehydrateSessions();
});

server.on('error', e => {
  if (e.code === 'EADDRINUSE') {
    console.error(
      `❌ ERRO: A porta ${port} já está em uso! Existe outro motor WhatsApp rodando.`
    );
    process.exit(1);
  }
});
