const demos = {
  logs: {
    filename: 'application.log', view: '日志视图', status: 'UTF-8 <b>·</b> 跟随末尾', caption: '从海量日志里，只看真正重要的那几行。',
    content: `<div class="log-search"><span aria-hidden="true">⌕</span><span class="search-term">ERROR | WARN</span><span class="match-count">包含上下文</span></div><div class="log-lines">
      <div class="log-row"><span class="line-number">1280</span><span class="timestamp">09:41:02.118</span><span class="info">INFO </span><span class="log-message">server started on port 8080</span></div>
      <div class="log-row"><span class="line-number">1281</span><span class="timestamp">09:41:02.305</span><span class="info">INFO </span><span class="log-message">database connection established</span></div>
      <div class="log-row highlight"><span class="line-number">1284</span><span class="timestamp">09:41:03.842</span><span class="error">ERROR</span><span class="log-message">payment timeout · request_id=8f2a</span></div>
      <div class="log-row"><span class="line-number">1285</span><span class="timestamp">09:41:03.843</span><span class="warn">WARN </span><span class="log-message">retry scheduled in 3000ms</span></div>
      <div class="log-row"><span class="line-number">1288</span><span class="timestamp">09:41:06.851</span><span class="info">INFO </span><span class="log-message">request completed · status=200</span></div>
      <div class="log-row highlight"><span class="line-number">1291</span><span class="timestamp">09:41:08.402</span><span class="error">ERROR</span><span class="log-message">payment declined · status=402</span></div>
      <div class="log-row"><span class="line-number">1292</span><span class="timestamp">09:41:08.409</span><span class="info">INFO </span><span class="log-message">trace saved · /var/log/application.log</span></div>
    </div>`
  },
  markdown: {
    filename: 'release-notes.md', view: '源码 / 预览', status: 'Markdown <b>·</b> 同步滚动', caption: '从源码到成稿，让想法在眼前成形。',
    content: `<div class="code-split"><div class="code-pane"><span class="syntax-blue"># 发布笔记</span>\n\n让复杂文本，变得清晰。\n\n<span class="syntax-blue">## 这次更新</span>\n\n<span class="syntax-green">- [x]</span> Markdown 实时预览\n<span class="syntax-green">- [x]</span> JSON 树与表格视图\n<span class="syntax-green">- [x]</span> 并排差异比较\n\n<span class="syntax-yellow">&gt; 从阅读到编辑，保持专注。</span>\n\n<span class="syntax-purple">\`\`\`mermaid</span>\nflowchart LR\n  A[打开] --&gt; B[编辑] --&gt; C[预览]\n<span class="syntax-purple">\`\`\`</span></div><div class="md-preview"><h3>发布笔记</h3><p>让复杂文本，变得清晰。</p><h4>这次更新</h4><p>☑ Markdown 实时预览<br>☑ JSON 树与表格视图<br>☑ 并排差异比较</p><div class="note-box">从阅读到编辑，保持专注。</div><div class="mini-flow"><span>打开</span><b>→</b><span>编辑</span><b>→</b><span>预览</span></div></div></div>`
  },
  json: {
    filename: 'config.json', view: 'JSON 检查器', status: 'JSON <b>·</b> 结构视图', caption: '展开结构，找到字段。数据不必挤成一行。',
    content: `<div class="code-split"><div class="code-pane">{\n  <span class="syntax-blue">"app"</span>: <span class="syntax-green">"TextStack"</span>,\n  <span class="syntax-blue">"editor"</span>: {\n    <span class="syntax-blue">"theme"</span>: <span class="syntax-green">"system"</span>,\n    <span class="syntax-blue">"fontSize"</span>: <span class="syntax-yellow">14</span>,\n    <span class="syntax-blue">"wordWrap"</span>: <span class="syntax-purple">true</span>\n  },\n  <span class="syntax-blue">"preview"</span>: {\n    <span class="syntax-blue">"markdown"</span>: <span class="syntax-purple">true</span>,\n    <span class="syntax-blue">"mermaid"</span>: <span class="syntax-purple">true</span>,\n    <span class="syntax-blue">"math"</span>: <span class="syntax-purple">true</span>\n  }\n}</div><div class="json-tree"><div class="tree-label">JSON 树</div><div class="tree-row">⌄ root <span class="tree-type">Object · 3 项</span></div><div class="tree-row nested">app <span class="tree-value">"TextStack"</span></div><div class="tree-row nested">⌄ editor <span class="tree-type">Object</span></div><div class="tree-row deep">theme <span class="tree-value">"system"</span></div><div class="tree-row deep">fontSize <span class="syntax-yellow tree-value">14</span></div><div class="tree-row deep">wordWrap <span class="syntax-purple tree-value">true</span></div><div class="tree-row nested">⌄ preview <span class="tree-type">Object</span></div><div class="tree-row deep">markdown <span class="syntax-purple tree-value">true</span></div><div class="tree-row deep">mermaid <span class="syntax-purple tree-value">true</span></div><div class="tree-row deep">math <span class="syntax-purple tree-value">true</span></div></div></div>`
  },
  diff: {
    filename: 'config.diff', view: '并排比较', status: 'UTF-8 <b>·</b> 2 处差异', caption: '并排看清变化，逐块决定保留什么。',
    content: `<div class="code-split"><div class="diff-pane"><div class="diff-heading">原始文件 · config.before.json</div><div class="diff-code"><div class="diff-line">  {</div><div class="diff-line">    "server": {</div><div class="diff-line remove">−     "timeout": <strong>3000</strong>,</div><div class="diff-line">      "port": 8080,</div><div class="diff-line remove">−     "retries": <strong>1</strong></div><div class="diff-line">    },</div><div class="diff-line">    "logging": "info"</div><div class="diff-line">  }</div></div></div><div class="diff-pane"><div class="diff-heading">合并结果 · config.after.json</div><div class="diff-code"><div class="diff-line">  {</div><div class="diff-line">    "server": {</div><div class="diff-line add">+     "timeout": <strong>5000</strong>,</div><div class="diff-line">      "port": 8080,</div><div class="diff-line add">+     "retries": <strong>3</strong></div><div class="diff-line">    },</div><div class="diff-line">    "logging": "info"</div><div class="diff-line">  }</div></div></div></div>`
  }
};

const tabs = [...document.querySelectorAll('[role="tab"]')];
function activate(mode, moveFocus = false) {
  const demo = demos[mode];
  if (!demo) return;
  tabs.forEach(tab => {
    const active = tab.dataset.mode === mode;
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
    if (active && moveFocus) tab.focus();
  });
  document.querySelectorAll('[data-file]').forEach(file => file.classList.toggle('selected', file.dataset.file === mode));
  document.getElementById('demo-panel').setAttribute('aria-labelledby', `tab-${mode}`);
  document.getElementById('demo-filename').textContent = demo.filename;
  document.getElementById('demo-view').textContent = demo.view;
  document.getElementById('demo-content').innerHTML = demo.content;
  document.getElementById('demo-status').innerHTML = demo.status;
  document.getElementById('demo-caption').textContent = demo.caption;
}

tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => activate(tab.dataset.mode));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next === undefined) return;
    event.preventDefault();
    activate(tabs[next].dataset.mode, true);
  });
});
activate('logs');
