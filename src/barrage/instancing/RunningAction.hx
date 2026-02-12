package barrage.instancing;

import barrage.data.ActionDef;
import barrage.data.EventDef.EventType;
import barrage.data.properties.Property;
import barrage.instancing.events.ITriggerableEvent;
import barrage.instancing.RunningBarrage;
import barrage.instancing.events.EventFactory;

class RunningAction {
	public var def:ActionDef;
	public var events:Array<ITriggerableEvent>;
	public var sleepTime:Float;
	public var currentBullet:IBarrageBullet;
	public var triggeringBullet:IBarrageBullet;
	public var prevAngle:Float;
	public var prevSpeed:Float;
	public var prevAccel:Float;
	public var prevPositionX:Float;
	public var prevPositionY:Float;
	public var actionTime:Float;
	public var prevDelta:Float;

	var barrage:RunningBarrage;
	var repeatCount:Int;
	var endless:Bool;
	var completedCycles:Int;
	var eventsPerCycle:Int;
	var runEvents:Int;

	public var callingAction:RunningAction;
	public var properties:Array<Property>;

	public function new(runningBarrage:RunningBarrage, def:ActionDef) {
		this.def = def;

		prevAngle = prevSpeed = prevAccel = sleepTime = prevDelta = prevPositionX = prevPositionY = 0;

		properties = [];
		for (p in def.properties) {
			properties.push(p.clone());
		}

		// #if debug
		// var repeatCount = def.events.length;
		// #else
		repeatCount = Std.int(def.repeatCount.get(runningBarrage, this));
		if (repeatCount < 0)
			repeatCount = 0;
		endless = def.endless;
		// #end
		events = new Array<ITriggerableEvent>();
		for (i in 0...def.events.length) {
			events.push(EventFactory.create(def.events[i]));
		}
		eventsPerCycle = events.length;
		runEvents = 0;
		completedCycles = 0;
	}

	function repeat(runningBarrage:RunningBarrage):Void {
		completedCycles++;
		if (!endless && completedCycles >= repeatCount) {
			runningBarrage.stopAction(this);
			return;
		}
		runEvents = 0;
	}

	public function update(runningBarrage:RunningBarrage, delta:Float):Void {
		if (events.length == 0) {
			runningBarrage.stopAction(this);
			return;
		} else {
			actionTime += delta;
			sleepTime -= delta;
			if (sleepTime <= 0) {
				// delta += Math.abs(sleepTime);
				runningBarrage.owner.executor.variables.set("actiontime", actionTime);
				while (runEvents < eventsPerCycle) {
					var e = events[runEvents++];
					runEvent(runningBarrage, e, delta);
					if (e.getType() == EventType.WAIT) {
						break;
					}
				}
				if (runEvents == eventsPerCycle && sleepTime <= 0) {
					repeat(runningBarrage);
				}
			}
		}
	}

	inline function runEvent(runningBarrage:RunningBarrage, e:ITriggerableEvent, delta:Float):Void {
		e.hasRun = true;
		runningBarrage.owner.executor.variables.set("repeatcount", completedCycles);
		e.trigger(this, runningBarrage, delta);
	}

	public function getProperty(name:String):Property {
		for (p in properties) {
			if (p.name == name)
				return p;
		}
		if (callingAction != null) {
			return callingAction.getProperty(name);
		}
		return null;
	}

	public inline function enter(callingAction:RunningAction, barrage:RunningBarrage, ?overrides:Array<Property>) {
		actionTime = 0;
		if (overrides != null) {
			for (o in overrides) {
				for (p in properties) {
					if (p.name == o.name) {
						p.copyFrom(o);
						// trace("Override: " + p.get(barrage,this));
					}
				}
			}
		}
		for (p in properties) {
			barrage.owner.executor.variables.set(p.name, p.get(barrage, callingAction));
		}
		this.callingAction = callingAction;
		this.barrage = barrage;
	}

	public inline function exit(barrage:RunningBarrage) {
		currentBullet = null;
	}
}
