package barrage.data.events;

import barrage.data.EventDef;
import barrage.data.properties.DurationType;
import barrage.script.ScriptValue;

class WaitDef extends EventDef {
	public var waitTime:Float;
	public var waitTimeScript:ScriptValue;
	public var scripted:Bool = false;
	public var durationType:DurationType;

	public function new() {
		super();
		type = EventType.WAIT;
	}
}
