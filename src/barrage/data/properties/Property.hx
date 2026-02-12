package barrage.data.properties;

import barrage.instancing.RunningAction;
import barrage.instancing.RunningBarrage;
import barrage.data.targets.TargetSelector;
import barrage.script.ScriptValue;
import haxe.ds.Vector;
import haxe.EnumFlags;

enum PropertyModifier {
	ABSOLUTE;
	INCREMENTAL;
	RELATIVE;
	AIMED;
	RANDOM;
}

class Property {
	public var modifier:EnumFlags<PropertyModifier>;
	public var isRandom:Bool;
	public var constValue:Float = 0;
	public var constValueVec:Vector<Float>;
	public var script:Null<ScriptValue>;
	public var scripted:Bool = false;
	public var name:String;
	public var target:TargetSelector = PLAYER;

	public function new(name:String = "Property") {
		this.name = name;
		modifier = new EnumFlags<PropertyModifier>();
		modifier.set(ABSOLUTE);
		constValueVec = new Vector<Float>(2);
		constValueVec[0] = constValueVec[1] = 0;
	}

	public inline function copyFrom(other:Property):Void {
		this.isRandom = other.isRandom;
		this.constValue = other.constValue;
		Vector.blit(other.constValueVec, 0, constValueVec, 0, constValueVec.length);
		this.script = other.script;
		this.scripted = other.scripted;
		this.name = other.name;
		this.target = other.target;
		this.modifier = other.modifier;
	}

	public inline function clone():Property {
		var n = new Property(name);
		n.copyFrom(this);
		return n;
	}

	public inline function get(runningBarrage:RunningBarrage, action:RunningAction):Float {
		if (scripted) {
			final serial = action == null ? -1 : action.enterSerial;
			final cycle = action == null ? 0 : action.cycleCount;
			return script.eval(runningBarrage.owner.executor, serial, cycle, runningBarrage.tickCount);
		} else {
			// trace("Value: " + constValue);
			return constValue;
		}
	}

	public inline function getVector(runningBarrage:RunningBarrage, action:RunningAction):Vector<Float> {
		if (scripted) {
			return runningBarrage.owner.executor.execute(script.expr);
		} else {
			return constValueVec;
		}
	}

	public inline function set(f:Float):Float {
		scripted = false;
		return constValue = f;
	}

	public inline function setVec(x:Float, y:Float):Vector<Float> {
		scripted = false;
		constValueVec.set(0, x);
		constValueVec.set(1, y);
		return constValueVec;
	}

	public function toString():String {
		return '[$name]';
	}
}
