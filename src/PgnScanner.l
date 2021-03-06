%{
//
// ChessCore (c)2008-2013 Andy Duplain <andy@trojanfoe.com>
//
// PgnScanner.l: Lexical scanner for parsing PGN games.
//

#include <ChessCore/PgnScanner.h>
#include <ChessCore/Log.h>

using namespace std;
using namespace ChessCore;

static const char *m_classname = "PgnScanner.l";

// Additional scanner debugging
#define SCANNER_DEBUG 0

// Stop 'no previous prototype' compiler warnings
int pgnget_column(yyscan_t yyscanner);
void pgnset_column(int column_no, yyscan_t yyscanner);

// Local functions
static unsigned countNewlines(yyscan_t yyscanner);
static unsigned eatLine(yyscan_t yyscanner);
static void flushBuffer(yyscan_t yyscanner);

#define YY_INPUT(buf, result, max_size) { \
    result = yyextra->read(buf, 1); \
}

%}

%option 8bit reentrant noyywrap never-interactive
%option fast
%option prefix="pgn"
%option extra-type="PgnScannerContext *"

spc     ([ \t]+)
piece   [KQBNRP]
prom    "="?[QBNR]
file    [a-h]
rank    [1-8]
value   [0-9]+
x       [xX]

%%

"[Event "[^\n\r]*"]"                    return A_PGN_EVENT;
"[Site "[^\n\r]*"]"                     return A_PGN_SITE;
"[Date "[^\n\r]*"]"                     return A_PGN_DATE;
"[Round "[^\n\r]*"]"                    return A_PGN_ROUND;
"[White "[^\n\r]*"]"                    return A_PGN_WHITE;
"[Black "[^\n\r]*"]"                    return A_PGN_BLACK;
"[Result "[^\n\r]*"]"                   return A_PGN_RESULT;
"[SetUp "[^\n\r]*"]"                    return A_PGN_SETUP;
"[FEN "[^\n\r]*"]"                      return A_PGN_FEN;
"[Annotator "[^\n\r]*"]"                return A_PGN_ANNOTATOR;
"[ECO "[^\n\r]*"]"                      return A_PGN_ECO;
"[WhiteElo "[^\n\r]*"]"                 return A_PGN_WHITEELO;
"[BlackElo "[^\n\r]*"]"                 return A_PGN_BLACKELO;
"[Opening "[^\n\r]*"]"                  return A_PGN_OPENING;
"[Variation "[^\n\r]*"]"                return A_PGN_VARIATION;
"[TimeControl "[^\n\r]*"]"              return A_PGN_TIMECONTROL;
"["[^\n\r]*"]"                          return A_PGN_XXX;

{value}"."?                             return A_WHITE_MOVENUM;
{value}"..."                            return A_BLACK_MOVENUM;

{file}{rank}{prom}?                     return A_PAWN_MOVE;
{file}{x}?{file}{rank}{prom}?           return A_PAWN_CAPTURE;
{file}{x}?{file}{prom}?                 return A_PAWN_CAPTURE;
{piece}{file}{rank}                     return A_PIECE_MOVE;
{piece}{file}{file}{rank}               return A_PIECE_MOVE;
{piece}{rank}{file}{rank}               return A_PIECE_MOVE;
{piece}{file}{rank}"-"?{file}{rank}     return A_PIECE_MOVE;
{file}{rank}"-"?{file}{rank}            return A_PIECE_MOVE;
{piece}{x}{file}{rank}                  return A_PIECE_CAPTURE;
{piece}{file}{x}{file}{rank}            return A_PIECE_CAPTURE;
{piece}{rank}{x}{file}{rank}            return A_PIECE_CAPTURE;
{piece}{file}{rank}{x}{file}{rank}      return A_PIECE_CAPTURE;
("O-O"|"o-o"|"0-0")                     return A_SHORT_CASTLE;
("O-O-O"|"o-o-o"|"0-0-0")               return A_LONG_CASTLE;
"+"                                     return A_CHECK;
"#"                                     return A_MATE;
"!"                                     return A_GOOD_MOVE;
"?"                                     return A_BAD_MOVE;
"!?"                                    return A_INTERESTING_MOVE;
"?!"                                    return A_DUBIOUS_MOVE;
"!!"                                    return A_BRILLIANT_MOVE;
"??"                                    return A_BLUNDER_MOVE;
"$"[0-9]+                               return A_NAG;
"$#"                                    return A_NAG_MATE;
"$N"                                    return A_NAG_NOVELTY;
("1-0"|"1:0")                           return A_WHITE_WINS;
("0-1"|"0:1")                           return A_BLACK_WINS;
("1/2-1/2"|"1/2:1/2"|"1/2"|"draw")      return A_DRAW;
"*"                                     return A_UNFINISHED;

"{"[^}]*"}"                             {
    yyextra->incLineNumber(countNewlines(yyscanner));
    return A_COMMENT;
}

"("                                     return A_VARSTART;
")"                                     return A_VAREND;
";".*$                                  return A_ROL_COMMENT;
^"%"                                    yyextra->incLineNumber(eatLine(yyscanner));
(\n\r|\r\n|\n|\r)                       yyextra->incLineNumber(1);
[ \t]+                                  ;
"..."                                   ;
"<"                                     ;
">"                                     ;
.                                       return *pgnget_text(yyscanner);

%%

//
// PgnScannerContext implementation
//

const char *PgnScannerContext::m_classname = "PgnScannerContext";

PgnScannerContext::PgnScannerContext(istream &stream) :
    m_scanner(0),
    m_stream(stream),
    m_lineNumber(1) {

    initScanner();
}

PgnScannerContext::~PgnScannerContext() {
    destroyScanner();
}

void *PgnScannerContext::scanner() {
    return m_scanner;
}

int PgnScannerContext::read(void *buffer, unsigned len) {
    int read = 0;
    for (unsigned i = 0; i < len; i++) {
        m_stream.get(((char *)buffer)[i]);
        if (m_stream.good())
            read++;
        else
            break;
    }
    return read;
}

int PgnScannerContext::lex() {
    return pgnlex(m_scanner);
}

void PgnScannerContext::restart() {
    pgnrestart(0, m_scanner);
}

void PgnScannerContext::flush() {
    flushBuffer(m_scanner);
}

char *PgnScannerContext::text() const {
    return pgnget_text(m_scanner);
}

unsigned PgnScannerContext::lineNumber() const {
    return m_lineNumber;
}

void PgnScannerContext::setLineNumber(unsigned lineNumber) {
    m_lineNumber = lineNumber;
}

void PgnScannerContext::incLineNumber(unsigned amount /*=1*/) {
    m_lineNumber += amount;
}

void PgnScannerContext::initScanner() {
    ASSERT(m_scanner == 0);
    int status = pgnlex_init_extra(this, &m_scanner);
    if (status) {
        LOGERR << "Failed to initialise PGN scanner: " << status;
    }
}

void PgnScannerContext::destroyScanner() {
    if (m_scanner) {
        pgnlex_destroy(m_scanner);
        m_scanner = 0;
    }
}

//
// Count the number of newlines within a comment
//
static unsigned countNewlines(yyscan_t yyscanner) {
    unsigned count = 0;
    char *s = pgnget_text(yyscanner);
    while(*s != '\0') {
        if ((*s == '\n' && *(s+1) == '\r') ||
            (*s == '\r' && *(s+1) == '\n')) {
            count++;
            *s++ = ' ';
            *s = ' ';
        }
        else if (*s == '\n') {
            count++;
            *s = ' ';
        }
        else if (*s == '{' || *s == '}') {
            *s = ' ';
        }
        s++;
    }
    return count;
}

//
// Eat the rest of the line and return the number of newlines seen (0 or 1).
//
static unsigned eatLine(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t *)yyscanner;    // To make unput() work
    unsigned count = 0;
    int c;
    while ((c = yyinput(yyscanner)) > 0) {
        if (c == '\n' || c == '\r') {
            c = yyinput(yyscanner);
            if (c != '\n' && c != '\r')
            unput(c);
            count = 1;
            break;
        }
    }
    return count;
}

//
// Flush the buffer, so any buffered input are discarded
//
static void flushBuffer(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t *)yyscanner;    // To make YY_FLUSH_BUFFER work
    YY_FLUSH_BUFFER;
}
