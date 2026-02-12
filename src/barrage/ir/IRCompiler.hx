package barrage.ir;

import barrage.Barrage;
import barrage.data.ActionDef;
import barrage.data.EventDef.EventType;
import barrage.data.events.FireEventDef;
import barrage.data.events.PropertySetDef;
import barrage.data.events.PropertyTweenDef;
import barrage.data.events.WaitDef;
import barrage.data.properties.Property;
import barrage.data.properties.DurationType;
import barrage.script.ScriptValue;

class IRCompiler {
	static final MAX_UNROLL = 64;

	public static function compile(barrage:Barrage, ?source:String):CompiledBarrage {
		final actions = new Array<CompiledAction>();
		for (action in barrage.actions) {
			if (action == null) {
				actions.push(null);
				continue;
			}
			optimizeAction(action);
			final baseInstructions = new Array<Instruction>();
			for (i in 0...action.events.length) {
				baseInstructions.push(compileInstruction(action.events[i].type, action.events[i], i, barrage.frameRate));
			}

			var instructions = baseInstructions;
			var repeatOverride:Null<Int> = null;
			var cycleInstructionCount = baseInstructions.length;
			var unrolledCycles = 1;
			final unrollCount = getConstantRepeatCount(action);
			if (canUnroll(action, unrollCount)) {
				instructions = new Array<Instruction>();
				for (_ in 0...unrollCount) {
					for (instr in baseInstructions) {
						instructions.push(new Instruction(instr.opcode, instr.eventIndex, instr.immF0, instr.immF1, instr.immI0));
					}
				}
				repeatOverride = 1;
				cycleInstructionCount = baseInstructions.length;
				unrolledCycles = unrollCount;
			}

			actions[action.id] = new CompiledAction(action, instructions, repeatOverride, cycleInstructionCount, unrolledCycles);
		}

		return new CompiledBarrage(
			barrage.name,
			barrage.frameRate,
			barrage.difficulty,
			barrage.start.id,
			actions,
			barrage.bullets,
			barrage.defaultBullet,
			barrage.targets,
			source
		);
	}

	static function optimizeAction(action:ActionDef):Void {
		foldPropertyConstant(action.repeatCount);
		for (event in action.events) {
			switch (event.type) {
				case EventType.WAIT:
					final d:WaitDef = cast event;
					if (d.scripted && isConstantScript(d.waitTimeScript)) {
						d.waitTime = evalConstantScript(d.waitTimeScript);
						d.scripted = false;
						d.waitTimeScript = null;
					}
				case EventType.PROPERTY_SET:
					final d:PropertySetDef = cast event;
					foldPropertySet(d);
				case EventType.PROPERTY_TWEEN:
					final d:PropertyTweenDef = cast event;
					foldPropertySet(d);
					if (d.scripted && isConstantScript(d.tweenTimeScript)) {
						d.tweenTime = evalConstantScript(d.tweenTimeScript);
						d.scripted = false;
						d.tweenTimeScript = null;
					}
				case EventType.FIRE:
					final d:FireEventDef = cast event;
					foldPropertyConstant(d.speed);
					foldPropertyConstant(d.acceleration);
					foldPropertyConstant(d.direction);
					foldPropertyConstant(d.position);
				case EventType.ACTION | EventType.ACTION_REF | EventType.DIE:
			}
		}
	}

	static function foldPropertySet(d:PropertySetDef):Void {
		foldPropertyConstant(d.speed);
		foldPropertyConstant(d.direction);
		foldPropertyConstant(d.acceleration);
		foldPropertyConstant(d.position);
	}

	static function foldPropertyConstant(p:Property):Void {
		if (p == null || !p.scripted || p.script == null)
			return;
		if (!isConstantScript(p.script))
			return;
		final v = evalConstantScript(p.script);
		p.constValue = v;
		p.scripted = false;
		p.script = null;
	}

	static inline function isConstantScript(s:ScriptValue):Bool {
		return s != null && s.nativeExpr != null && s.nativeExpr.isConstant();
	}

	static inline function evalConstantScript(s:ScriptValue):Float {
		return s.nativeExpr.evalConstant();
	}

	static function getConstantRepeatCount(action:ActionDef):Int {
		if (action.endless)
			return -1;
		if (action.repeatCount.scripted && isConstantScript(action.repeatCount.script)) {
			action.repeatCount.constValue = evalConstantScript(action.repeatCount.script);
			action.repeatCount.scripted = false;
			action.repeatCount.script = null;
		}
		if (action.repeatCount.scripted)
			return -1;
		return Std.int(action.repeatCount.constValue);
	}

	static function canUnroll(action:ActionDef, count:Int):Bool {
		if (count <= 1 || count > MAX_UNROLL)
			return false;
		if (action.endless)
			return false;
		if (action.events.length == 0)
			return false;
		if (hasUnsafeEventsForUnroll(action))
			return false;
		return !actionUsesRepeatCount(action);
	}

	static function hasUnsafeEventsForUnroll(action:ActionDef):Bool {
		for (event in action.events) {
			switch (event.type) {
				case EventType.WAIT | EventType.ACTION | EventType.ACTION_REF | EventType.PROPERTY_TWEEN:
					return true;
				case EventType.FIRE | EventType.PROPERTY_SET | EventType.DIE:
			}
		}
		return false;
	}

	static function actionUsesRepeatCount(action:ActionDef):Bool {
		final needle = "repeatcount";
		if (hasRepeatCount(action.repeatCount.script, needle))
			return true;
		for (event in action.events) {
			switch (event.type) {
				case EventType.WAIT:
					final d:WaitDef = cast event;
					if (hasRepeatCount(d.waitTimeScript, needle)) return true;
				case EventType.PROPERTY_SET:
					final d:PropertySetDef = cast event;
					if (propertyUsesRepeatCount(d.speed, needle) || propertyUsesRepeatCount(d.direction, needle) || propertyUsesRepeatCount(d.acceleration, needle)
						|| propertyUsesRepeatCount(d.position, needle))
						return true;
				case EventType.PROPERTY_TWEEN:
					final d:PropertyTweenDef = cast event;
					if (hasRepeatCount(d.tweenTimeScript, needle) || propertyUsesRepeatCount(d.speed, needle) || propertyUsesRepeatCount(d.direction, needle)
						|| propertyUsesRepeatCount(d.acceleration, needle) || propertyUsesRepeatCount(d.position, needle))
						return true;
				case EventType.FIRE:
					final d:FireEventDef = cast event;
					if (propertyUsesRepeatCount(d.speed, needle) || propertyUsesRepeatCount(d.acceleration, needle) || propertyUsesRepeatCount(d.direction, needle)
						|| propertyUsesRepeatCount(d.position, needle))
						return true;
				case EventType.ACTION | EventType.ACTION_REF | EventType.DIE:
			}
		}
		return false;
	}

	static inline function propertyUsesRepeatCount(p:Property, needle:String):Bool {
		return p != null && p.scripted && hasRepeatCount(p.script, needle);
	}

	static inline function hasRepeatCount(s:ScriptValue, needle:String):Bool {
		return s != null && s.source != null && s.source.toLowerCase().indexOf(needle) >= 0;
	}

	static function compileInstruction(eventType:EventType, event:Dynamic, eventIndex:Int, frameRate:Int):Instruction {
		return switch (eventType) {
			case WAIT:
				final d:WaitDef = cast event;
				if (!d.scripted) {
					switch (d.durationType) {
						case SECONDS:
							new Instruction(WAIT_SECONDS_CONST, eventIndex, d.waitTime);
						case FRAMES:
							new Instruction(WAIT_FRAMES_CONST, eventIndex, d.waitTime * (1 / frameRate));
					}
				} else {
					new Instruction(WAIT, eventIndex);
				}
			case FIRE:
				final d:FireEventDef = cast event;
				if (canUseConstFire(d)) new Instruction(FIRE_CONST, eventIndex) else new Instruction(FIRE, eventIndex);
			case PROPERTY_SET:
				final d:PropertySetDef = cast event;
				if (d.speed != null && !d.speed.scripted) {
					new Instruction(PROPERTY_SET_SPEED_CONST, eventIndex, d.speed.constValue, 0.0, d.speed.modifier.has(RELATIVE) ? 1 : 0);
				} else if (d.direction != null && !d.direction.scripted && !d.direction.modifier.has(AIMED)) {
					new Instruction(PROPERTY_SET_DIRECTION_CONST, eventIndex, d.direction.constValue, 0.0, d.relative ? 1 : 0);
				} else if (d.acceleration != null && !d.acceleration.scripted) {
					new Instruction(PROPERTY_SET_ACCEL_CONST, eventIndex, d.acceleration.constValue, 0.0, d.relative ? 1 : 0);
				} else {
					new Instruction(PROPERTY_SET, eventIndex);
				}
			case PROPERTY_TWEEN:
				final d:PropertyTweenDef = cast event;
				if (!d.scripted) {
					final tweenSeconds = d.durationType == FRAMES ? d.tweenTime * (1 / frameRate) : d.tweenTime;
					if (d.speed != null && !d.speed.scripted) {
						new Instruction(PROPERTY_TWEEN_SPEED_CONST, eventIndex, d.speed.constValue, tweenSeconds, d.relative ? 1 : 0);
					} else if (d.direction != null && !d.direction.scripted && !d.direction.modifier.has(AIMED)) {
						new Instruction(PROPERTY_TWEEN_DIRECTION_CONST, eventIndex, d.direction.constValue, tweenSeconds, d.relative ? 1 : 0);
					} else if (d.acceleration != null && !d.acceleration.scripted) {
						new Instruction(PROPERTY_TWEEN_ACCEL_CONST, eventIndex, d.acceleration.constValue, tweenSeconds, d.relative ? 1 : 0);
					} else {
						new Instruction(PROPERTY_TWEEN, eventIndex);
					}
				} else {
					new Instruction(PROPERTY_TWEEN, eventIndex);
				}
			case ACTION:
				new Instruction(ACTION, eventIndex);
			case ACTION_REF:
				new Instruction(ACTION_REF, eventIndex);
			case DIE:
				new Instruction(DIE, eventIndex);
		}
	}

	static inline function canUseConstFire(d:FireEventDef):Bool {
		if (d == null) return false;
		if (d.speed != null && d.speed.scripted) return false;
		if (d.acceleration != null && d.acceleration.scripted) return false;
		if (d.direction != null && d.direction.scripted) return false;
		if (d.position != null && (d.position.scripted || d.position.vectorScripted)) return false;
		return true;
	}
}
