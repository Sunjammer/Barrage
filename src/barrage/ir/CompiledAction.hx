package barrage.ir;

import barrage.data.ActionDef;

class CompiledAction {
	public var def:ActionDef;
	public var instructions:Array<Instruction>;
	public var repeatCountOverride:Null<Int>;
	public var cycleInstructionCount:Int;
	public var unrolledCycles:Int;

	public function new(def:ActionDef, instructions:Array<Instruction>, ?repeatCountOverride:Int, ?cycleInstructionCount:Int, ?unrolledCycles:Int) {
		this.def = def;
		this.instructions = instructions;
		this.repeatCountOverride = repeatCountOverride;
		this.cycleInstructionCount = cycleInstructionCount == null ? instructions.length : cycleInstructionCount;
		this.unrolledCycles = unrolledCycles == null ? 1 : unrolledCycles;
	}
}
