package barrage.instancing.events;

import barrage.instancing.RunningAction;
import barrage.instancing.RunningBarrage;
import barrage.data.EventDef.EventType;

interface ITriggerableEvent {
	public var hasRun:Bool;
	public function trigger(runningAction:RunningAction, runningBarrage:RunningBarrage, delta:Float):Void;
	public function getType():EventType;
}
