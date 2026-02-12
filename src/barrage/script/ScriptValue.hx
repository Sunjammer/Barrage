package barrage.script;

import hscript.Expr;
import hscript.Interp;
import haxe.Timer;

private enum EvalTier {
	ALWAYS;
	PER_TICK;
	PER_CYCLE;
	PER_ACTION;
}

class ScriptValue {
	public var source:String;
	public var expr:Expr;
	public var nativeExpr:Null<NativeExpr>;
	public var tier:EvalTier;
	public var constant:Null<Float>;

	var hasCached:Bool = false;
	var cachedValue:Float = 0;
	var cachedActionSerial:Int = -1;
	var cachedCycle:Int = -1;
	var cachedTick:Int = -1;

	public function new(source:String, expr:Expr) {
		this.source = source;
		this.expr = expr;
		this.nativeExpr = NativeExpr.compile(source);
		this.tier = inferTier(source);
		this.constant = if (nativeExpr != null && nativeExpr.isConstant()) nativeExpr.evalConstant() else null;
	}

	public function eval(interp:Interp, ctx:ScriptContext, actionSerial:Int, cycle:Int, tick:Int):Float {
		if (constant != null) {
			return constant;
		}
		if (canReuse(actionSerial, cycle, tick)) {
			return cachedValue;
		}

		final t0 = Timer.stamp();
		final out = if (nativeExpr != null) {
			ctx.profile.nativeScriptEvals++;
			nativeExpr.eval(interp, ctx);
		} else {
			ctx.profile.fallbackScriptEvals++;
			ctx.syncToInterp(interp);
			interp.execute(expr);
		}
		ctx.profile.scriptEvalSeconds += (Timer.stamp() - t0);
		hasCached = true;
		cachedValue = out;
		cachedActionSerial = actionSerial;
		cachedCycle = cycle;
		cachedTick = tick;
		return out;
	}

	function canReuse(actionSerial:Int, cycle:Int, tick:Int):Bool {
		if (!hasCached) return false;
		return switch (tier) {
			case ALWAYS:
				false;
			case PER_TICK:
				cachedActionSerial == actionSerial && cachedTick == tick;
			case PER_CYCLE:
				cachedActionSerial == actionSerial && cachedCycle == cycle;
			case PER_ACTION:
				cachedActionSerial == actionSerial;
		}
	}

	static function inferTier(source:String):EvalTier {
		final s = source.toLowerCase();
		if (s.indexOf("rand(") >= 0 || s.indexOf("math.random") >= 0) {
			return ALWAYS;
		}
		if (s.indexOf("actiontime") >= 0 || s.indexOf("barragetime") >= 0) {
			return PER_TICK;
		}
		if (s.indexOf("repeatcount") >= 0) {
			return PER_CYCLE;
		}
		return PER_ACTION;
	}
}
