package barrage.script;

import hscript.Interp;

private enum NativeToken {
	TNumber(v:Float);
	TIdentifier(name:String);
	TRand;
	TAdd;
	TSub;
	TMul;
	TDiv;
	TNeg;
}

class NativeExpr {
	public var rpn:Array<NativeToken>;
	final stack:Array<Float>;

	public function new(rpn:Array<NativeToken>) {
		this.rpn = rpn;
		this.stack = [];
	}

	public function eval(interp:Interp):Float {
		var top = 0;
		for (t in rpn) {
			switch (t) {
				case TNumber(v):
					stack[top++] = v;
				case TIdentifier(name):
					final v:Dynamic = interp.variables.get(name);
					if (v == null)
						throw "Unknown variable: " + name;
					stack[top++] = toFloat(v);
				case TRand:
					final fn:Dynamic = interp.variables.get("rand");
					if (fn == null)
						throw "rand() is not defined";
					stack[top++] = fn();
				case TAdd:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a + b;
				case TSub:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a - b;
				case TMul:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a * b;
				case TDiv:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a / b;
				case TNeg:
					stack[top - 1] = -stack[top - 1];
			}
		}
		if (top != 1)
			throw "Invalid native expression stack state";
		return stack[0];
	}

	public function isConstant():Bool {
		for (t in rpn) {
			switch (t) {
				case TIdentifier(_) | TRand:
					return false;
				default:
			}
		}
		return true;
	}

	public function evalConstant():Float {
		if (!isConstant())
			throw "NativeExpr is not constant";
		final stack = new Array<Float>();
		for (t in rpn) {
			switch (t) {
				case TNumber(v):
					stack.push(v);
				case TAdd:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(a + b);
				case TSub:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(a - b);
				case TMul:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(a * b);
				case TDiv:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(a / b);
				case TNeg:
					stack.push(-stack.pop());
				case TIdentifier(_) | TRand:
					throw "NativeExpr is not constant";
			}
		}
		if (stack.length != 1)
			throw "Invalid native constant expression stack state";
		return stack[0];
	}

	public static function compile(raw:String):Null<NativeExpr> {
		try {
			final src = stripOuterParens(raw);
			final parser = new NativeExprParser(src);
			final rpn = parser.compile();
			return new NativeExpr(rpn);
		} catch (_:Dynamic) {
			return null;
		}
	}

	static inline function toFloat(v:Dynamic):Float {
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Bool)) return cast(v, Bool) ? 1.0 : 0.0;
		return Std.parseFloat(Std.string(v));
	}

	static function stripOuterParens(raw:String):String {
		var s = StringTools.trim(raw);
		while (s.length >= 2 && s.charAt(0) == "(" && s.charAt(s.length - 1) == ")") {
			var level = 0;
			var wraps = true;
			for (i in 0...s.length - 1) {
				final ch = s.charAt(i);
				if (ch == "(") level++;
				else if (ch == ")") level--;
				if (level == 0 && i < s.length - 2) {
					wraps = false;
					break;
				}
			}
			if (!wraps) break;
			s = StringTools.trim(s.substr(1, s.length - 2));
		}
		return s;
	}
}

private class NativeExprParser {
	final source:String;
	var index:Int = 0;
	final out:Array<NativeToken> = [];
	final ops:Array<String> = [];
	var expectUnary = true;

	public function new(source:String) {
		this.source = source;
	}

	public function compile():Array<NativeToken> {
		while (index < source.length) {
			final ch = source.charAt(index);
			if (isSpace(ch)) {
				index++;
				continue;
			}
			if (isDigit(ch) || ch == ".") {
				out.push(TNumber(parseNumber()));
				expectUnary = false;
				continue;
			}
			if (isIdentStart(ch)) {
				final ident = parseIdentifier();
				if (ident == "rand" && peekNonSpace() == "(") {
					index = skipNonSpace(index);
					if (source.charAt(index) != "(") throw "Invalid rand call";
					index++;
					index = skipSpaces(index);
					if (index >= source.length || source.charAt(index) != ")") throw "rand() takes no args";
					index++;
					out.push(TRand);
				} else {
					out.push(TIdentifier(ident));
				}
				expectUnary = false;
				continue;
			}
			if (ch == "(") {
				ops.push(ch);
				index++;
				expectUnary = true;
				continue;
			}
			if (ch == ")") {
				while (ops.length > 0 && ops[ops.length - 1] != "(") {
					popOp();
				}
				if (ops.length == 0) throw "Unbalanced parentheses";
				ops.pop();
				index++;
				expectUnary = false;
				continue;
			}
			if (isOperator(ch)) {
				final op = expectUnary && ch == "-" ? "u-" : ch;
				while (ops.length > 0 && shouldPopBeforePush(op, ops[ops.length - 1])) {
					popOp();
				}
				ops.push(op);
				index++;
				expectUnary = true;
				continue;
			}
			throw "Unsupported token";
		}

		while (ops.length > 0) {
			if (ops[ops.length - 1] == "(") throw "Unbalanced parentheses";
			popOp();
		}
		return out;
	}

	function popOp():Void {
		final op = ops.pop();
		switch (op) {
			case "+":
				out.push(TAdd);
			case "-":
				out.push(TSub);
			case "*":
				out.push(TMul);
			case "/":
				out.push(TDiv);
			case "u-":
				out.push(TNeg);
			default:
				throw "Unknown operator";
		}
	}

	function shouldPopBeforePush(incoming:String, top:String):Bool {
		if (top == "(") return false;
		final pTop = precedence(top);
		final pIn = precedence(incoming);
		return pTop > pIn || (pTop == pIn && incoming != "u-");
	}

	function precedence(op:String):Int {
		return switch (op) {
			case "u-": 3;
			case "*", "/": 2;
			case "+", "-": 1;
			default: 0;
		}
	}

	function parseNumber():Float {
		final start = index;
		while (index < source.length) {
			final ch = source.charAt(index);
			if (!isDigit(ch) && ch != ".") break;
			index++;
		}
		return Std.parseFloat(source.substring(start, index));
	}

	function parseIdentifier():String {
		final start = index;
		index++;
		while (index < source.length) {
			final ch = source.charAt(index);
			if (!isIdentPart(ch)) break;
			index++;
		}
		return source.substring(start, index);
	}

	function peekNonSpace():String {
		final i = skipNonSpace(index);
		return i < source.length ? source.charAt(i) : "";
	}

	function skipNonSpace(i:Int):Int {
		var idx = i;
		while (idx < source.length && isSpace(source.charAt(idx))) idx++;
		return idx;
	}

	function skipSpaces(i:Int):Int {
		return skipNonSpace(i);
	}

	inline function isSpace(ch:String):Bool {
		return ch == " " || ch == "\t" || ch == "\r" || ch == "\n";
	}

	inline function isDigit(ch:String):Bool {
		return ch >= "0" && ch <= "9";
	}

	inline function isIdentStart(ch:String):Bool {
		return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_";
	}

	inline function isIdentPart(ch:String):Bool {
		return isIdentStart(ch) || isDigit(ch);
	}

	inline function isOperator(ch:String):Bool {
		return ch == "+" || ch == "-" || ch == "*" || ch == "/";
	}
}
