declare module '@iktakahiro/markdown-it-katex' {
    import MarkdownIt from 'markdown-it';
    const plugin: (md: MarkdownIt, options?: Record<string, unknown>) => void;
    export default plugin;
}

interface Window {
    webkit?: { messageHandlers?: { markdownRenderer?: { postMessage(message: string): void } } };
    mrPreview: {
        render(source: string, options: { dark: boolean; revision: number; language: string; format?: string; syntax?: string }): Promise<boolean>;
        cancel(): void;
    };
}

declare module 'markdown-it-emoji';
declare module 'markdown-it-footnote';
declare module 'markdown-it-task-lists';
declare module 'markdown-it-mark';
declare module 'markdown-it-sub';
declare module 'markdown-it-sup';
