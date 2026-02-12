package barrage.script;

import barrage.instancing.IRng;
#if barrage_profile
import barrage.instancing.RuntimeProfile;
#end

class ScriptContext {
	public var rng:IRng;
	#if barrage_profile
	public var profile:RuntimeProfile;
	#end
	public var strictNativeExpressions:Bool;

	final slotsByName:Map<String, Int>;
	final slotValues:Array<Float>;
	final slotHasValue:Array<Bool>;

	public function new(rng:IRng, strictNativeExpressions:Bool = false, ?profile:Dynamic) {
		this.rng = rng;
		#if barrage_profile
		this.profile = cast profile;
		#end
		this.strictNativeExpressions = strictNativeExpressions;
		this.slotsByName = new Map<String, Int>();
		this.slotValues = [];
		this.slotHasValue = [];
	}

	public inline function rand():Float {
		return rng.nextFloat();
	}

	public inline function setVar(name:String, value:Float):Void {
		setVarBySlot(resolveSlot(name), value);
	}

	public inline function getVar(name:String):Null<Float> {
		final slot = slotsByName.get(name);
		return slot == null ? null : getVarBySlot(slot);
	}

	public inline function resolveSlot(name:String):Int {
		var slot = slotsByName.get(name);
		if (slot == null) {
			slot = slotValues.length;
			slotsByName.set(name, slot);
			slotValues.push(0.0);
			slotHasValue.push(false);
		}
		return slot;
	}

	public inline function getVarBySlot(slot:Int):Null<Float> {
		return slotHasValue[slot] ? slotValues[slot] : null;
	}

	public inline function setVarBySlot(slot:Int, value:Float):Void {
		slotValues[slot] = value;
		slotHasValue[slot] = true;
	}
}
