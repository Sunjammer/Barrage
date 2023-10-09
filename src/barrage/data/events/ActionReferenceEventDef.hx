package barrage.data.events;

import barrage.data.EventDef;
import barrage.data.properties.Property;

class ActionReferenceEventDef extends EventDef {
	public var actionID:Int = -1;
	public var overrides:Array<Property>;

	public function new() {
		super();
		overrides = [];
		type = EventType.ACTION_REF;
	}
}
