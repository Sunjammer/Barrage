package barrage.instancing;

import barrage.data.ActionDef;
import barrage.data.properties.Property;
import barrage.ir.CompiledAction;
import barrage.ir.Instruction;
import barrage.instancing.ActionStateStore.ActionHandle;
import barrage.instancing.RunningBarrage;

class RunningAction {
	public var def:ActionDef;
	public var sleepTime(get, set):Float;
	public var currentBullet(get, set):IBarrageBullet;
	public var triggeringBullet(get, set):IBarrageBullet;
	public var prevAngle(get, set):Float;
	public var prevSpeed(get, set):Float;
	public var prevAccel(get, set):Float;
	public var prevPositionX(get, set):Float;
	public var prevPositionY(get, set):Float;
	public var actionTime(get, set):Float;
	public var prevDelta(get, set):Float;
	public var enterSerial(get, set):Int;

	var barrage:RunningBarrage;
	final stateStore:ActionStateStore;
	public final stateHandle:ActionHandle;
	var compiledAction:Null<CompiledAction>;
	var vmUnrolled:Bool;
	var vmCycleInstructionCount:Int;
	var vmUnrolledCycles:Int;
	var repeatCount:Int;
	var endless:Bool;
	var completedCycles(get, set):Int;
	var eventsPerCycle:Int;
	var runEvents(get, set):Int;

	public var callingAction(get, set):Null<RunningAction>;
	public var properties:Array<Property>;

	public function new(runningBarrage:RunningBarrage, def:ActionDef) {
		this.def = def;
		this.stateStore = runningBarrage.getActionStore();
		this.stateHandle = runningBarrage.allocActionState();
		this.compiledAction = runningBarrage.compiledProgram != null ? runningBarrage.compiledProgram.actions[def.id] : null;
		this.vmUnrolled = this.compiledAction != null && this.compiledAction.unrolledCycles > 1;
		this.vmCycleInstructionCount = this.compiledAction != null ? this.compiledAction.cycleInstructionCount : 0;
		this.vmUnrolledCycles = this.compiledAction != null ? this.compiledAction.unrolledCycles : 1;

		prevAngle = prevSpeed = prevAccel = sleepTime = prevDelta = prevPositionX = prevPositionY = 0;
		enterSerial = 0;

		properties = [];
		for (p in def.properties) {
			properties.push(p.clone());
		}

		// #if debug
		// var repeatCount = def.events.length;
		// #else
		repeatCount = Std.int(def.repeatCount.get(runningBarrage, this));
		if (repeatCount < 0)
			repeatCount = 0;
		endless = def.endless;
		if (compiledAction != null && compiledAction.repeatCountOverride != null) {
			repeatCount = compiledAction.repeatCountOverride;
			endless = false;
		}
		eventsPerCycle = compiledAction.instructions.length;
		runEvents = 0;
		completedCycles = 0;
	}

	function repeat(runningBarrage:RunningBarrage):Void {
		completedCycles++;
		if (!endless && completedCycles >= repeatCount) {
			runningBarrage.stopAction(this);
			return;
		}
		runEvents = 0;
	}

	public function update(runningBarrage:RunningBarrage, delta:Float):Void {
		runningBarrage.executeActionHandleVm(stateHandle, this, delta);
	}

	public inline function getInstruction(index:Int):Instruction {
		return compiledAction.instructions[index];
	}

	public inline function getEventsPerCycle():Int {
		return eventsPerCycle;
	}

	public inline function isVmUnrolled():Bool {
		return vmUnrolled;
	}

	public inline function getVmCycleInstructionCount():Int {
		return vmCycleInstructionCount;
	}

	public inline function getVmUnrolledCycles():Int {
		return vmUnrolledCycles;
	}

	public inline function getRepeatCountLimit():Int {
		return repeatCount;
	}

	public inline function isEndlessAction():Bool {
		return endless;
	}

	public function getProperty(name:String):Property {
		for (p in properties) {
			if (p.name == name)
				return p;
		}
		if (callingAction != null) {
			return callingAction.getProperty(name);
		}
		return null;
	}

	public inline function enter(callingAction:Null<RunningAction>, barrage:RunningBarrage, ?overrides:Array<Property>) {
		enterSerial++;
		actionTime = 0;
		if (overrides != null) {
			for (o in overrides) {
				for (p in properties) {
					if (p.name == o.name) {
						p.copyFrom(o);
						// trace("Override: " + p.get(barrage,this));
					}
				}
			}
		}
		for (p in properties) {
			barrage.scriptContext.setVar(p.name, p.get(barrage, callingAction));
		}
		this.callingAction = callingAction;
		this.barrage = barrage;
	}

	public inline function exit(barrage:RunningBarrage) {
		currentBullet = null;
		barrage.releaseActionState(stateHandle);
	}

	public var cycleCount(get, never):Int;

	inline function get_cycleCount():Int {
		return completedCycles;
	}

	inline function get_sleepTime():Float {
		return stateStore.sleepTime[stateHandle];
	}

	inline function set_sleepTime(value:Float):Float {
		return stateStore.sleepTime[stateHandle] = value;
	}

	inline function get_currentBullet():IBarrageBullet {
		return stateStore.currentBullet[stateHandle];
	}

	inline function set_currentBullet(value:IBarrageBullet):IBarrageBullet {
		return stateStore.currentBullet[stateHandle] = value;
	}

	inline function get_triggeringBullet():IBarrageBullet {
		return stateStore.triggeringBullet[stateHandle];
	}

	inline function set_triggeringBullet(value:IBarrageBullet):IBarrageBullet {
		return stateStore.triggeringBullet[stateHandle] = value;
	}

	inline function get_prevAngle():Float {
		return stateStore.prevAngle[stateHandle];
	}

	inline function set_prevAngle(value:Float):Float {
		return stateStore.prevAngle[stateHandle] = value;
	}

	inline function get_prevSpeed():Float {
		return stateStore.prevSpeed[stateHandle];
	}

	inline function set_prevSpeed(value:Float):Float {
		return stateStore.prevSpeed[stateHandle] = value;
	}

	inline function get_prevAccel():Float {
		return stateStore.prevAccel[stateHandle];
	}

	inline function set_prevAccel(value:Float):Float {
		return stateStore.prevAccel[stateHandle] = value;
	}

	inline function get_prevPositionX():Float {
		return stateStore.prevPositionX[stateHandle];
	}

	inline function set_prevPositionX(value:Float):Float {
		return stateStore.prevPositionX[stateHandle] = value;
	}

	inline function get_prevPositionY():Float {
		return stateStore.prevPositionY[stateHandle];
	}

	inline function set_prevPositionY(value:Float):Float {
		return stateStore.prevPositionY[stateHandle] = value;
	}

	inline function get_actionTime():Float {
		return stateStore.actionTime[stateHandle];
	}

	inline function set_actionTime(value:Float):Float {
		return stateStore.actionTime[stateHandle] = value;
	}

	inline function get_prevDelta():Float {
		return stateStore.prevDelta[stateHandle];
	}

	inline function set_prevDelta(value:Float):Float {
		return stateStore.prevDelta[stateHandle] = value;
	}

	inline function get_enterSerial():Int {
		return stateStore.enterSerial[stateHandle];
	}

	inline function set_enterSerial(value:Int):Int {
		return stateStore.enterSerial[stateHandle] = value;
	}

	inline function get_completedCycles():Int {
		return stateStore.completedCycles[stateHandle];
	}

	inline function set_completedCycles(value:Int):Int {
		return stateStore.completedCycles[stateHandle] = value;
	}

	inline function get_runEvents():Int {
		return stateStore.runEvents[stateHandle];
	}

	inline function set_runEvents(value:Int):Int {
		return stateStore.runEvents[stateHandle] = value;
	}

	inline function get_callingAction():Null<RunningAction> {
		return stateStore.callingAction[stateHandle];
	}

	inline function set_callingAction(value:Null<RunningAction>):Null<RunningAction> {
		return stateStore.callingAction[stateHandle] = value;
	}
}
