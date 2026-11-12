// CRM sign-in for the Dataverse Alchemist Playwright tests.
// Opens a visible browser on a dedicated profile (<dir>/profile-<env>), waits for the user to be signed in
// (app loaded), then saves the session to <dir>/auth-<env>.json. <dir>: --dir, by default
// .alchemist/playwright of the current folder (Invoke-AlchemistUiTests.ps1 passes the CRM project one).
// If the profile session is still valid, nothing has to be entered.
// Usage: node login.mjs --url https://org.crm4.dynamics.com --env dev [--dir <folder>] [--channel msedge] [--timeout 300]
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) { acc.push([a.slice(2), all[i + 1]]); }
    return acc;
}, []));
const url = (args.url || process.env.ALCHEMIST_CRM_URL || '').replace(/\/$/, '');
const env = args.env || 'default';
const timeoutMs = Number(args.timeout || 300) * 1000;
if (!url) { console.error('Missing --url parameter'); process.exit(2); }

const root = path.resolve(args.dir || path.join(process.cwd(), '.alchemist', 'playwright'));
fs.mkdirSync(root, { recursive: true });
const profileDir = path.join(root, `profile-${env}`);
const statePath = path.join(root, `auth-${env}.json`);
const host = new URL(url).host;

const context = await chromium.launchPersistentContext(profileDir, { channel: args.channel || 'msedge', headless: false, viewport: null, args: ['--start-maximized'] });
const page = context.pages()[0] || await context.newPage();
await page.goto(`${url}/main.aspx`);
console.log(`Waiting for sign-in to ${host} (${timeoutMs / 1000} s max)…`);
try {
    await page.waitForFunction((h) => location.host === h && !!(window.Xrm && window.Xrm.Utility), host, { timeout: timeoutMs, polling: 1000 });
    await context.storageState({ path: statePath });
    console.log(JSON.stringify({ status: 'connected', statePath }));
} catch (e) {
    console.error(JSON.stringify({ status: 'timeout', message: e.message }));
    process.exitCode = 1;
} finally {
    await context.close();
}



