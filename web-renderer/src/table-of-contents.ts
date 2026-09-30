// Adapted from FluxMarkdown, copyright (c) 2024-2026 xykong. GPL-3.0.
// Upstream: 733a664c57cbc5f23045e5f87d3ec7f3db17f947. See LICENSE and UPSTREAM.md.
import type { HeadingNode } from './outline';

function compressMultipleHyphens(text: string): string {
    return text.replace(/-+/g, '-');
}

function unifyUnderscoreAndHyphen(text: string): string {
    return text.replace(/[_-]/g, '~');
}

function findElementByAnchor(anchorId: string): HTMLElement | null {
    const allElementsWithId = document.querySelectorAll('#markdown-preview [id]');
    
    const exactMatch = Array.from(allElementsWithId).find(element => element.id === anchorId) as HTMLElement | undefined;
    if (exactMatch) return exactMatch;
    
    const level2NormalizedTarget = compressMultipleHyphens(anchorId);
    for (const element of allElementsWithId) {
        const elementId = element.getAttribute('id');
        if (elementId && compressMultipleHyphens(elementId) === level2NormalizedTarget) {
            return element as HTMLElement;
        }
    }
    
    const level3NormalizedTarget = unifyUnderscoreAndHyphen(compressMultipleHyphens(anchorId));
    for (const element of allElementsWithId) {
        const elementId = element.getAttribute('id');
        if (elementId && unifyUnderscoreAndHyphen(compressMultipleHyphens(elementId)) === level3NormalizedTarget) {
            return element as HTMLElement;
        }
    }
    
    return null;
}

export class TableOfContents {
    private container: HTMLElement;
    private isVisible: boolean = false;
    private activeId: string | null = null;
    private observer: IntersectionObserver | null = null;

    constructor(containerId: string) {
        const element = document.getElementById(containerId);
        if (!element) {
            throw new Error(`TOC container element not found: ${containerId}`);
        }
        this.container = element;
        this.setupToggleButton();
        this.setupIntersectionObserver();
    }

    private setupToggleButton(): void {
        const button = document.createElement('button');
        button.className = 'toc-toggle';
        button.setAttribute('aria-label', 'Toggle Table of Contents');
        button.innerHTML = `
            <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
                <path d="M2 4h16v2H2V4zm0 5h16v2H2V9zm0 5h16v2H2v-2z"/>
            </svg>
        `;
        button.addEventListener('click', () => this.toggle());
        this.container.appendChild(button);
    }

    private setupIntersectionObserver(): void {
        const observerOptions = {
            rootMargin: '-80px 0px -80% 0px',
            threshold: 0
        };

        this.observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    this.setActiveItem(entry.target.id);
                }
            });
        }, observerOptions);

    }

    public observeHeadings(): void {
        this.observer?.disconnect();
        this.activeId = null;
        document.querySelectorAll('#markdown-preview h1[id], #markdown-preview h2[id], #markdown-preview h3[id], #markdown-preview h4[id], #markdown-preview h5[id], #markdown-preview h6[id]')
            .forEach(heading => this.observer?.observe(heading));
    }

    private setActiveItem(id: string): void {
        if (this.activeId === id) return;
        
        this.activeId = id;
        const links = this.container.querySelectorAll('.toc-link');
        links.forEach(link => {
            if (link.getAttribute('href') === `#${id}`) {
                link.classList.add('active');
            } else {
                link.classList.remove('active');
            }
        });
    }

    public render(headings: HeadingNode[]): void {
        if (headings.length === 0) {
            this.container.style.display = 'none';
            return;
        }

        this.container.style.display = 'block';

        const nav = document.createElement('nav');
        nav.className = this.isVisible ? 'toc-nav visible' : 'toc-nav';
        nav.setAttribute('aria-label', 'Table of Contents');

        const title = document.createElement('div');
        title.className = 'toc-title';
        title.textContent = 'Contents';
        nav.appendChild(title);

        const list = this.renderList(headings);
        nav.appendChild(list);

        const existingNav = this.container.querySelector('.toc-nav');
        if (existingNav) {
            this.container.replaceChild(nav, existingNav);
        } else {
            this.container.appendChild(nav);
        }

        this.attachClickHandlers();
    }

    private renderList(headings: HeadingNode[]): HTMLElement {
        const ul = document.createElement('ul');
        ul.className = 'toc-list';

        headings.forEach(heading => {
            const li = document.createElement('li');
            li.className = 'toc-item';

            const link = document.createElement('a');
            link.className = 'toc-link';
            link.href = `#${heading.id}`;
            link.textContent = heading.text;
            link.dataset.level = heading.level.toString();
            li.appendChild(link);

            if (heading.children.length > 0) {
                const childList = this.renderList(heading.children);
                li.appendChild(childList);
            }

            ul.appendChild(li);
        });

        return ul;
    }

    private attachClickHandlers(): void {
        const links = this.container.querySelectorAll('.toc-link');
        links.forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const href = (e.target as HTMLAnchorElement).getAttribute('href');
                if (href) {
                    const targetId = href.substring(1);
                    const targetElement = findElementByAnchor(targetId);
                    if (targetElement) {
                        targetElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
                        const actualId = targetElement.getAttribute('id');
                        if (actualId) {
                            this.setActiveItem(actualId);
                        }
                    }
                }
            });
        });
    }

    public toggle(): void {
        this.isVisible = !this.isVisible;
        const nav = this.container.querySelector('.toc-nav');
        if (nav) {
            nav.classList.toggle('visible', this.isVisible);
        }
    }

    public show(): void {
        this.isVisible = true;
        const nav = this.container.querySelector('.toc-nav');
        if (nav) {
            nav.classList.add('visible');
        }
    }

    public hide(): void {
        this.isVisible = false;
        const nav = this.container.querySelector('.toc-nav');
        if (nav) {
            nav.classList.remove('visible');
        }
    }
}
