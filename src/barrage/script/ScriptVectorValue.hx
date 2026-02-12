package barrage.script;

import haxe.ds.Vector;

class ScriptVectorValue {
	public var xExpr:ScriptValue;
	public var yExpr:ScriptValue;
	final out:Vector<Float>;

	public function new(xExpr:ScriptValue, yExpr:ScriptValue) {
		this.xExpr = xExpr;
		this.yExpr = yExpr;
		this.out = new Vector<Float>(2);
	}

	public inline function eval(ctx:ScriptContext, actionSerial:Int, cycle:Int, tick:Int):Vector<Float> {
		out[0] = xExpr.eval(ctx, actionSerial, cycle, tick);
		out[1] = yExpr.eval(ctx, actionSerial, cycle, tick);
		return out;
	}
}
