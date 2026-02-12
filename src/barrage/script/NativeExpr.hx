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
	final ops:Array<Int>;
	final immF:Array<Float>;
	final immI:Array<Int>;
	final varNames:Array<String>;
	final varSlots:Array<Int>;
	var boundCtx:ScriptContext;
	final isConst:Bool;
	final stack:Array<Float>;

	public function new(rpn:Array<NativeToken>) {
		ops = [];
		immF = [];
		immI = [];
		varNames = [];
		final varIndex = new Map<String, Int>();
		var constant = true;

		for (t in rpn) {
			switch (t) {
				case TNumber(v):
					pushOp(NativeOp.PUSH_CONST, v, 0);
				case TIdentifier(name):
					constant = false;
					var idx = varIndex.get(name);
					if (idx == null) {
						idx = varNames.length;
						varNames.push(name);
						varIndex.set(name, idx);
					}
					pushOp(NativeOp.PUSH_VAR, 0.0, idx);
				case TRand:
					constant = false;
					pushOp(NativeOp.RAND, 0.0, 0);
				case TSin:
					pushOp(NativeOp.SIN, 0.0, 0);
				case TCos:
					pushOp(NativeOp.COS, 0.0, 0);
				case TTan:
					pushOp(NativeOp.TAN, 0.0, 0);
				case TAbs:
					pushOp(NativeOp.ABS, 0.0, 0);
				case TSqrt:
					pushOp(NativeOp.SQRT, 0.0, 0);
				case TFloor:
					pushOp(NativeOp.FLOOR, 0.0, 0);
				case TCeil:
					pushOp(NativeOp.CEIL, 0.0, 0);
				case TRound:
					pushOp(NativeOp.ROUND, 0.0, 0);
				case TExp:
					pushOp(NativeOp.EXP, 0.0, 0);
				case TLog:
					pushOp(NativeOp.LOG, 0.0, 0);
				case TAsin:
					pushOp(NativeOp.ASIN, 0.0, 0);
				case TAcos:
					pushOp(NativeOp.ACOS, 0.0, 0);
				case TAtan:
					pushOp(NativeOp.ATAN, 0.0, 0);
				case TPow:
					pushOp(NativeOp.POW, 0.0, 0);
				case TMin:
					pushOp(NativeOp.MIN, 0.0, 0);
				case TMax:
					pushOp(NativeOp.MAX, 0.0, 0);
				case TAtan2:
					pushOp(NativeOp.ATAN2, 0.0, 0);
				case TAdd:
					pushOp(NativeOp.ADD, 0.0, 0);
				case TSub:
					pushOp(NativeOp.SUB, 0.0, 0);
				case TMul:
					pushOp(NativeOp.MUL, 0.0, 0);
				case TDiv:
					pushOp(NativeOp.DIV, 0.0, 0);
				case TNeg:
					pushOp(NativeOp.NEG, 0.0, 0);
			}
		}

		isConst = constant;
		varSlots = [];
		boundCtx = null;
		this.stack = [];
	}

	inline function pushOp(op:Int, f:Float, i:Int):Void {
		ops.push(op);
		immF.push(f);
		immI.push(i);
	}

	public function eval(ctx:ScriptContext):Float {
		return evalInternal(ctx, false);
	}

	function evalInternal(ctx:ScriptContext, constMode:Bool):Float {
		if (!constMode && !isConst) {
			bindSlots(ctx);
		}
		var top = 0;
		for (pc in 0...ops.length) {
			switch (ops[pc]) {
				case NativeOp.PUSH_CONST:
					stack[top++] = immF[pc];
				case NativeOp.PUSH_VAR:
					if (constMode)
						throw "NativeExpr is not constant";
					final v = ctx.getVarBySlot(varSlots[immI[pc]]);
					if (v == null)
						throw "Unknown variable: " + varNames[immI[pc]];
					stack[top++] = v;
				case NativeOp.RAND:
					if (constMode)
						throw "NativeExpr is not constant";
					stack[top++] = ctx.rand();
				case NativeOp.SIN:
					stack[top - 1] = Math.sin(stack[top - 1]);
				case NativeOp.COS:
					stack[top - 1] = Math.cos(stack[top - 1]);
				case NativeOp.TAN:
					stack[top - 1] = Math.tan(stack[top - 1]);
				case NativeOp.ABS:
					stack[top - 1] = Math.abs(stack[top - 1]);
				case NativeOp.SQRT:
					stack[top - 1] = Math.sqrt(stack[top - 1]);
				case NativeOp.FLOOR:
					stack[top - 1] = Math.floor(stack[top - 1]);
				case NativeOp.CEIL:
					stack[top - 1] = Math.ceil(stack[top - 1]);
				case NativeOp.ROUND:
					stack[top - 1] = Math.round(stack[top - 1]);
				case NativeOp.EXP:
					stack[top - 1] = Math.exp(stack[top - 1]);
				case NativeOp.LOG:
					stack[top - 1] = Math.log(stack[top - 1]);
				case NativeOp.ASIN:
					stack[top - 1] = Math.asin(stack[top - 1]);
				case NativeOp.ACOS:
					stack[top - 1] = Math.acos(stack[top - 1]);
				case NativeOp.ATAN:
					stack[top - 1] = Math.atan(stack[top - 1]);
				case NativeOp.POW:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.pow(a, b);
				case NativeOp.MIN:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.min(a, b);
				case NativeOp.MAX:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.max(a, b);
				case NativeOp.ATAN2:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = Math.atan2(a, b);
				case NativeOp.ADD:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a + b;
				case NativeOp.SUB:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a - b;
				case NativeOp.MUL:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a * b;
				case NativeOp.DIV:
					final b = stack[--top];
					final a = stack[--top];
					stack[top++] = a / b;
				case NativeOp.NEG:
					stack[top - 1] = -stack[top - 1];
			}
		}
		if (top != 1)
			throw "Invalid native expression stack state";
		return stack[0];
	}

	public function isConstant():Bool {
		return isConst;
	}

	public function evalConstant():Float {
		if (!isConst)
			throw "NativeExpr is not constant";
		return evalInternal(null, true);
	}

	inline function bindSlots(ctx:ScriptContext):Void {
		if (boundCtx == ctx) {
			return;
		}
		boundCtx = ctx;
		varSlots.resize(varNames.length);
		for (i in 0...varNames.length) {
			varSlots[i] = ctx.resolveSlot(varNames[i]);
		}
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

private class NativeOp {
	public static inline var PUSH_CONST:Int = 0;
	public static inline var PUSH_VAR:Int = 1;
	public static inline var RAND:Int = 2;
	public static inline var SIN:Int = 3;
	public static inline var COS:Int = 4;
	public static inline var TAN:Int = 5;
	public static inline var ABS:Int = 6;
	public static inline var SQRT:Int = 7;
	public static inline var FLOOR:Int = 8;
	public static inline var CEIL:Int = 9;
	public static inline var ROUND:Int = 10;
	public static inline var EXP:Int = 11;
	public static inline var LOG:Int = 12;
	public static inline var ASIN:Int = 13;
	public static inline var ACOS:Int = 14;
	public static inline var ATAN:Int = 15;
	public static inline var POW:Int = 16;
	public static inline var MIN:Int = 17;
	public static inline var MAX:Int = 18;
	public static inline var ATAN2:Int = 19;
	public static inline var ADD:Int = 20;
	public static inline var SUB:Int = 21;
	public static inline var MUL:Int = 22;
	public static inline var DIV:Int = 23;
	public static inline var NEG:Int = 24;
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
