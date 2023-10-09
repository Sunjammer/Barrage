package barrage.data.events;

import barrage.data.EventDef;
import barrage.data.properties.Property;

class PropertySetDef extends EventDef {
	public var speed:Property;
	public var direction:Property;
	public var acceleration:Property;
	public var position:Property;
	public var relative:Bool;

	public function new() {
		super();
		type = EventType.PROPERTY_SET;
	}
}
