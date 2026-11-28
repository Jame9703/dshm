import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const MARKER = 'DSHM_ACCOUNT_CONTACT_DOCUMENT';
const APPLY = 'function apply(ctx, config) {';
const CONFIG = [
  'value: {',
  '\t\t\t\tcontactFormUrl: config.contactFormUrl,',
  '\t\t\t\tcontactSource: config.contactSource',
  '\t\t\t}'
].join('\n');

export function patchAccountContactDocument(stage) {
  const directory = join(stage, 'node_modules', '@deepseek-ai', 'dsh-client-ui-settings-account');
  const target = join(directory, 'lib', 'index.js');
  const source = readFileSync(target, 'utf8');
  if (source.includes(MARKER)) { return; }
  const version = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8')).version;
  if (typeof version !== 'string' || !version || source.split(APPLY).length !== 2 ||
    source.split(CONFIG).length !== 2) {
    throw new Error('Account feedback configuration changed upstream');
  }
  const route = `
	// ${MARKER}: share the live public options with the native desktop menu.
	const readContactConfig = () => ({
		contactFormUrl: config.contactFormUrl,
		contactSource: config.contactSource
	});
	ctx.inject(["webServer"], (scope) => {
		scope.effect(() => scope.webServer.register({
			kind: "exact",
			path: "/api/dshm.account.contact",
			auth: "required",
			handler(request, response) {
				if (request.method !== "GET") {
					response.writeHead(405, { allow: "GET" });
					response.end();
					return;
				}
				response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
				response.end(JSON.stringify({ ...readContactConfig(), clientVersion: ${JSON.stringify(version)} }));
			}
		}));
	});`;
  writeFileSync(target, source.replace(CONFIG, 'value: readContactConfig()')
    .replace(APPLY, () => APPLY + route), 'utf8');
}
