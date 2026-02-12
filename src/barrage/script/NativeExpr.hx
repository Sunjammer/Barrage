package barrage.script;

private enum NativeToken {
	TNumber(v:Float);
	TIdentifier(name:String);
	TRand;
	TSin;
	TCos;
	TTan;
	TAbs;
	TSqrt;
	TFloor;
	TCeil;
	TRound;
	TExp;
	TLog;
	TAsin;
	TAcos;
	TAtan;
	TPow;
	TMin;
	TMax;
	TAtan2;
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

	public function eval(ctx:ScriptContext):Float {
		var top = 0;
		for (t in rpn) {
			switch (t) {
				case TNumber(v):
					stack[top++] = v;
				case TIdentifier(name):
					final v = ctx.getVar(name);
					if (v == null)
						throw "Unknown variable: " + name;
					stack[top++] = v;
				case TRand:
					stack[top++] = ctx.rand();
				case TSin:
					stack[top - 1] = Math.sin(stack[top - 1]);
				case TCos:
					stack[top - 1] = Math.cos(stack[top - 1]);
				case TTan:
					stack[top - 1] = Math.tan(stack[top - 1]);
				case TAbs:
					stack[top - 1] = Math.abs(stack[top - 1]);
				case TSqrt:
					stack[top - 1] = Math.sqrt(stack[top - 1]);
				case TFloor:
					stack[top - 1] = Math.floor(stack[top - 1]);
				case TCeil:
					stack[top - 1] = Math.ceil(stack[top - 1]);
				case TRound:
					stack[top - 1] = Math.round(stack[top - 1]);
				case TExp:
					stack[top - 1] = Math.exp(stack[top - 1]);
				case TLog:
					stack[top - 1] = Math.log(stack[top - 1]);
				case TAsin:
					stack[top - 1] = Math.asin(stack[top - 1]);
				case TAcos:
					stack[top - 1] = Math.acos(stack[top - 1]);
				case TAtan:
					stack[top - 1] = Math.atan(stack[top - 1]);
				case TPow:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.pow(a, b);
				case TMin:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.min(a, b);
				case TMax:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.max(a, b);
				case TAtan2:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.atan2(a, b);
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
				case TSin:
					stack[stack.length - 1] = Math.sin(stack[stack.length - 1]);
				case TCos:
					stack[stack.length - 1] = Math.cos(stack[stack.length - 1]);
				case TTan:
					stack[stack.length - 1] = Math.tan(stack[stack.length - 1]);
				case TAbs:
					stack[stack.length - 1] = Math.abs(stack[stack.length - 1]);
				case TSqrt:
					stack[stack.length - 1] = Math.sqrt(stack[stack.length - 1]);
				case TFloor:
					stack[stack.length - 1] = Math.floor(stack[stack.length - 1]);
				case TCeil:
					stack[stack.length - 1] = Math.ceil(stack[stack.length - 1]);
				case TRound:
					stack[stack.length - 1] = Math.round(stack[stack.length - 1]);
				case TExp:
					stack[stack.length - 1] = Math.exp(stack[stack.length - 1]);
				case TLog:
					stack[stack.length - 1] = Math.log(stack[stack.length - 1]);
				case TAsin:
					stack[stack.length - 1] = Math.asin(stack[stack.length - 1]);
				case TAcos:
					stack[stack.length - 1] = Math.acos(stack[stack.length - 1]);
				case TAtan:
					stack[stack.length - 1] = Math.atan(stack[stack.length - 1]);
				case TPow:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(Math.pow(a, b));
				case TMin:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(Math.min(a, b));
				case TMax:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(Math.max(a, b));
				case TAtan2:
					final b = stack.pop();
					final a = stack.pop();
					stack.push(Math.atan2(a, b));
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

	public function new(source:String) {
		this.source = source;
	}

	public function compile():Array<NativeToken> {
		parseExpression();
		skipSpaces();
		if (index != source.length) {
			throw "Unsupported trailing token";
		}
		return out;
	}

	function parseExpression():Void {
		parseTerm();
		while (true) {
			skipSpaces();
			if (match("+")) {
				parseTerm();
				out.push(TAdd);
			} else if (match("-")) {
				parseTerm();
				out.push(TSub);
			} else {
				return;
			}
		}
	}

	function parseTerm():Void {
		parseUnary();
		while (true) {
			skipSpaces();
			if (match("*")) {
				parseUnary();
				out.push(TMul);
			} else if (match("/")) {
				parseUnary();
				out.push(TDiv);
			} else {
				return;
			}
		}
	}

	function parseUnary():Void {
		skipSpaces();
		if (match("-")) {
			parseUnary();
			out.push(TNeg);
		} else {
			parsePrimary();
		}
	}

	function parsePrimary():Void {
		skipSpaces();
		if (index >= source.length) {
			throw "Unexpected end of expression";
		}
		final ch = source.charAt(index);
		if (ch == "(") {
			index++;
			parseExpression();
			skipSpaces();
			expect(")");
			return;
		}
		if (isDigit(ch) || ch == ".") {
			out.push(TNumber(parseNumber()));
			return;
		}
		if (isIdentStart(ch)) {
			parseIdentifierOrCall();
			return;
		}
		throw "Unsupported token";
	}

	function parseIdentifierOrCall():Void {
		final name = parseIdentifier();
		skipSpaces();
		if (match("(")) {
			parseCall(name);
			return;
		}
		final constant = resolveConstant(name);
		if (constant != null) {
			out.push(TNumber(constant));
			return;
		}
		out.push(TIdentifier(name));
	}

	function parseCall(name:String):Void {
		final lowered = name.toLowerCase();
		if (match(")")) {
			if (lowered == "rand" || lowered == "math.random") {
				out.push(TRand);
				return;
			}
			throw "Unsupported zero-arg function";
		}
		var argc = 0;
		while (true) {
			parseExpression();
			argc++;
			skipSpaces();
			if (match(",")) {
				continue;
			}
			expect(")");
			break;
		}
		switch (lowered) {
			case "sin", "math.sin":
				ensureArity(argc, 1, name);
				out.push(TSin);
			case "cos", "math.cos":
				ensureArity(argc, 1, name);
				out.push(TCos);
			case "tan", "math.tan":
				ensureArity(argc, 1, name);
				out.push(TTan);
			case "abs", "math.abs":
				ensureArity(argc, 1, name);
				out.push(TAbs);
			case "sqrt", "math.sqrt":
				ensureArity(argc, 1, name);
				out.push(TSqrt);
			case "floor", "math.floor":
				ensureArity(argc, 1, name);
				out.push(TFloor);
			case "ceil", "math.ceil":
				ensureArity(argc, 1, name);
				out.push(TCeil);
			case "round", "math.round":
				ensureArity(argc, 1, name);
				out.push(TRound);
			case "exp", "math.exp":
				ensureArity(argc, 1, name);
				out.push(TExp);
			case "log", "math.log":
				ensureArity(argc, 1, name);
				out.push(TLog);
			case "asin", "math.asin":
				ensureArity(argc, 1, name);
				out.push(TAsin);
			case "acos", "math.acos":
				ensureArity(argc, 1, name);
				out.push(TAcos);
			case "atan", "math.atan":
				ensureArity(argc, 1, name);
				out.push(TAtan);
			case "pow", "math.pow":
				ensureArity(argc, 2, name);
				out.push(TPow);
			case "min", "math.min":
				ensureArity(argc, 2, name);
				out.push(TMin);
			case "max", "math.max":
				ensureArity(argc, 2, name);
				out.push(TMax);
			case "atan2", "math.atan2":
				ensureArity(argc, 2, name);
				out.push(TAtan2);
			default:
				throw "Unsupported function call";
		}
	}

	inline function ensureArity(actual:Int, expected:Int, name:String):Void {
		if (actual != expected) {
			throw name + " expects " + expected + " args";
		}
	}

	function resolveConstant(name:String):Null<Float> {
		return switch (name) {
			case "PI", "Math.PI", "math.PI":
				Math.PI;
			case "E", "Math.E", "math.E":
				Math.exp(1);
			default:
				null;
		}
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

	function parseNumber():Float {
		final start = index;
		while (index < source.length) {
			final ch = source.charAt(index);
			if (!isDigit(ch) && ch != ".") break;
			index++;
		}
		return Std.parseFloat(source.substring(start, index));
	}

	inline function skipSpaces():Void {
		while (index < source.length && isSpace(source.charAt(index))) {
			index++;
		}
	}

	inline function match(token:String):Bool {
		skipSpaces();
		if (source.substr(index, token.length) == token) {
			index += token.length;
			return true;
		}
		return false;
	}

	inline function expect(token:String):Void {
		if (!match(token)) {
			throw "Expected " + token;
		}
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
		return isIdentStart(ch) || isDigit(ch) || ch == ".";
	}
}
