package barrage.ir;

class Instruction {
	public var opcode:Opcode;
	public var eventIndex:Int;

	public function new(opcode:Opcode, eventIndex:Int) {
		this.opcode = opcode;
		this.eventIndex = eventIndex;
	}
}
