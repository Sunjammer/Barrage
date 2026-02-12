package barrage.instancing.events;

import barrage.data.EventDef;
import barrage.data.events.FireEventDef;
import barrage.instancing.events.ITriggerableEvent;
import barrage.instancing.RunningAction;
import barrage.instancing.RunningBarrage;

class FireEvent implements ITriggerableEvent {
	public var def:FireEventDef;
	public var hasRun:Bool;

	public function new(def:EventDef) {
		this.def = cast def;
	}

	public inline function trigger(runningAction:RunningAction, runningBarrage:RunningBarrage, delta:Float):Void {
		final bulletID = def.bulletID;
		runningAction.currentBullet = runningBarrage.fire(runningAction, this, bulletID, delta);
		if (bulletID != -1) {
			final bd = runningBarrage.owner.bullets[bulletID];
			if (bd.action != -1) {
				runningBarrage.runActionByID(runningAction, bd.action, runningAction.currentBullet);
			}
		}
	}

	public inline function getType():EventType {
		return def.type;
	}
}
