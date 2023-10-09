package com.furusystems.barrage.data.events;

import com.furusystems.barrage.data.EventDef;
import com.furusystems.barrage.data.properties.Property;

class ActionReferenceEventDef extends EventDef {
	public var actionID:Int = -1;
	public var overrides:Array<Property>;

	public function new() {
		super();
		overrides = [];
		type = EventType.ACTION_REF;
	}
}
