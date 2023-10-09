package barrage.data.events;

import barrage.data.EventDef.EventType;
import barrage.data.properties.DurationType;
import hscript.Expr;

class PropertyTweenDef extends PropertySetDef {
	public var tweenTime:Float;
	public var tweenTimeScript:Expr;
	public var scripted:Bool = false;
	public var durationType:DurationType;

	public function new() {
		super();
		type = EventType.PROPERTY_TWEEN;
	}
}
