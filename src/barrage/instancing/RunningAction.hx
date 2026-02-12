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
import barrage.ir.Opcode;
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
	public var sleepTime:Float;
	public var currentBullet:IBarrageBullet;
	public var triggeringBullet:IBarrageBullet;
	public var prevAngle:Float;
	public var prevSpeed:Float;
	public var prevAccel:Float;
	public var prevPositionX:Float;
	public var prevPositionY:Float;
	public var actionTime:Float;
	public var prevDelta:Float;
	public var enterSerial:Int;

	var barrage:RunningBarrage;
	var useVmExecution:Bool;
	var compiledAction:Null<CompiledAction>;
	var vmUnrolled:Bool;
	var vmCycleInstructionCount:Int;
	var vmUnrolledCycles:Int;
	var repeatCount:Int;
	var endless:Bool;
	var completedCycles:Int;
	var eventsPerCycle:Int;
	var runEvents:Int;

	public var callingAction:RunningAction;
	public var properties:Array<Property>;

	public function new(runningBarrage:RunningBarrage, def:ActionDef, useVmExecution:Bool = false) {
		this.def = def;
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
				runningBarrage.scriptContext.setVar("actiontime", actionTime);
				runningBarrage.scriptContext.setVar("actionTime", actionTime);
				runningBarrage.scriptContext.setVar("repeatcount", completedCycles);
				runningBarrage.scriptContext.setVar("repeatCount", completedCycles);
				if (compiledAction != null) {
					var processedThisTick = 0;
					while (runEvents < eventsPerCycle) {
						final instr = compiledAction.instructions[runEvents++];
						runVmInstruction(runningBarrage, instr.opcode, instr.eventIndex, delta);
						processedThisTick++;
						if (instr.opcode == Opcode.WAIT) {
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

	inline function runVmInstruction(runningBarrage:RunningBarrage, opcode:Opcode, eventIndex:Int, delta:Float):Void {
		switch (opcode) {
			case WAIT:
				vmWait(runningBarrage, cast def.events[eventIndex]);
			case FIRE:
				vmFire(runningBarrage, cast def.events[eventIndex], delta);
			case PROPERTY_SET:
				vmPropertySet(runningBarrage, cast def.events[eventIndex]);
			case PROPERTY_TWEEN:
				vmPropertyTween(runningBarrage, cast def.events[eventIndex], delta);
			case ACTION:
				vmAction(runningBarrage, cast def.events[eventIndex], delta);
			case ACTION_REF:
				vmActionRef(runningBarrage, cast def.events[eventIndex], delta);
			case DIE:
				vmDie(runningBarrage, cast def.events[eventIndex]);
		}
	}

	inline function vmWait(runningBarrage:RunningBarrage, waitDef:WaitDef):Void {
		var wait:Float;
		if (waitDef.scripted) {
			wait = waitDef.waitTimeScript.eval(runningBarrage.owner.executor, runningBarrage.scriptContext, enterSerial, cycleCount, runningBarrage.tickCount);
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

	inline function vmPropertySet(runningBarrage:RunningBarrage, d:PropertySetDef):Void {
		final bullet = triggeringBullet;
		if (d.speed != null) {
			if (d.speed.modifier.has(RELATIVE)) {
				bullet.speed += d.speed.get(runningBarrage, this);
			} else {
				bullet.speed = d.speed.get(runningBarrage, this);
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
				bullet.angle += ang;
			} else {
				bullet.angle = ang;
			}
		}
		if (d.acceleration != null) {
			final accel = d.acceleration.get(runningBarrage, this);
			if (d.relative) {
				bullet.acceleration += accel;
			} else {
				bullet.acceleration = accel;
			}
		}
	}

	inline function vmPropertyTween(runningBarrage:RunningBarrage, d:PropertyTweenDef, delta:Float):Void {
		var tweenTime:Float;
		if (d.scripted) {
			tweenTime = d.tweenTimeScript.eval(runningBarrage.owner.executor, runningBarrage.scriptContext, enterSerial, cycleCount, runningBarrage.tickCount);
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
	}

	public var cycleCount(get, never):Int;

	inline function get_cycleCount():Int {
		return completedCycles;
	}
}
