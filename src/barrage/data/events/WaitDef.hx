package barrage.data.events;

import barrage.data.EventDef;
import barrage.data.properties.DurationType;
import hscript.Expr;

class WaitDef extends EventDef {
	public var waitTime:Float;
	public var waitTimeScript:Expr;
	public var scripted:Bool = false;
	public var durationType:DurationType;

	public function new() {
		super();
		type = EventType.WAIT;
	}
}
