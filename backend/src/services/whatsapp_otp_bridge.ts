import {
  makeWASocket,
  BufferJSON,
  DisconnectReason,
  initAuthCreds,
  proto,
} from '@whiskeysockets/baileys';
import pino from 'pino';

import { adminSupabase } from '../lib/supabase.js';

type BridgeStatus = 'DISCONNECTED' | 'CONNECTING' | 'PAIRING' | 'CONNECTED' | 'LOGGED_OUT';

type KeyStore = {
  get: (type: string, ids: string[]) => Promise<Record<string, any>>;
  set: (data: Record<string, Record<string, any>>) => Promise<void>;
};

function serialize(value: any): any {
  return JSON.parse(JSON.stringify(value, BufferJSON.replacer));
}

function deserialize(value: any): any {
  return JSON.parse(JSON.stringify(value), BufferJSON.reviver);
}

async function readState(key: string): Promise<any | null> {
  const { data, error } = await adminSupabase
    .from('whatsapp_bridge_auth')
    .select('value')
    .eq('storage_key', key)
    .maybeSingle();

  if (error) throw error;
  return data?.value == null ? null : deserialize(data.value);
}

async function writeState(key: string, value: any): Promise<void> {
  const { error } = await adminSupabase
    .from('whatsapp_bridge_auth')
    .upsert({
      storage_key: key,
      value: serialize(value),
      updated_at: new Date().toISOString(),
    }, { onConflict: 'storage_key' });

  if (error) throw error;
}

async function deleteState(key: string): Promise<void> {
  const { error } = await adminSupabase
    .from('whatsapp_bridge_auth')
    .delete()
    .eq('storage_key', key);
  if (error) throw error;
}

async function makeDatabaseAuthState(): Promise<{
  state: { creds: any; keys: KeyStore };
  saveCreds: () => Promise<void>;
}> {
  const creds = (await readState('creds')) || initAuthCreds();

  const keys: KeyStore = {
    get: async (type, ids) => {
      const result: Record<string, any> = {};
      await Promise.all(ids.map(async (id) => {
        const storageKey = `key:${type}:${id}`;
        let value = await readState(storageKey);
        if (type === 'app-state-sync-key' && value) {
          value = proto.Message.AppStateSyncKeyData.fromObject(value);
        }
        result[id] = value;
      }));
      return result;
    },
    set: async (data) => {
      const writes: Promise<void>[] = [];
      for (const [category, entries] of Object.entries(data)) {
        for (const [id, value] of Object.entries(entries || {})) {
          const storageKey = `key:${category}:${id}`;
          writes.push(value == null ? deleteState(storageKey) : writeState(storageKey, value));
        }
      }
      await Promise.all(writes);
    },
  };

  return {
    state: { creds, keys },
    saveCreds: async () => writeState('creds', creds),
  };
}

class WhatsAppOtpBridge {
  private socket: any | null = null;
  private status: BridgeStatus = 'DISCONNECTED';
  private lastError: string | null = null;
  private connectPromise: Promise<void> | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private pairingCode: string | null = null;
  private pairingPhone: string | null = null;
  private authCreds: any | null = null;

  getStatus() {
    return {
      status: this.status,
      connected: this.status === 'CONNECTED',
      paired: Boolean(this.authCreds?.registered),
      senderJid: this.authCreds?.me?.id || null,
      lastError: this.lastError,
      pairingCode: this.pairingCode,
      pairingPhone: this.pairingPhone,
    };
  }

  async start(): Promise<void> {
    if (this.connectPromise) return this.connectPromise;
    this.connectPromise = this.connectInternal()
      .catch((error: any) => {
        this.status = 'DISCONNECTED';
        this.lastError = error?.message || String(error);
        this.socket = null;
        this.scheduleReconnect(5000);
      })
      .finally(() => {
        this.connectPromise = null;
      });
    return this.connectPromise;
  }

  private scheduleReconnect(delayMs = 3000) {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      void this.start();
    }, delayMs);
  }

  private async connectInternal(): Promise<void> {
    this.status = 'CONNECTING';
    this.lastError = null;

    const { state, saveCreds } = await makeDatabaseAuthState();
    this.authCreds = state.creds;

    const socket = makeWASocket({
      auth: state as any,
      logger: pino({ level: 'silent' }) as any,
      markOnlineOnConnect: false,
      syncFullHistory: false,
      connectTimeoutMs: 60_000,
      defaultQueryTimeoutMs: 60_000,
      emitOwnEvents: false,
      generateHighQualityLinkPreview: false,
    });

    this.socket = socket;

    socket.ev.on('creds.update', async () => {
      try {
        await saveCreds();
      } catch (error: any) {
        this.lastError = `Could not persist WhatsApp credentials: ${error?.message || error}`;
      }
    });

    socket.ev.on('connection.update', (update: any) => {
      const { connection, lastDisconnect, qr } = update || {};

      if (connection === 'open') {
        this.status = 'CONNECTED';
        this.lastError = null;
        this.pairingCode = null;
        this.pairingPhone = null;
        return;
      }

      if (qr && !this.authCreds?.registered) {
        this.status = 'PAIRING';
      }

      if (connection === 'close') {
        const statusCode = lastDisconnect?.error?.output?.statusCode;
        const loggedOut = statusCode === DisconnectReason.loggedOut;

        if (loggedOut) {
          this.status = 'LOGGED_OUT';
          this.lastError = 'WhatsApp linked device was logged out. Pairing is required again.';
          this.socket = null;
          return;
        }

        this.status = 'DISCONNECTED';
        this.lastError = lastDisconnect?.error?.message || 'WhatsApp connection closed unexpectedly.';
        this.socket = null;
        this.scheduleReconnect();
      }
    });

    await new Promise((resolve) => setTimeout(resolve, 1200));
    if (this.authCreds?.registered) {
      this.status = 'CONNECTING';
    } else {
      this.status = 'PAIRING';
    }
  }

  async requestPairingCode(phoneDigits: string): Promise<string> {
    const clean = phoneDigits.replace(/\D/g, '');
    if (clean.length < 10 || clean.length > 15) {
      throw new Error('Enter the WhatsApp sender number with country code, digits only.');
    }

    await this.start();
    const socket = this.socket;
    if (!socket) throw new Error('WhatsApp bridge is not ready yet.');
    if (this.authCreds?.registered) {
      throw new Error('WhatsApp sender is already paired.');
    }

    this.pairingPhone = clean;
    this.status = 'PAIRING';

    let lastError: unknown;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        if (attempt > 1) await new Promise((resolve) => setTimeout(resolve, attempt * 1200));
        const code = await socket.requestPairingCode(clean);
        this.pairingCode = String(code);
        return this.pairingCode;
      } catch (error) {
        lastError = error;
      }
    }

    throw new Error(`Could not generate WhatsApp pairing code: ${(lastError as any)?.message || lastError}`);
  }

  async sendOtp(phoneE164: string, otp: string): Promise<{ messageId: string | null; attempts: number }> {
    const digits = phoneE164.replace(/\D/g, '');
    if (!digits) throw new Error('Invalid destination WhatsApp number.');

    const message =
      `Your ShipdeHop verification code is ${otp}.\n\n` +
      'It expires in 5 minutes. Do not share this code with anyone.';

    let lastError: unknown;

    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        await this.ensureConnected();
        const socket = this.socket;
        if (!socket) throw new Error('WhatsApp bridge is disconnected.');

        const jid = `${digits}@s.whatsapp.net`;
        const availability = await socket.onWhatsApp(jid);
        if (!availability?.[0]?.exists) {
          throw new Error('That number is not registered on WhatsApp.');
        }

        const result = await socket.sendMessage(jid, { text: message });
        const messageId = result?.key?.id?.toString() || null;
        if (!messageId) {
          throw new Error('WhatsApp did not acknowledge the OTP message.');
        }

        return { messageId, attempts: attempt };
      } catch (error) {
        lastError = error;
        this.lastError = (error as any)?.message || String(error);
        this.socket = null;
        this.status = 'DISCONNECTED';
        if (attempt < 3) {
          await new Promise((resolve) => setTimeout(resolve, attempt * 1000));
          try {
            await this.start();
          } catch {}
        }
      }
    }

    throw new Error(`WhatsApp OTP could not be sent after 3 attempts: ${(lastError as any)?.message || lastError}`);
  }

  private async ensureConnected(): Promise<void> {
    if (this.status === 'CONNECTED' && this.socket) return;

    await this.start();

    const started = Date.now();
    while (Date.now() - started < 12_000) {
      if (this.status === 'CONNECTED' && this.socket) return;
      if (this.status === 'LOGGED_OUT' || this.status === 'PAIRING') break;
      await new Promise((resolve) => setTimeout(resolve, 400));
    }

    const state = this.getStatus();
    if (!state.paired) throw new Error('WhatsApp sender is not paired yet.');
    throw new Error('WhatsApp sender is temporarily disconnected.');
  }
}

export const whatsappOtpBridge = new WhatsAppOtpBridge();
