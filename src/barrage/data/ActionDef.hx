package barrage.data;

import barrage.data.EventDef;
import barrage.data.properties.Property;

class ActionDef extends BarrageItemDef {
	public var events:Array<EventDef>;
	public var repeatCount:Property;
	public var endless:Bool;
	public var properties:Array<Property>;

	public function new(name:String = "") {
		repeatCount = new Property();
		repeatCount.constValue = 1;
		events = [];
		properties = [];
		super(name);
	}
}
