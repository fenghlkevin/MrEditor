// Minimal stable C API from github/cmark-gfm (system macOS library).
#include <stdlib.h>
typedef struct cmark_parser cmark_parser;
typedef struct cmark_node cmark_node;
typedef struct cmark_syntax_extension cmark_syntax_extension;
typedef struct _cmark_llist cmark_llist;
void cmark_gfm_core_extensions_ensure_registered(void);
cmark_syntax_extension *cmark_find_syntax_extension(const char *name);
cmark_parser *cmark_parser_new(int options);
int cmark_parser_attach_syntax_extension(cmark_parser *, cmark_syntax_extension *);
void cmark_parser_feed(cmark_parser *, const char *, size_t);
cmark_node *cmark_parser_finish(cmark_parser *);
cmark_llist *cmark_parser_get_syntax_extensions(cmark_parser *);
char *cmark_render_html(cmark_node *, int, cmark_llist *);
void cmark_node_free(cmark_node *);
void cmark_parser_free(cmark_parser *);
