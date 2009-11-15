

my $grammar <<'END_OF_GRAMMAR';
prog  progstart lineseq
block  LBRACE remember lineseq RBRACE
remember
mydefsv
progstart
mblock  LBRACE mremember lineseq RBRACE
mremember
lineseq
lineseq lineseq decl
lineseq lineseq line
line  label cond
line loop
line switch
line label case
line label SEMICOLON
line label sideff SEMICOLON
sideff error
sideff expr
sideff expr IF expr
sideff expr UNLESS expr
sideff expr WHILE expr
sideff expr UNTIL iexpr
sideff expr FOR expr
else
else ELSE mblock
else ELSIF LPAREN mexpr RPAREN mblock else
cond IF LPAREN remember mexpr RPAREN mblock else
cond UNLESS LPAREN remember miexpr RPAREN mblock else
case WHEN LPAREN remember mexpr RPAREN mblock
case DEFAULT block
cont
cont CONTINUE block
loop label WHILE LPAREN remember texpr RPAREN mintro mblock cont
loop label UNTIL LPAREN remember iexpr RPAREN mintro mblock cont
loop label FOR MY remember my_scalar LPAREN mexpr RPAREN mblock cont
loop label FOR scalar LPAREN remember mexpr RPAREN mblock cont
loop label FOR LPAREN remember mexpr RPAREN mblock cont
loop label FOR LPAREN remember mnexpr SEMICOLON texpr SEMICOLON mintro mnexpr RPAREN mblock
loop label block cont
switch label GIVEN LPAREN remember mydefsv mexpr RPAREN mblock
mintro
nexpr
nexpr sideff
texpr
texpr expr
iexpr expr
mexpr expr
mnexpr nexpr
miexpr iexpr
label
label LABEL
decl format
decl subrout
decl mysubrout
decl package
decl use
decl peg
peg PEG
format FORMAT startformsub formname block
formname WORD
formname
mysubrout MYSUB startsub subname proto subattrlist subbody
subrout SUB startsub subname proto subattrlist subbody
startsub
startanonsub
startformsub
subname WORD
proto
proto THING
subattrlist:
subattrlist COLONATTR THING
subattrlist COLONATTR
myattrlist: COLONATTR THING
myattrlist COLONATTR
subbody block
subbody SEMICOLON
package PACKAGE WORD SEMICOLON
use USE startsub WORD WORD listexpr SEMICOLON
expr expr ANDOP expr
expr expr OROP expr
expr expr DOROP expr
expr argexpr
argexpr argexpr COMMA
argexpr argexpr COMMA term
argexpr term
listop LSTOP indirob argexpr
listop FUNC LPAREN indirob expr RPAREN
listop term ARROW method LPAREN listexprcom RPAREN
listop term ARROW method
listop METHOD indirob listexpr
listop FUNCMETH indirob LPAREN listexprcom RPAREN
listop LSTOP listexpr
listop FUNC LPAREN listexprcom RPAREN
listop LSTOPSUB startanonsub block listexpr
method METHOD
method scalar
subscripted    star LBRACE expr SEMICOLON RBRACE
subscripted scalar LSQUARE expr RQUARE
subscripted term ARROW LSQUARE expr RQUARE
subscripted subscripted LSQUARE expr RQUARE
subscripted scalar LBRACE expr SEMICOLON RBRACE
subscripted term ARROW LBRACE expr SEMICOLON RBRACE
subscripted subscripted LBRACE expr SEMICOLON RBRACE
subscripted term ARROW LPAREN RPAREN
subscripted term ARROW LPAREN expr RPAREN
subscripted subscripted LPAREN expr RPAREN
subscripted subscripted LPAREN RPAREN
subscripted LPAREN expr RPAREN LSQUARE expr RQUARE
subscripted LPAREN RPAREN LSQUARE expr RQUARE
termbinop term ASSIGNOP term
termbinop term POWOP term
termbinop term MULOP term
termbinop term ADDOP term
termbinop term SHIFTOP term
termbinop term RELOP term
termbinop term EQOP term
termbinop term BITANDOP term
termbinop term BITOROP term
termbinop term DOTDOT term
termbinop term ANDAND term
termbinop term OROR term
termbinop term DORDOR term
termbinop term MATCHOP term
termunop MINUS_SIGN term
termunop PLUS_SIGN term
termunop BANG term
termunop TILDE term
termunop term POSTINC
termunop term POSTDEC
termunop PREINC term
termunop PREDEC term
anonymous LSQUARE expr RQUARE
anonymous LSQUARE RQUARE
anonymous HASHBRACK expr SEMICOLON RBRACE
anonymous HASHBRACK SEMICOLON RBRACE
anonymous ANONSUB startanonsub proto subattrlist block
termdo DO term
termdo DO block
termdo DO WORD LPAREN RPAREN
termdo DO WORD LPAREN expr RPAREN
termdo DO scalar LPAREN RPAREN
termdo DO scalar LPAREN expr RPAREN
term termbinop
term termunop
term anonymous
term termdo
term term QUESTIONMARK term COLON term
term REFGEN term
term myattrterm
term LOCAL term
term LPAREN expr RPAREN
term LPAREN RPAREN
term scalar
term star
term hsh
term ary
term arylen
term       subscripted
term ary LSQUARE expr RQUARE
term ary LBRACE expr SEMICOLON RBRACE
term THING
term amper
term amper LPAREN RPAREN
term amper LPAREN expr RPAREN
term NOAMP WORD listexpr
term LOOPEX
term LOOPEX term
term NOTOP argexpr
term UNIOP
term UNIOP block
term UNIOP term
term REQUIRE
term REQUIRE term
term UNIOPSUB
term UNIOPSUB term
term FUNC0
term FUNC0 LPAREN RPAREN
term FUNC0SUB
term FUNC1 LPAREN RPAREN
term FUNC1 LPAREN expr RPAREN
term PMFUNC LPAREN argexpr RPAREN
term WORD
term listop
myattrterm MY myterm myattrlist
myattrterm MY myterm
myterm LPAREN expr RPAREN
myterm LPAREN RPAREN
myterm scalar
myterm hsh
myterm ary
listexpr
listexpr argexpr
listexprcom
listexprcom expr
listexprcom expr COMMA
my_scalar scalar
amper AMPERSAND indirob
scalar DOLLAR_SIGN indirob
ary AT_SIGN indirob
hsh PERCENT_SIGN indirob
arylen DOLSHARP indirob
star STAR indirob
indirob WORD
indirob scalar
indirob block
indirob PRIVATEREF
END_OF_GRAMMAR