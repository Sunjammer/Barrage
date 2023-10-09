package barrage.data.events;

import barrage.data.EventDef;

class ActionEventDef extends EventDef {
	public var actionID:Int = -1;

	public function new() {
		super();
		type = EventType.ACTION;
	}
}
