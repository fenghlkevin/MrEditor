export function installSearch(output: HTMLElement) {
    const bar = document.createElement('div'); bar.className = 'preview-search';
    const field = document.createElement('input'); field.type = 'search'; field.placeholder = '搜索文档'; field.setAttribute('aria-label',field.placeholder);
    const count = document.createElement('span'); count.className = 'search-count'; count.setAttribute('role','status');
    let marks: HTMLElement[] = [], current = -1, timer: ReturnType<typeof setTimeout>;
    function clear() { output.querySelectorAll('mark[data-preview-search]').forEach(m=>m.replaceWith(document.createTextNode(m.textContent ?? ''))); output.normalize(); marks=[]; current=-1; }
    function select(offset: number) { if(!marks.length) return; marks[current]?.classList.remove('current-match'); current=(current+offset+marks.length)%marks.length; marks[current].classList.add('current-match'); marks[current].scrollIntoView({block:'center'}); count.textContent=`${current+1} / ${marks.length}${marks.length===2000?'+':''}`; }
    function search(scroll=true) {
        clear(); const q=field.value.toLocaleLowerCase(); if(!q) {count.textContent=''; return;}
        output.querySelectorAll('details').forEach(d=>d.open=true);
        const walker=document.createTreeWalker(output,NodeFilter.SHOW_TEXT); const nodes: Text[]=[]; let n: Node|null;
        while((n=walker.nextNode())) { const t=n as Text; if(!t.parentElement?.closest('button, input, .line-numbers, [aria-hidden="true"]')) nodes.push(t); }
        for(const node of nodes) { const text=node.data, lower=text.toLocaleLowerCase(); let start=0, index=lower.indexOf(q); if(index<0) continue; const fragment=document.createDocumentFragment(); while(index>=0 && marks.length<2000) {fragment.append(text.slice(start,index)); const mark=document.createElement('mark'); mark.dataset.previewSearch='true'; mark.textContent=text.slice(index,index+q.length); fragment.append(mark); marks.push(mark); start=index+q.length; index=lower.indexOf(q,start); } fragment.append(text.slice(start)); node.replaceWith(fragment); if(marks.length>=2000) break; }
        count.textContent=`0 / ${marks.length}${marks.length===2000?'+':''}`; if(scroll) select(1);
    }
    function button(label: string, path: string, action:()=>void) {
        const b = document.createElement('button'); b.type = 'button'; b.title = label; b.setAttribute('aria-label', label);
        b.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}"/></svg>`;
        b.onclick = action; return b;
    }
    field.oninput=()=>{clearTimeout(timer);timer=setTimeout(()=>search(),120);};
    field.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();select(e.shiftKey?-1:1);} if(e.key==='Escape'){field.value='';clear();count.textContent='';field.blur();e.stopPropagation();}};
    const box = document.createElement('div'); box.className = 'search-field';
    const icon = document.createElement('span'); icon.className = 'search-symbol'; icon.setAttribute('aria-hidden','true');
    icon.innerHTML = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>';
    box.append(icon, field, count, button('清除搜索', 'M7 7l10 10M17 7 7 17',()=>{field.value='';clear();count.textContent='';field.focus();}));
    bar.append(box, button('上一处（Shift+Enter）','m6 14 6-6 6 6',()=>select(-1)),button('下一处（Enter）','m6 10 6 6 6-6',()=>select(1)));
    document.body.insertBefore(bar,output);
    output.addEventListener('preview-content-changed',()=>search(false));
    document.addEventListener('keydown',e=>{if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='f'){e.preventDefault();field.focus();field.select();}});
    return {refresh:()=>search(false),clear,bar};
}
