package barrage.instancing.events;

import barrage.data.EventDef;
import barrage.data.events.WaitDef;
import barrage.instancing.events.ITriggerableEvent;
import barrage.instancing.RunningAction;
import barrage.instancing.RunningBarrage;

class Wait implements ITriggerableEvent {
	public var hasRun:Bool;
	public var def:WaitDef;

	public function new(def:EventDef) {
		this.def = cast def;
	}

	public inline function trigger(runningAction:RunningAction, runningBarrage:RunningBarrage, delta:Float):Void {
		var sleepTimeNum:Float;
		if (def.scripted) {
			sleepTimeNum = def.waitTimeScript.eval(runningBarrage.scriptContext, runningAction.enterSerial, runningAction.cycleCount, runningBarrage.tickCount);
		} else {
			sleepTimeNum = def.waitTime;
		}
		switch (def.durationType) {
			case SECONDS:
				runningAction.sleepTime += sleepTimeNum;
			case FRAMES:
				runningAction.sleepTime += (sleepTimeNum * 1 / runningBarrage.owner.frameRate);
		}
	}

	public inline function getType():EventType {
		return def.type;
	}
}
