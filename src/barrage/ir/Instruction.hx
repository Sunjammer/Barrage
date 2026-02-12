package barrage.ir;

class Instruction {
	public var opcode:Opcode;
	public var eventIndex:Int;
	public var immF0:Float;
	public var immF1:Float;
	public var immI0:Int;

	public function new(opcode:Opcode, eventIndex:Int, immF0:Float = 0.0, immF1:Float = 0.0, immI0:Int = 0) {
		this.opcode = opcode;
		this.eventIndex = eventIndex;
		this.immF0 = immF0;
		this.immF1 = immF1;
		this.immI0 = immI0;
	}
}
