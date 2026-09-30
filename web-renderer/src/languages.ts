// SPDX-License-Identifier: MIT
// Application language inventory; grammar implementations come from highlight.js.
import highlighter from 'highlight.js/lib/core';
import grammar0 from 'highlight.js/lib/languages/javascript';
import grammar1 from 'highlight.js/lib/languages/typescript';
import grammar2 from 'highlight.js/lib/languages/python';
import grammar3 from 'highlight.js/lib/languages/bash';
import grammar4 from 'highlight.js/lib/languages/shell';
import grammar5 from 'highlight.js/lib/languages/sql';
import grammar6 from 'highlight.js/lib/languages/json';
import grammar7 from 'highlight.js/lib/languages/yaml';
import grammar8 from 'highlight.js/lib/languages/markdown';
import grammar9 from 'highlight.js/lib/languages/css';
import grammar10 from 'highlight.js/lib/languages/xml';
import grammar11 from 'highlight.js/lib/languages/go';
import grammar12 from 'highlight.js/lib/languages/rust';
import grammar13 from 'highlight.js/lib/languages/java';
import grammar14 from 'highlight.js/lib/languages/c';
import grammar15 from 'highlight.js/lib/languages/cpp';
import grammar16 from 'highlight.js/lib/languages/swift';
import grammar17 from 'highlight.js/lib/languages/kotlin';
import grammar18 from 'highlight.js/lib/languages/ruby';
import grammar19 from 'highlight.js/lib/languages/php';
import grammar20 from 'highlight.js/lib/languages/csharp';
import grammar21 from 'highlight.js/lib/languages/diff';
import grammar22 from 'highlight.js/lib/languages/dockerfile';
import grammar23 from 'highlight.js/lib/languages/nginx';
import grammar24 from 'highlight.js/lib/languages/scala';
import grammar25 from 'highlight.js/lib/languages/perl';
import grammar26 from 'highlight.js/lib/languages/r';
import grammar27 from 'highlight.js/lib/languages/dart';
import grammar28 from 'highlight.js/lib/languages/lua';
import grammar29 from 'highlight.js/lib/languages/haskell';
import grammar30 from 'highlight.js/lib/languages/elixir';
import grammar31 from 'highlight.js/lib/languages/groovy';
import grammar32 from 'highlight.js/lib/languages/verilog';
import grammar33 from 'highlight.js/lib/languages/vhdl';
import grammar34 from 'highlight.js/lib/languages/makefile';
import grammar35 from 'highlight.js/lib/languages/ini';
import grammar36 from 'highlight.js/lib/languages/protobuf';
import grammar37 from 'highlight.js/lib/languages/graphql';
import grammar38 from 'highlight.js/lib/languages/plaintext';
import grammar39 from 'highlight.js/lib/languages/powershell';
import grammar40 from 'highlight.js/lib/languages/objectivec';

const grammars = {
    javascript: grammar0,
    typescript: grammar1,
    python: grammar2,
    bash: grammar3,
    shell: grammar4,
    sql: grammar5,
    json: grammar6,
    yaml: grammar7,
    markdown: grammar8,
    css: grammar9,
    xml: grammar10,
    go: grammar11,
    rust: grammar12,
    java: grammar13,
    c: grammar14,
    cpp: grammar15,
    swift: grammar16,
    kotlin: grammar17,
    ruby: grammar18,
    php: grammar19,
    csharp: grammar20,
    diff: grammar21,
    dockerfile: grammar22,
    nginx: grammar23,
    scala: grammar24,
    perl: grammar25,
    r: grammar26,
    dart: grammar27,
    lua: grammar28,
    haskell: grammar29,
    elixir: grammar30,
    groovy: grammar31,
    verilog: grammar32,
    vhdl: grammar33,
    makefile: grammar34,
    ini: grammar35,
    protobuf: grammar36,
    graphql: grammar37,
    plaintext: grammar38,
    powershell: grammar39,
    objectivec: grammar40,
};
for (const [name, grammar] of Object.entries(grammars)) highlighter.registerLanguage(name, grammar);
// Additional editor file extensions not registered by the grammars themselves.
for (const [alias, language] of Object.entries({ps1: 'powershell', gql: 'graphql', mk: 'makefile', text: 'plaintext'})) {
    highlighter.registerAliases(alias, {languageName: language});
}
export default highlighter;
