package com.furusystems.barrage.data;

import com.furusystems.barrage.data.EventDef;
import com.furusystems.barrage.data.properties.Property;

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
