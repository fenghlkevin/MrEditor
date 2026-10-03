#!/usr/bin/env python3
"""Build the offline guide from docs/user-guide.md (stdlib only)."""
import html, re, shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'docs/user-guide.md'
out = ROOT / 'Sources/MrEditorCore/Resources/UserGuide'

def inline(text):
    text = html.escape(text)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    return text

def build():
    out.mkdir(parents=True, exist_ok=True)
    # Bundle only assets referenced by the current guide; discard obsolete screenshots.
    image_dir = out / 'images'
    if image_dir.exists(): shutil.rmtree(image_dir)
    image_dir.mkdir()
    for relative in set(re.findall(r'!\[[^]]*\]\((user-guide/images/[^)]+)\)', source.read_text())):
        shutil.copy2(ROOT / 'docs' / relative, image_dir / Path(relative).name)
    chunks, toc, list_kind, table = [], [], None, False
    fence, code_lines = None, []
    def close():
        nonlocal list_kind, table
        if list_kind: chunks.append(f'</{list_kind}>'); list_kind = None
        if table: chunks.append('</tbody></table></div>'); table = False
    for line in source.read_text().splitlines():
        marker = re.match(r'^(`{3,}|~{3,})(.*)$', line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence):
                chunks.append('<pre><code>' + html.escape('\n'.join(code_lines)) + '</code></pre>')
                fence, code_lines = None, []
            else: code_lines.append(line)
            continue
        if marker:
            close(); fence = marker[1]; continue
        commands = re.fullmatch(r'<!-- commands: (.+) -->', line)
        if commands:
            close()
            chunks.extend('<span hidden data-command="' + html.escape(command) + '"></span>' for command in commands[1].split())
            continue
        if not line.strip(): close(); continue
        heading = re.match(r'^(#{1,3}) (.+)', line)
        if heading:
            close(); level = len(heading[1]); title = heading[2]
            anchor = 'chapter-' + str(len(toc) + 1) if level == 2 else 'title-' + str(len(chunks))
            if level == 2: toc.append((anchor, title))
            chunks.append(f'<h{level} id="{anchor}">{inline(title)}</h{level}>'); continue
        image = re.fullmatch(r'!\[([^]]*)\]\(([^)]+)\)', line)
        if image:
            close(); relative = image[2].replace('user-guide/', '')
            if not (out / relative).is_file(): raise ValueError(f'Missing image: {relative}')
            chunks.append(f'<figure><img loading="lazy" src="{html.escape(relative)}" alt="{html.escape(image[1])}"><figcaption>{inline(image[1])}</figcaption></figure>'); continue
        if line.startswith('|'):
            close_list = list_kind
            if close_list: chunks.append(f'</{close_list}>'); list_kind = None
            cells = [x.strip() for x in line.strip('|').split('|')]
            if all(re.fullmatch(r':?-+:?', x) for x in cells): continue
            if not table:
                chunks.append('<div class="table"><table><thead><tr>' + ''.join('<th>'+inline(c)+'</th>' for c in cells) + '</tr></thead><tbody>'); table = True
            else: chunks.append('<tr>' + ''.join('<td>'+inline(c)+'</td>' for c in cells) + '</tr>')
            continue
        item = re.match(r'^(\d+\. |[-*] )(.+)', line)
        if item:
            kind = 'ol' if item[1][0].isdigit() else 'ul'
            if table: close()
            if list_kind != kind: close(); chunks.append(f'<{kind}>'); list_kind = kind
            chunks.append('<li>'+inline(item[2])+'</li>'); continue
        close(); chunks.append('<p>'+inline(line)+'</p>')
    if fence: raise ValueError('Unclosed code fence')
    close()
    links = ''.join(f'<a href="#{anchor}">{inline(title)}</a>' for anchor,title in toc)
    css = '''html{scroll-behavior:smooth}body{margin:0;background:#f7f8fb;color:#243047;font:16px/1.8 -apple-system,BlinkMacSystemFont,sans-serif}nav{position:fixed;inset:0 auto 0 0;width:235px;padding:24px 18px;overflow:auto;background:#eaf0f7;box-sizing:border-box}nav strong{font-size:23px;display:block;margin-bottom:18px}nav a{display:block;padding:6px 0;color:#31557b;text-decoration:none;font-size:14px;line-height:1.55}nav a:hover{text-decoration:underline}main{max-width:940px;margin-left:235px;padding:35px 45px 90px}h1{font-size:34px;line-height:1.3}h2{font-size:25px;margin-top:60px;border-top:1px solid #d9e2ef;padding-top:25px;scroll-margin-top:20px}h3{font-size:20px;margin-top:32px}li{margin:9px 0}code{background:#e7edf4;padding:2px 5px;border-radius:4px;font-size:14px;overflow-wrap:anywhere}figure{margin:25px 0;padding:12px;background:white;border:1px solid #dce3ee;border-radius:10px}img{display:block;width:100%;height:auto}figcaption{font-size:13px;color:#576879;margin-top:10px}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;border:1px solid #d7e0ec;padding:9px}th{background:#eaf0f7}.table{overflow:auto}p{overflow-wrap:anywhere}pre{overflow:auto;padding:18px;border-radius:8px;background:#e7edf4;line-height:1.6}pre code{padding:0;white-space:pre;overflow-wrap:normal}@media(prefers-color-scheme:dark){pre{background:#303c50}}@media(max-width:760px){nav{position:static;width:auto}main{margin:0;padding:20px}}@media(prefers-color-scheme:dark){body{background:#1b2029;color:#e2e9f3}nav,th{background:#252e3c}nav a{color:#aacaf4}code{background:#303c50}figure{background:#252e3c}figcaption{color:#b8c7d9}}@media print{nav{display:none}main{margin:0;padding:0}h2{break-before:page}figure,li{break-inside:avoid}}'''
    document = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src \'self\' data:; style-src \'unsafe-inline\'"><title>TextStack 功能使用说明</title><style>'+css+'</style><nav aria-label="目录"><strong>TextStack</strong>'+links+'</nav><main>'+''.join(chunks)+'</main></html>'
    (out / 'index.html').write_text(document)
    (ROOT / 'docs/user-guide/index.html').write_text(document)
    print(f'Guide built: {len(toc)} chapters, {len(list((out / "images").iterdir()))} images')
if __name__ == '__main__': build()
