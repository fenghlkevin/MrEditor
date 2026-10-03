import { cp, mkdir, readFile, rm, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.join(root, 'dist');
const files = ['index.html', 'styles.css', 'app.js', 'favicon.svg', '_headers', 'assets'];
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
for (const file of files) await cp(path.join(root, file), path.join(output, file), { recursive: true });
const html = await readFile(path.join(output, 'index.html'), 'utf8');
for (const [, reference] of html.matchAll(/(?:src|href)="([^"#]+)"/g)) {
  if (/^(https?:|mailto:|data:)/.test(reference)) continue;
  await stat(path.join(output, reference));
}
if (/\.dmg|checkout|buy\.polar|lemonsqueezy/i.test(html)) throw new Error('展示版本不能包含安装包或付款链接。');
console.log('TextStack 展示页面构建完成。全部本地资源已校验；不包含安装包或付款链接。');
console.log(output);
