package barrage.data.events;

import barrage.data.EventDef;

class DieEventDef extends EventDef {
	public function new() {
		super();
		type = EventType.DIE;
	}
}
