package barrage.instancing;

import barrage.data.ActionDef;
import barrage.data.EventDef.EventType;
import barrage.data.events.ActionEventDef;
import barrage.data.events.ActionReferenceEventDef;
import barrage.data.events.DieEventDef;
import barrage.data.events.FireEventDef;
import barrage.data.events.PropertySetDef;
import barrage.data.events.PropertyTweenDef;
import barrage.data.events.WaitDef;
import barrage.data.properties.DurationType;
import barrage.data.properties.Property;
import barrage.ir.CompiledAction;
import barrage.ir.Instruction;
import barrage.ir.Opcode;
import barrage.instancing.ActionStateStore.ActionHandle;
 #if barrage_legacy
import barrage.instancing.events.ITriggerableEvent;
import barrage.instancing.events.EventFactory;
 #end
import barrage.instancing.RunningBarrage;

class RunningAction {
	public var def:ActionDef;
	#if barrage_legacy
	public var events:Array<ITriggerableEvent>;
	#end
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
	final stateHandle:ActionHandle;
	var useVmExecution:Bool;
	var compiledAction:Null<CompiledAction>;
	var vmUnrolled:Bool;
	var vmCycleInstructionCount:Int;
	var vmUnrolledCycles:Int;
	var repeatCount:Int;
	var endless:Bool;
	var completedCycles(get, set):Int;
	var eventsPerCycle:Int;
	var runEvents(get, set):Int;

	public var callingAction(get, set):RunningAction;
	public var properties:Array<Property>;

	public function new(runningBarrage:RunningBarrage, def:ActionDef, useVmExecution:Bool = false) {
		this.def = def;
		this.stateStore = runningBarrage.getActionStore();
		this.stateHandle = runningBarrage.allocActionState();
		#if barrage_legacy
		this.compiledAction = useVmExecution && runningBarrage.compiledProgram != null ? runningBarrage.compiledProgram.actions[def.id] : null;
		this.useVmExecution = useVmExecution && this.compiledAction != null;
		#else
		this.compiledAction = runningBarrage.compiledProgram != null ? runningBarrage.compiledProgram.actions[def.id] : null;
		this.useVmExecution = this.compiledAction != null;
		#end
		this.vmUnrolled = this.useVmExecution && this.compiledAction != null && this.compiledAction.unrolledCycles > 1;
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
		if (this.useVmExecution && compiledAction != null && compiledAction.repeatCountOverride != null) {
			repeatCount = compiledAction.repeatCountOverride;
			endless = false;
		}
		// #end
		#if barrage_legacy
		events = this.useVmExecution ? [] : new Array<ITriggerableEvent>();
		if (!this.useVmExecution) {
			for (i in 0...def.events.length) {
				events.push(EventFactory.create(def.events[i]));
			}
		}
		eventsPerCycle = events.length;
		#else
		eventsPerCycle = 0;
		#end
		if (this.useVmExecution && compiledAction != null) {
			eventsPerCycle = compiledAction.instructions.length;
		} else if (this.useVmExecution) {
			eventsPerCycle = def.events.length;
		}
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
		#if barrage_legacy
		if (!useVmExecution && events.length == 0) {
			runningBarrage.stopAction(this);
			return;
		} else {
		#else
		{
		#end
			actionTime += delta;
			sleepTime -= delta;
			if (sleepTime <= 0) {
				// delta += Math.abs(sleepTime);
				runningBarrage.setScriptActionTimeVars(actionTime);
				runningBarrage.setScriptRepeatCountVars(completedCycles);
				if (compiledAction != null) {
					var processedThisTick = 0;
					while (runEvents < eventsPerCycle) {
						final instr = compiledAction.instructions[runEvents++];
						runVmInstruction(runningBarrage, instr, delta);
						processedThisTick++;
						if (isWaitOpcode(instr.opcode)) {
							break;
						}
						if (vmUnrolled && processedThisTick >= vmCycleInstructionCount) {
							break;
						}
					}
					if (vmUnrolled) {
						if (sleepTime <= 0 && vmCycleInstructionCount > 0 && (runEvents % vmCycleInstructionCount) == 0) {
							completedCycles++;
							if (completedCycles >= vmUnrolledCycles) {
								runningBarrage.stopAction(this);
							}
						}
						return;
					}
				#if barrage_legacy
				else {
					while (runEvents < eventsPerCycle) {
						var e = events[runEvents++];
						runEvent(runningBarrage, e, delta);
						if (e.getType() == EventType.WAIT) {
							break;
						}
					}
				}
				#end
				}
				if (runEvents == eventsPerCycle && sleepTime <= 0) {
					repeat(runningBarrage);
				}
			}
		}
	}

	#if barrage_legacy
	inline function runEvent(runningBarrage:RunningBarrage, e:ITriggerableEvent, delta:Float):Void {
		e.hasRun = true;
		e.trigger(this, runningBarrage, delta);
	}
	#end

	inline function isWaitOpcode(opcode:Opcode):Bool {
		return switch (opcode) {
			case WAIT | WAIT_SECONDS_CONST | WAIT_FRAMES_CONST:
				true;
			default:
				false;
		}
	}

	inline function runVmInstruction(runningBarrage:RunningBarrage, instr:Instruction, delta:Float):Void {
		switch (instr.opcode) {
			case WAIT:
				vmWait(runningBarrage, cast def.events[instr.eventIndex]);
			case WAIT_SECONDS_CONST:
				sleepTime += instr.immF0;
			case WAIT_FRAMES_CONST:
				sleepTime += instr.immF0;
			case FIRE:
				vmFire(runningBarrage, cast def.events[instr.eventIndex], delta);
			case FIRE_CONST:
				vmFireConst(runningBarrage, cast def.events[instr.eventIndex], delta);
			case PROPERTY_SET:
				vmPropertySet(runningBarrage, cast def.events[instr.eventIndex]);
			case PROPERTY_SET_SPEED_CONST:
				vmPropertySetSpeedConst(runningBarrage, instr.immF0, instr.immI0 != 0);
			case PROPERTY_SET_DIRECTION_CONST:
				vmPropertySetDirectionConst(runningBarrage, instr.immF0, instr.immI0 != 0);
			case PROPERTY_SET_ACCEL_CONST:
				vmPropertySetAccelConst(runningBarrage, instr.immF0, instr.immI0 != 0);
			case PROPERTY_TWEEN:
				vmPropertyTween(runningBarrage, cast def.events[instr.eventIndex], delta);
			case PROPERTY_TWEEN_SPEED_CONST:
				vmPropertyTweenSpeedConst(runningBarrage, instr.immF0, instr.immF1, instr.immI0 != 0, delta);
			case PROPERTY_TWEEN_DIRECTION_CONST:
				vmPropertyTweenDirectionConst(runningBarrage, instr.immF0, instr.immF1, instr.immI0 != 0, delta);
			case PROPERTY_TWEEN_ACCEL_CONST:
				vmPropertyTweenAccelConst(runningBarrage, instr.immF0, instr.immF1, instr.immI0 != 0, delta);
			case ACTION:
				vmAction(runningBarrage, cast def.events[instr.eventIndex], delta);
			case ACTION_REF:
				vmActionRef(runningBarrage, cast def.events[instr.eventIndex], delta);
			case DIE:
				vmDie(runningBarrage, cast def.events[instr.eventIndex]);
		}
	}

	inline function vmWait(runningBarrage:RunningBarrage, waitDef:WaitDef):Void {
		var wait:Float;
		if (waitDef.scripted) {
			wait = waitDef.waitTimeScript.eval(runningBarrage.scriptContext, enterSerial, cycleCount, runningBarrage.tickCount);
		} else {
			wait = waitDef.waitTime;
		}
		switch (waitDef.durationType) {
			case DurationType.SECONDS:
				sleepTime += wait;
			case DurationType.FRAMES:
				sleepTime += wait * (1 / runningBarrage.owner.frameRate);
		}
	}

	inline function vmFire(runningBarrage:RunningBarrage, fireDef:FireEventDef, delta:Float):Void {
		final bulletID = fireDef.bulletID;
		currentBullet = runningBarrage.fireDef(this, fireDef, bulletID, delta);
		if (bulletID != -1) {
			final bd = runningBarrage.owner.bullets[bulletID];
			if (bd.action != -1) {
				runningBarrage.runActionByID(this, bd.action, currentBullet);
			}
		}
	}

	inline function vmFireConst(runningBarrage:RunningBarrage, fireDef:FireEventDef, delta:Float):Void {
		final bulletID = fireDef.bulletID;
		currentBullet = runningBarrage.fireDefConst(this, fireDef, bulletID, delta);
		if (bulletID != -1) {
			final bd = runningBarrage.owner.bullets[bulletID];
			if (bd.action != -1) {
				runningBarrage.runActionByID(this, bd.action, currentBullet);
			}
		}
	}

	inline function vmPropertySet(runningBarrage:RunningBarrage, d:PropertySetDef):Void {
		final bullet = triggeringBullet;
		if (d.speed != null) {
			if (d.speed.modifier.has(RELATIVE)) {
				runningBarrage.setBulletSpeed(bullet, bullet.speed + d.speed.get(runningBarrage, this));
			} else {
				runningBarrage.setBulletSpeed(bullet, d.speed.get(runningBarrage, this));
			}
		}
		if (d.direction != null) {
			var ang:Float = 0;
			if (d.direction.modifier.has(AIMED)) {
				ang = runningBarrage.getAngleToTarget(bullet.posX, bullet.posY, this, d.direction.target);
			} else {
				ang = d.direction.get(runningBarrage, this);
			}
			if (d.relative) {
				runningBarrage.setBulletAngle(bullet, bullet.angle + ang);
			} else {
				runningBarrage.setBulletAngle(bullet, ang);
			}
		}
		if (d.acceleration != null) {
			final accel = d.acceleration.get(runningBarrage, this);
			if (d.relative) {
				runningBarrage.setBulletAcceleration(bullet, bullet.acceleration + accel);
			} else {
				runningBarrage.setBulletAcceleration(bullet, accel);
			}
		}
	}

	inline function vmPropertySetSpeedConst(runningBarrage:RunningBarrage, v:Float, relative:Bool):Void {
		final bullet = triggeringBullet;
		runningBarrage.setBulletSpeed(bullet, relative ? bullet.speed + v : v);
	}

	inline function vmPropertySetDirectionConst(runningBarrage:RunningBarrage, v:Float, relative:Bool):Void {
		final bullet = triggeringBullet;
		runningBarrage.setBulletAngle(bullet, relative ? bullet.angle + v : v);
	}

	inline function vmPropertySetAccelConst(runningBarrage:RunningBarrage, v:Float, relative:Bool):Void {
		final bullet = triggeringBullet;
		runningBarrage.setBulletAcceleration(bullet, relative ? bullet.acceleration + v : v);
	}

	inline function vmPropertyTween(runningBarrage:RunningBarrage, d:PropertyTweenDef, delta:Float):Void {
		var tweenTime:Float;
		if (d.scripted) {
			tweenTime = d.tweenTimeScript.eval(runningBarrage.scriptContext, enterSerial, cycleCount, runningBarrage.tickCount);
		} else {
			tweenTime = d.tweenTime;
		}
		if (d.durationType == DurationType.FRAMES) {
			tweenTime *= (1 / runningBarrage.owner.frameRate);
		}
		final bullet = triggeringBullet;
		if (d.speed != null) {
			var v = d.speed.get(runningBarrage, this);
			if (d.relative) v = bullet.speed + v;
			runningBarrage.retargetSpeed(bullet, v, tweenTime, delta);
		}
		if (d.direction != null) {
			var ang:Float = 0;
			if (d.direction.modifier.has(AIMED)) {
				final current = bullet.angle;
				ang = runningBarrage.getAngleToTarget(bullet.posX, bullet.posY, this, d.direction.target);
				while (ang - current > 180) ang -= 360;
				while (ang - current < -180) ang += 360;
			} else {
				ang = d.direction.get(runningBarrage, this);
			}
			if (d.relative) ang = bullet.angle + ang;
			runningBarrage.retargetAngle(bullet, ang, tweenTime, delta);
		}
		if (d.acceleration != null) {
			var accel = d.acceleration.get(runningBarrage, this);
			if (d.relative) accel = bullet.acceleration + accel;
			runningBarrage.retargetAcceleration(bullet, accel, tweenTime, delta);
		}
	}

	inline function vmPropertyTweenSpeedConst(runningBarrage:RunningBarrage, value:Float, tweenTime:Float, relative:Bool, delta:Float):Void {
		final bullet = triggeringBullet;
		var v = value;
		if (relative) v = bullet.speed + v;
		runningBarrage.retargetSpeed(bullet, v, tweenTime, delta);
	}

	inline function vmPropertyTweenDirectionConst(runningBarrage:RunningBarrage, value:Float, tweenTime:Float, relative:Bool, delta:Float):Void {
		final bullet = triggeringBullet;
		var ang = value;
		if (relative) ang = bullet.angle + ang;
		runningBarrage.retargetAngle(bullet, ang, tweenTime, delta);
	}

	inline function vmPropertyTweenAccelConst(runningBarrage:RunningBarrage, value:Float, tweenTime:Float, relative:Bool, delta:Float):Void {
		final bullet = triggeringBullet;
		var accel = value;
		if (relative) accel = bullet.acceleration + accel;
		runningBarrage.retargetAcceleration(bullet, accel, tweenTime, delta);
	}

	inline function vmAction(runningBarrage:RunningBarrage, d:ActionEventDef, delta:Float):Void {
		runningBarrage.runActionByID(this, d.actionID, triggeringBullet, null, delta);
	}

	inline function vmActionRef(runningBarrage:RunningBarrage, d:ActionReferenceEventDef, delta:Float):Void {
		runningBarrage.runActionByID(this, d.actionID, triggeringBullet, d.overrides, delta);
	}

	inline function vmDie(runningBarrage:RunningBarrage, d:DieEventDef):Void {
		runningBarrage.killBullet(triggeringBullet);
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

	public inline function enter(callingAction:RunningAction, barrage:RunningBarrage, ?overrides:Array<Property>) {
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

	inline function get_callingAction():RunningAction {
		return stateStore.callingAction[stateHandle];
	}

	inline function set_callingAction(value:RunningAction):RunningAction {
		return stateStore.callingAction[stateHandle] = value;
	}
}
