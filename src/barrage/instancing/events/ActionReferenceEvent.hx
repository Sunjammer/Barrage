package barrage.instancing.events;

import barrage.data.EventDef;
import barrage.data.events.ActionReferenceEventDef;
import barrage.instancing.events.ITriggerableEvent;
import barrage.instancing.RunningAction;
import barrage.instancing.RunningBarrage;

class ActionReferenceEvent implements ITriggerableEvent {
	public var def:ActionReferenceEventDef;
	public var hasRun:Bool;

	public function new(def:EventDef) {
		this.def = cast def;
	}

	public inline function trigger(runningAction:RunningAction, runningBarrage:RunningBarrage, delta:Float):Void {
		runningBarrage.runActionByID(runningAction, def.actionID, runningAction.triggeringBullet, def.overrides, delta);
	}

	public inline function getType():EventType {
		return def.type;
	}
}
