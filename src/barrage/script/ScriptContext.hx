package barrage.script;

import barrage.instancing.IRng;
import hscript.Interp;
#if barrage_profile
import barrage.instancing.RuntimeProfile;
#end

class ScriptContext {
	public var rng:IRng;
	#if barrage_profile
	public var profile:RuntimeProfile;
	#end
	public var strictNativeExpressions:Bool;

	final vars:Map<String, Float>;
	var interpDirty:Bool = true;

	public function new(rng:IRng, strictNativeExpressions:Bool = false, ?profile:Dynamic) {
		this.rng = rng;
		#if barrage_profile
		this.profile = cast profile;
		#end
		this.strictNativeExpressions = strictNativeExpressions;
		this.vars = new Map<String, Float>();
	}

	public inline function rand():Float {
		return rng.nextFloat();
	}

	public inline function setVar(name:String, value:Float):Void {
		vars.set(name, value);
		interpDirty = true;
	}

	public inline function getVar(name:String):Null<Float> {
		return vars.get(name);
	}

	public function syncToInterp(interp:Interp):Void {
		if (!interpDirty) {
			return;
		}
		for (name in vars.keys()) {
			interp.variables.set(name, vars.get(name));
		}
		interpDirty = false;
	}
}
