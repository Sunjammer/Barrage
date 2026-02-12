package barrage.instancing.events;

import barrage.data.EventDef;
import barrage.data.events.DieEventDef;
import barrage.instancing.events.ITriggerableEvent;
import barrage.instancing.RunningAction;
import barrage.instancing.RunningBarrage;

class DieEvent implements ITriggerableEvent {
	public var def:DieEventDef;
	public var hasRun:Bool;

	public function new(def:EventDef) {
		this.def = cast def;
	}

	public inline function trigger(runningAction:RunningAction, runningBarrage:RunningBarrage, delta:Float):Void {
		runningBarrage.killBullet(runningAction.triggeringBullet);
	}

	public inline function getType():EventType {
		return def.type;
	}
}
