import http2 from 'node:http2';
import { SignJWT, importPKCS8 } from 'jose';

export interface ApnsKey {
  keyId: string;
  teamId: string;
  p8: string;
}

export async function makeApnsJwt(key: ApnsKey): Promise<string> {
  const privateKey = await importPKCS8(key.p8, 'ES256');
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: key.keyId })
    .setIssuer(key.teamId)
    .setIssuedAt()
    .sign(privateKey);
}

export interface SendApnsInput {
  token: string;
  environment: 'production' | 'sandbox';
  jwt: string;
  bundleId: string;
  collapseId?: string;
  payload: unknown;
}

export interface SendApnsResult {
  status: number;
  body: string;
}

export function sendApns(input: SendApnsInput): Promise<SendApnsResult> {
  const host =
    input.environment === 'sandbox'
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com';

  return new Promise((resolve, reject) => {
    const client = http2.connect(host);
    client.on('error', reject);

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${input.token}`,
      authorization: `bearer ${input.jwt}`,
      'apns-topic': input.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
      ...(input.collapseId ? { 'apns-collapse-id': input.collapseId } : {}),
    });

    let status = 0;
    let body = '';
    req.on('response', (headers) => {
      status = Number(headers[':status']);
    });
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      client.close();
      resolve({ status, body });
    });
    req.on('error', (err) => {
      client.close();
      reject(err);
    });

    req.write(JSON.stringify(input.payload));
    req.end();
  });
}
