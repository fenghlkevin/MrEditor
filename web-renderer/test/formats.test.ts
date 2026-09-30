// @vitest-environment jsdom
import {describe,it,expect} from 'vitest';
import {parseDelimited, structured, tableView, safeMarkup, codeView} from '../src/formats';
import {installSearch} from '../src/search';
import '../src/markdown';

describe('document formats',()=>{
 it('parses quoted delimiters, newlines, escapes and CRLF',()=>{expect(parseDelimited('a,b\r\n"hello, world","a\n""b"""\r\n',',').rows).toEqual([['a','b'],['hello, world','a\n"b"']]);});
 it('bounds rows and rejects unfinished quotes',()=>{expect(parseDelimited('h\n1\n2\n3',',',2).truncated).toBe(true);expect(()=>parseDelimited('a,"b',',')).toThrow();});
 it('supports TSV empty cells',()=>{expect(parseDelimited('a\tb\n\t2\n','\t').rows).toEqual([['a','b'],['','2']]);});
 it('shows nested JSON without executing markup and reports errors',()=>{const r=structured('{"a":{"b":"<img src=x onerror=alert(1)>"}}',false);expect(r.querySelectorAll('details').length).toBe(2);expect(r.querySelector('img')).toBeNull();expect(structured('{"a":}',false).textContent).toContain('Parse error');});
 it('bounds YAML aliases and reports line and column',()=>{expect(structured('a: &a [*a]',true).textContent).toContain('YAML alias');expect(structured('a: [',true).textContent).toContain('Line');});
 it('sorts and filters tabular data',()=>{const r=tableView('name,value\nb,10\na,2',',');(r.querySelector('th button') as HTMLButtonElement).click();expect(r.querySelector('tbody tr')?.textContent).toBe('a2');const i=r.querySelector('input')!;i.value='b';i.dispatchEvent(new Event('input'));expect(r.querySelectorAll('tbody tr')).toHaveLength(1);expect(r.querySelector('tbody')?.textContent).toBe('b10');});
 it('strips executable and remote HTML/SVG content',()=>{for(const svg of [false,true]) {const r=safeMarkup('<script>alert(1)</script><iframe src="https://x"></iframe><svg onload="x()"><foreignObject>bad</foreignObject><image href="https://x"/><rect fill="url(https://x)"/></svg><img src="https://x" onerror="x()">',svg);expect(r.innerHTML).not.toMatch(/script|iframe|onload|onerror|foreignObject|https:/);}});
 it('renders code and log levels with no executable markup',()=>{expect(codeView('let x = 1','swift').querySelector('.hljs-keyword')).not.toBeNull();const r=codeView('ERROR <script>x</script>\nWARN wait','log');expect(r.querySelector('.log-error')).not.toBeNull();expect(r.querySelector('script')).toBeNull();});
 it('finds literal text, cycles results and clears highlighting',()=>{const output=document.createElement('main');output.textContent='alpha alpha <tag>';document.body.append(output);const s=installSearch(output);const f=s.bar.querySelector('input')!;f.value='alpha';s.refresh();expect(output.querySelectorAll('mark')).toHaveLength(2);s.clear();expect(output.textContent).toBe('alpha alpha <tag>');expect(output.querySelector('mark')).toBeNull();});
});
