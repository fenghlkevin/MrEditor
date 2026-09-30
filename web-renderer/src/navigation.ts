// SPDX-License-Identifier: MIT
/** Navigation is derived from the sanitized DOM, never from a second token tree. */
export class HeadingNavigation {
    private readonly button = document.createElement('button');
    private readonly panel = document.createElement('nav');
    private readonly title = document.createElement('div');
    private readonly list = document.createElement('ol');
    private entries: {heading: HTMLElement; link: HTMLAnchorElement}[] = [];
    private expanded = false;
    private scheduled = false;
    private readonly resize: ResizeObserver | undefined;

    constructor(private readonly host: HTMLElement, private readonly content: HTMLElement) {
        this.button.className = 'toc-toggle';
        this.button.type = 'button';
        this.button.innerHTML = '<svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true"><path d="M3 5h14M3 10h14M3 15h14" fill="none" stroke="currentColor" stroke-width="2"/></svg>';
        this.button.setAttribute('aria-controls', 'preview-contents');
        this.panel.id = 'preview-contents';
        this.panel.className = 'toc-nav';
        this.title.className = 'toc-title';
        this.list.className = 'toc-list';
        this.panel.append(this.title, this.list);
        this.host.replaceChildren(this.button, this.panel);
        this.button.onclick = () => this.setExpanded(!this.expanded);
        this.panel.addEventListener('keydown', event => {
            if (event.key === 'Escape') { this.setExpanded(false); this.button.focus(); }
        });
        this.list.addEventListener('click', event => {
            const link = (event.target as Element).closest<HTMLAnchorElement>('a');
            const entry = this.entries.find(entry => entry.link === link);
            if (!entry) return;
            event.preventDefault(); event.stopPropagation();
            entry.heading.scrollIntoView({behavior: 'smooth', block: 'start'});
            this.mark(entry.heading);
        });
        window.addEventListener('scroll', this.schedule, {passive: true});
        window.addEventListener('resize', this.schedule, {passive: true});
        this.resize = typeof ResizeObserver === 'undefined' ? undefined : new ResizeObserver(this.schedule);
        this.resize?.observe(content);
        this.setExpanded(false);
    }

    private setExpanded(value: boolean): void {
        this.expanded = value;
        this.panel.classList.toggle('visible', value);
        this.panel.hidden = !value;
        this.button.setAttribute('aria-expanded', String(value));
    }

    private mark(heading: HTMLElement): void {
        for (const entry of this.entries) {
            const active = entry.heading === heading;
            entry.link.classList.toggle('active', active);
            if (active) entry.link.setAttribute('aria-current', 'location');
            else entry.link.removeAttribute('aria-current');
        }
    }

    private schedule = (): void => {
        if (this.scheduled) return;
        this.scheduled = true;
        requestAnimationFrame(() => {
            this.scheduled = false;
            if (!this.entries.length) return;
            const boundary = (document.querySelector('.preview-search')?.getBoundingClientRect().bottom ?? 46) + 16;
            let current = this.entries[0].heading;
            for (const entry of this.entries) {
                if (entry.heading.getBoundingClientRect().top > boundary) break;
                current = entry.heading;
            }
            this.mark(current);
        });
    };

    refresh(language: string, enabled = true): void {
        const label = language.startsWith('zh') ? '目录' : language.startsWith('ja') ? '目次' : 'Contents';
        this.title.textContent = label;
        this.button.title = label;
        this.button.setAttribute('aria-label', label);
        this.panel.setAttribute('aria-label', label);
        this.entries = [];
        this.list.replaceChildren();
        const used = new Set(Array.from(this.content.querySelectorAll('[id]'), node => node.id));
        let generated = 0;
        const assigned = new Set<string>();
        if (enabled) for (const heading of this.content.querySelectorAll<HTMLElement>('h1,h2,h3,h4,h5,h6')) {
            if (!heading.id || assigned.has(heading.id)) {
                do { heading.id = `preview-heading-${++generated}`; } while (used.has(heading.id));
                used.add(heading.id);
            }
            assigned.add(heading.id);
            const link = document.createElement('a');
            link.className = 'toc-link';
            link.href = `#${encodeURIComponent(heading.id)}`;
            link.textContent = heading.textContent?.trim() || '…';
            link.title = link.textContent;
            const level = Number(heading.tagName[1]);
            link.dataset.level = String(level);
            link.style.setProperty('--heading-indent', `${Math.min(4, level - 1) * 16}px`);
            const item = document.createElement('li');
            item.append(link); this.list.append(item);
            this.entries.push({heading, link});
        }
        this.host.hidden = !this.entries.length;
        this.setExpanded(this.expanded);
        this.schedule();
    }
}
