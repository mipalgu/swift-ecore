grammar Arith

entry Expr: Num | Var | BinOp | Let;
Num: value=INT;
Var: name=ID;
BinOp: '(' left=Expr operator=('+' | '-' | '*' | '/') right=Expr ')';
Let: 'let' name=ID '=' init=Expr 'in' body=Expr;

hidden terminal WS: /\s+/;
terminal ID: /[_a-zA-Z][\w_]*/;
terminal INT returns number: /[0-9]+/;
