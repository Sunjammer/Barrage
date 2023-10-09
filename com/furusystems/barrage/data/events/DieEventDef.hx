package com.furusystems.barrage.data.events;

import com.furusystems.barrage.data.EventDef;

class DieEventDef extends EventDef {
	public function new() {
		super();
		type = EventType.DIE;
	}
}
