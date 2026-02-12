package barrage.script;

import barrage.instancing.IRng;
import barrage.instancing.RuntimeProfile;
import hscript.Interp;

class ScriptContext {
	public var rng:IRng;
	public var profile:RuntimeProfile;

	final vars:Map<String, Float>;
	var interpDirty:Bool = true;

	public function new(rng:IRng, profile:RuntimeProfile) {
		this.rng = rng;
		this.profile = profile;
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
