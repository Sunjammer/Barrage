package barrage.data.events;

import barrage.data.EventDef;
import barrage.data.properties.Property;

class FireEventDef extends EventDef {
	public var bulletID:Int = -1;
	public var speed:Property;
	public var acceleration:Property;
	public var direction:Property;
	public var position:Property;

	public function new() {
		super();
		type = EventType.FIRE;
	}
}
