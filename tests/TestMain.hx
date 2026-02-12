package tests;

import barrage.Barrage;
import barrage.data.ActionDef;
import barrage.data.EventDef.EventType;
import barrage.data.events.ActionReferenceEventDef;
import barrage.data.events.FireEventDef;
import barrage.data.events.PropertySetDef;
import barrage.data.events.PropertyTweenDef;
import barrage.data.events.WaitDef;
import barrage.data.properties.DurationType;
import barrage.ir.CompiledBarrage;
import barrage.parser.ParseError;
import barrage.data.targets.TargetSelector;
import barrage.instancing.IBarrageBullet;
import barrage.instancing.IBulletEmitter;
import barrage.instancing.RunningBarrage;
import barrage.instancing.SeededRng;
import barrage.data.properties.Property;
import barrage.data.properties.Property.PropertyModifier;
import haxe.Timer;
import haxe.EnumFlags;
import sys.io.File;

class TestMain {
	static function main():Void {
		var failures = 0;
		failures += run("parser evaluates constant math expressions", testConstMathParsing);
		failures += run("IR compile cache returns same object for same source", testCompileCache);
		failures += run("AOT bytes round-trip preserves runnable barrage", testCompiledBytesRoundTrip);
		failures += run("IR unrolls safe constant repeats", testIrRepeatUnroll);
		failures += run("IR preserves repeats when repeatCount is referenced", testIrRepeatNoUnrollWhenReferenced);
		failures += run("parser statement types are classified correctly", testStatementTypes);
		failures += run("parser grammar coverage", testGrammarCoverage);
		failures += run("parser rejects unsupported random direction clause", testUnsupportedRandomDirectionClause);
		failures += run("parser supports forward action references", testForwardActionReference);
		failures += run("parser rejects unknown action references", testUnknownActionReference);
		failures += run("parser rejects unknown bullet references", testUnknownBulletReference);
		failures += run("parser preserves identifier/script case", testScriptCasePreservation);
		failures += run("parser handles inline comments", testInlineComments);
		failures += run("runtime does not stop early when no bullets are active", testNoEarlyStopWithoutBullets);
		failures += run("action default repeat runs exactly once", testDefaultRepeatCount);
		failures += run("running barrage tolerates null onComplete", testNullOnCompleteCallback);
		failures += run("default rng is deterministic", testDefaultRngDeterministic);
		failures += run("seeded rng is deterministic by default injection", testDeterministicRngSameSeed);
		failures += run("different rng seeds produce different outcomes", testDeterministicRngDifferentSeeds);
		failures += run("scripted rand() is deterministic with seed", testScriptedRandDeterminism);
		failures += run("examples parse successfully", testExamplesParse);
		failures += run("examples start-event shapes are stable", testExampleStartEventShapes);
		failures += run("multitarget nearest bullet targeting updates direction", testNearestBulletTargeting);
		failures += run("dev example emits expected first incremental outcome", testDevExampleOutcome);
		failures += run("particle governor: bullet moves expected distance over script lifetime", testBulletMotionOverScriptLifetime);
		failures += run("particle governor: acceleration affects traveled distance", testBulletMotionWithAcceleration);
		failures += run("runtime profiling captures hot-path metrics", testRuntimeProfilingMetrics);
		failures += run("VM execution parity with legacy runtime", testVmParity);
		failures += run("VM parity across all shipped examples", testVmParityExamples);
		failures += run("benchmark VM vs legacy runtime", benchmarkVmVsLegacy);
		failures += run("benchmark stress profiles", benchmarkStressProfiles);

		if (failures == 0) {
			Sys.println("All tests passed.");
			Sys.exit(0);
		}

		Sys.println("Tests failed: " + failures);
		Sys.exit(1);
	}

	static function run(name:String, test:Void->Void):Int {
		try {
			test();
			Sys.println("PASS " + name);
			return 0;
		} catch (e:Dynamic) {
			Sys.println("FAIL " + name + " -> " + Std.string(e));
			return 1;
		}
	}

	static function testConstMathParsing():Void {
		final source = "barrage called parse_test\n\taction called start\n\t\twait (1+1) seconds\n";
		final barrage = Barrage.fromString(source, false);
		final waitDef:WaitDef = cast barrage.start.events[0];
		assertFalse(waitDef.scripted, "Expected constant expression to compile to a non-scripted wait.");
		assertFloatEquals(2, waitDef.waitTime, 1e-6, "Expected wait time to evaluate to 2.");
	}

	static function testDefaultRepeatCount():Void {
		final source =
			"barrage called repeat_test\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 10\n"
			+ "\taction called start\n"
			+ "\t\tfire source in absolute direction 0\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);

		running.start();
		assertIntEquals(1, emitter.emitCount, "Expected one bullet emission during initial action execution.");

		running.update(1 / 60);
		assertIntEquals(1, emitter.emitCount, "Action should not run a second cycle when repeat count is 1.");
	}

	static function testCompileCache():Void {
		final source = "barrage called compile_cache\n\taction called start\n\t\twait 1 frames\n";
		final a = Barrage.compileString(source, true);
		final b = Barrage.compileString(source, true);
		assertTrue(a == b, "Expected same compiled instance from source cache.");
	}

	static function testCompiledBytesRoundTrip():Void {
		final source =
			"barrage called aot_roundtrip\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 42\n"
			+ "\taction called start\n"
			+ "\t\tfire source in absolute direction 0\n";
		final bytes = Barrage.compileStringToBytes(source, false);
		final compiled = CompiledBarrage.fromBytes(bytes);
		final barrage = compiled.instantiate();
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		running.start();
		assertIntEquals(1, emitter.emitCount, "Expected one bullet from AOT-loaded barrage.");
		assertFloatEquals(42, emitter.speeds[0], 1e-6, "Expected emitted speed to match compiled source.");
	}

	static function testIrRepeatUnroll():Void {
		final source =
			"barrage called unroll_ok\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 10\n"
			+ "\taction called start\n"
			+ "\t\tfire source in absolute direction 0\n"
			+ "\t\tfire source in incremental direction 10\n"
			+ "\t\trepeat 5 times\n";
		final compiled = Barrage.compileString(source, false);
		final start = compiled.actions[compiled.startActionId];
		assertIntEquals(10, start.instructions.length, "Expected 2 instructions unrolled 5x.");
		assertIntEquals(1, start.repeatCountOverride, "Expected repeat override to 1 after unroll.");
	}

	static function testIrRepeatNoUnrollWhenReferenced():Void {
		final source =
			"barrage called unroll_blocked\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 10\n"
			+ "\taction called start\n"
			+ "\t\tfire source in absolute direction (repeatCount)\n"
			+ "\t\twait 1 frames\n"
			+ "\t\trepeat 5 times\n";
		final compiled = Barrage.compileString(source, false);
		final start = compiled.actions[compiled.startActionId];
		assertIntEquals(2, start.instructions.length, "Expected no unroll when repeatCount is referenced.");
		assertTrue(start.repeatCountOverride == null, "Expected no repeat override when unroll is blocked.");
	}

	static function testForwardActionReference():Void {
		final source =
			"barrage called fwd_ref\n"
			+ "\taction called start\n"
			+ "\t\tdo later\n"
			+ "\taction called later\n"
			+ "\t\twait 1 frames\n";
		final barrage = Barrage.fromString(source, false);
		assertIntEquals(1, barrage.start.events.length, "Expected one action-ref event.");
		assertEventType(EventType.ACTION_REF, barrage.start.events[0].type, "Forward action reference type");
	}

	static function testUnknownActionReference():Void {
		final source =
			"barrage called bad_ref\n"
			+ "\taction called start\n"
			+ "\t\tdo missing_action\n";
		assertParseError(source, "Unknown action reference");
	}

	static function testUnknownBulletReference():Void {
		final source =
			"barrage called bad_bullet\n"
			+ "\taction called start\n"
			+ "\t\tfire missing in aimed direction 0\n";
		assertParseError(source, "Unknown bullet reference");
	}

	static function testScriptCasePreservation():Void {
		final source =
			"barrage called case_test\n"
			+ "\taction called start\n"
			+ "\t\tMyValue is 2\n"
			+ "\t\twait (MyValue+1) frames\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		var completeCalls = 0;
		running.onComplete = function(_) {
			completeCalls++;
		};

		running.start();
		running.update(1 / 60);
		running.update(1 / 60);
		assertIntEquals(0, completeCalls, "Action should still be waiting after 2 frames.");
		running.update(1 / 60);
		running.update(1 / 60);
		running.update(1 / 60);
		assertIntEquals(1, completeCalls, "Action should complete shortly after 3 frames.");
	}

	static function testInlineComments():Void {
		final source =
			"barrage called comments\n"
			+ "\taction called start\n"
			+ "\t\twait 1 frames # inline comment\n";
		final barrage = Barrage.fromString(source, false);
		assertIntEquals(1, barrage.start.events.length, "Expected inline comment to be ignored.");
		assertEventType(EventType.WAIT, barrage.start.events[0].type, "Inline comment event type");
	}

	static function testNoEarlyStopWithoutBullets():Void {
		final source =
			"barrage called no_bullets\n"
			+ "\taction called start\n"
			+ "\t\twait 2 frames\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		var completeCalls = 0;
		running.onComplete = function(_) {
			completeCalls++;
		};

		running.start();
		running.update(1 / 60);
		assertIntEquals(0, completeCalls, "Barrage should remain active until wait completes.");
		running.update(1 / 60);
		running.update(1 / 60);
		assertIntEquals(1, completeCalls, "Barrage should complete when action finishes.");
	}

	static function testStatementTypes():Void {
		final source =
			"barrage called statement_test\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 5\n"
			+ "\taction called start\n"
			+ "\t\twait 2 frames\n"
			+ "\t\tset speed to 3\n"
			+ "\t\tset direction to aimed over 1 frames\n"
			+ "\t\tfire source in aimed direction 0\n"
			+ "\t\tdie\n";
		final barrage = Barrage.fromString(source, false);
		final events = barrage.start.events;

		assertIntEquals(5, events.length, "Expected exactly five events in start action.");
		assertEventType(EventType.WAIT, events[0].type, "Event 0");
		assertEventType(EventType.PROPERTY_SET, events[1].type, "Event 1");
		assertEventType(EventType.PROPERTY_TWEEN, events[2].type, "Event 2");
		assertEventType(EventType.FIRE, events[3].type, "Event 3");
		assertEventType(EventType.DIE, events[4].type, "Event 4");
	}

	static function testGrammarCoverage():Void {
		final source =
			"barrage called grammar_full\n"
			+ "\ttarget called p is player\n"
			+ "\ttarget called pa is parent\n"
			+ "\ttarget called me is self\n"
			+ "\ttarget called near_seed is nearest bullet where type is seed\n"
			+ "\tbullet called seed\n"
			+ "\t\tspeed is 10\n"
			+ "\t\tdirection is (45+45)\n"
			+ "\t\tacceleration is (rand()*2)\n"
			+ "\t\tdo action\n"
			+ "\t\t\twait 1 frames\n"
			+ "\t\t\tdie\n"
			+ "\tbullet called child\n"
			+ "\t\tspeed is (50 + rand()*5)\n"
			+ "\t\tdo action\n"
			+ "\t\t\tset direction to aimed at near_seed over 2 frames\n"
			+ "\t\t\tincrement speed by 5 over 1 seconds\n"
			+ "\t\t\tset acceleration to -1\n"
			+ "\t\t\twait (1+1) frames\n"
			+ "\t\t\tvanish\n"
			+ "\taction called helper\n"
			+ "\t\tmyoverride is 3\n"
			+ "\t\tfire child from relative position [1,2] at absolute speed (20+myoverride) in aimed at p direction (360/8*0.5) with incremental acceleration 1\n"
			+ "\t\tset direction to aimed at p\n"
			+ "\t\tincrement direction by aimed at pa over 3 frames\n"
			+ "\t\twait 1 seconds\n"
			+ "\t\trepeat 2 times\n"
			+ "\taction called start\n"
			+ "\t\tdo helper\n"
			+ "\t\t\tmyoverride is 7\n"
			+ "\t\tdo action\n"
			+ "\t\t\tfire seed in aimed at me direction 0\n"
			+ "\t\t\twait 1 frames\n"
			+ "\t\tfire seed in incremental direction 10\n"
			+ "\t\trepeat forever\n";

		final barrage = Barrage.fromString(source, false);
		assertTrue(barrage.start != null, "Expected start action.");

		assertTargetSelector(TargetSelector.PLAYER, barrage.targets.get("p"), "target p");
		assertTargetSelector(TargetSelector.PARENT, barrage.targets.get("pa"), "target pa");
		assertTargetSelector(TargetSelector.SELF, barrage.targets.get("me"), "target me");
		assertTargetSelector(TargetSelector.NEAREST_BULLET_TYPE("seed"), barrage.targets.get("near_seed"), "target near_seed");

		final helperId = findActionId(barrage, "helper");
		final helper = barrage.actions[helperId];
		assertIntEquals(4, helper.events.length, "Helper should contain fire, set, tween, wait events.");
		assertEventType(EventType.FIRE, helper.events[0].type, "helper event 0");
		assertEventType(EventType.PROPERTY_SET, helper.events[1].type, "helper event 1");
		assertEventType(EventType.PROPERTY_TWEEN, helper.events[2].type, "helper event 2");
		assertEventType(EventType.WAIT, helper.events[3].type, "helper event 3");
		assertIntEquals(2, Std.int(helper.repeatCount.constValue), "Helper repeat count should parse to 2.");

		final helperFire:FireEventDef = cast helper.events[0];
		assertTrue(helperFire.position.modifier.has(PropertyModifier.RELATIVE), "Helper fire position should be relative.");
		assertFloatEquals(1, helperFire.position.constValueVec[0], 1e-6, "Helper fire X position.");
		assertFloatEquals(2, helperFire.position.constValueVec[1], 1e-6, "Helper fire Y position.");
		assertTrue(helperFire.speed.scripted, "Helper fire speed should be scripted.");
		assertTrue(helperFire.direction.modifier.has(PropertyModifier.AIMED), "Helper fire direction should be aimed.");
		assertTargetSelector(TargetSelector.TARGET_ALIAS("p"), helperFire.direction.target, "helper fire direction target");
		assertFloatEquals(22.5, helperFire.direction.constValue, 1e-6, "Helper fire direction offset value.");
		assertTrue(helperFire.acceleration.modifier.has(PropertyModifier.INCREMENTAL), "Helper fire acceleration should be incremental.");
		assertFloatEquals(1, helperFire.acceleration.constValue, 1e-6, "Helper fire acceleration value.");

		final helperSet:PropertySetDef = cast helper.events[1];
		assertTrue(helperSet.direction.modifier.has(PropertyModifier.AIMED), "Helper set direction should be aimed.");
		assertTargetSelector(TargetSelector.TARGET_ALIAS("p"), helperSet.direction.target, "helper set direction target");

		final helperTween:PropertyTweenDef = cast helper.events[2];
		assertTrue(helperTween.relative, "Helper increment direction should be relative.");
		assertTrue(helperTween.direction.modifier.has(PropertyModifier.AIMED), "Helper tween direction should be aimed.");
		assertTargetSelector(TargetSelector.TARGET_ALIAS("pa"), helperTween.direction.target, "helper tween direction target");
		assertFloatEquals(3, helperTween.tweenTime, 1e-6, "Helper tween duration value.");
		assertTrue(helperTween.durationType == DurationType.FRAMES, "Helper tween duration type should be frames.");

		final helperWait:WaitDef = cast helper.events[3];
		assertFloatEquals(1, helperWait.waitTime, 1e-6, "Helper wait value.");
		assertTrue(helperWait.durationType == DurationType.SECONDS, "Helper wait duration type should be seconds.");

		final start = barrage.start;
		assertTrue(start.endless, "Start action should repeat forever.");
		assertIntEquals(3, start.events.length, "Start should have action_ref, action, fire.");
		assertEventType(EventType.ACTION_REF, start.events[0].type, "start event 0");
		assertEventType(EventType.ACTION, start.events[1].type, "start event 1");
		assertEventType(EventType.FIRE, start.events[2].type, "start event 2");

		final startActionRef:ActionReferenceEventDef = cast start.events[0];
		assertIntEquals(1, startActionRef.overrides.length, "Action ref should have one override.");
		assertStringEquals("myoverride", startActionRef.overrides[0].name, "Override property name.");
		assertFloatEquals(7, startActionRef.overrides[0].constValue, 1e-6, "Override property value.");
	}

	static function testUnsupportedRandomDirectionClause():Void {
		final source =
			"barrage called bad_random_clause\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 10\n"
			+ "\taction called start\n"
			+ "\t\tfire source in random direction 0\n";
		assertParseError(source, "Unrecognized line");
	}

	static function testNullOnCompleteCallback():Void {
		final source = "barrage called complete_test\n\taction called start\n\t\twait 1 frames\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);

		running.start();
		running.update(1 / 60);
	}

	static function testDeterministicRngSameSeed():Void {
		final first = collectRandomFireAngles(new SeededRng(12345));
		final second = collectRandomFireAngles(new SeededRng(12345));
		assertIntEquals(first.length, second.length, "Angle sample lengths should match.");
		for (i in 0...first.length) {
			assertFloatEquals(first[i], second[i], 1e-9, "Angle sequence should be identical for equal seeds.");
		}
	}

	static function testDeterministicRngDifferentSeeds():Void {
		final first = collectRandomFireAngles(new SeededRng(12345));
		final second = collectRandomFireAngles(new SeededRng(54321));
		assertIntEquals(first.length, second.length, "Angle sample lengths should match.");
		var allEqual = true;
		for (i in 0...first.length) {
			if (Math.abs(first[i] - second[i]) > 1e-9) {
				allEqual = false;
				break;
			}
		}
		assertFalse(allEqual, "Angle sequence should differ for different seeds.");
	}

	static function testDefaultRngDeterministic():Void {
		final first = collectRandomFireAngles();
		final second = collectRandomFireAngles();
		assertIntEquals(first.length, second.length, "Angle sample lengths should match.");
		for (i in 0...first.length) {
			assertFloatEquals(first[i], second[i], 1e-9, "Default RNG should produce deterministic sequence.");
		}
	}

	static function testScriptedRandDeterminism():Void {
		final first = collectScriptRandSpeeds(new SeededRng(7));
		final second = collectScriptRandSpeeds(new SeededRng(7));
		assertIntEquals(first.length, second.length, "Speed sample lengths should match.");
		for (i in 0...first.length) {
			assertFloatEquals(first[i], second[i], 1e-9, "Script rand sequence should be deterministic with same seed.");
		}
	}

	static function testExamplesParse():Void {
		final files = [
			"examples/waveburst.brg",
			"examples/swarm.brg",
			"examples/inchworm.brg",
			"examples/dev.brg",
			"examples/multitarget_demo.brg",
			"examples/exhaustive_stress.brg"
		];
		for (path in files) {
			final source = File.getContent(path);
			final barrage = Barrage.fromString(source, false);
			assertTrue(barrage.start != null, "Expected start action in " + path);
		}
	}

	static function testExampleStartEventShapes():Void {
		assertStartEventTypes("examples/waveburst.brg", [EventType.FIRE]);
		assertStartEventTypes("examples/swarm.brg", [EventType.FIRE, EventType.ACTION]);
		assertStartEventTypes("examples/inchworm.brg", [EventType.ACTION_REF, EventType.WAIT]);
		assertStartEventTypes("examples/dev.brg", [EventType.FIRE, EventType.ACTION]);
		assertStartEventTypes("examples/multitarget_demo.brg", [EventType.FIRE, EventType.ACTION, EventType.WAIT, EventType.FIRE, EventType.ACTION]);
		assertStartEventTypes("examples/exhaustive_stress.brg", [EventType.ACTION_REF, EventType.WAIT]);
	}

	static function testNearestBulletTargeting():Void {
		final source =
			"barrage called nearest_target\n"
			+ "\ttarget called nearest_seed is nearest bullet where type is seed\n"
			+ "\tbullet called seed\n"
			+ "\t\tspeed is 0\n"
			+ "\tbullet called hunter\n"
			+ "\t\tspeed is 0\n"
			+ "\t\tdo action\n"
			+ "\t\t\tset direction to aimed at nearest_seed over 1 frames\n"
			+ "\taction called start\n"
			+ "\t\tfire seed from relative position [100,0] in absolute direction 0\n"
			+ "\t\tfire hunter from relative position [0,0] in absolute direction 90\n"
			+ "\t\twait 1 frames\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		running.start();
		running.update(1 / 60);

		assertIntEquals(2, emitter.emitCount, "Expected seed and hunter bullets.");
		final hunter = emitter.emitted[1];
		assertFloatEquals(0, hunter.angle, 0.001, "Hunter should retarget toward nearest seed at +X.");
	}

	static function testDevExampleOutcome():Void {
		final barrage = Barrage.fromString(File.getContent("examples/dev.brg"), false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		running.start();

		assertIntEquals(1, emitter.emitCount, "Expected immediate first emit in dev example.");
		assertFloatEquals(10, emitter.xs[0], 1e-6, "First emitted bullet X should be relative +10.");
		assertFloatEquals(0, emitter.ys[0], 1e-6, "First emitted bullet Y should be unchanged.");
		assertFloatEquals(100, emitter.accelerations[0], 1e-6, "First emitted bullet acceleration should be absolute 100.");

		running.update(0.1);
		assertIntEquals(2, emitter.emitCount, "Expected second emit after wait 0.1s.");
		assertFloatEquals(20, emitter.xs[1], 1e-6, "Second emitted bullet X should be incremental +10 from previous.");
		assertFloatEquals(0, emitter.ys[1], 1e-6, "Second emitted bullet Y should remain unchanged.");
		assertFloatEquals(50, emitter.accelerations[1], 1e-6, "Second emitted bullet acceleration should be incremental -50 from previous 100.");
	}

	static function testBulletMotionOverScriptLifetime():Void {
		final source =
			"barrage called motion\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 100\n"
			+ "\taction called start\n"
			+ "\t\tfire source in absolute direction 0\n"
			+ "\t\twait 1 seconds\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		running.start();

		simulate(running, emitter, 1 / 60, 60);
		final bullet = emitter.emitted[0];
		assertFloatEquals(100, bullet.posX, 0.5, "Bullet should travel ~100 units in 1 second at speed 100.");
		assertFloatEquals(0, bullet.posY, 0.01, "Bullet Y should remain near 0 at direction 0.");
	}

	static function testBulletMotionWithAcceleration():Void {
		final source =
			"barrage called accel_motion\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 0\n"
			+ "\taction called start\n"
			+ "\t\tfire source in absolute direction 0 with absolute acceleration 10\n"
			+ "\t\twait 2 seconds\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		running.start();

		simulate(running, emitter, 1 / 60, 120);
		final bullet = emitter.emitted[0];
		// Semi-implicit Euler in MockEmitter.update should land close to 20 units.
		assertFloatEquals(20, bullet.posX, 0.5, "Bullet should travel ~20 units in 2 seconds under +10 accel.");
	}

	static function testRuntimeProfilingMetrics():Void {
		final source =
			"barrage called profile_metrics\n"
			+ "\ttarget called near_worker is nearest bullet where type is worker\n"
			+ "\tbullet called worker\n"
			+ "\t\tspeed is (difficulty > 0 ? 100 : 50)\n"
			+ "\t\tdo action\n"
			+ "\t\t\tset direction to aimed at near_worker over 1 frames\n"
			+ "\t\t\twait 1 frames\n"
			+ "\t\t\trepeat 4 times\n"
			+ "\taction called start\n"
			+ "\t\tfire worker in absolute direction (rand()*360)\n"
			+ "\t\tdo action\n"
			+ "\t\t\twait 1 frames\n"
			+ "\t\t\tfire worker in absolute direction (rand()*360)\n"
			+ "\t\t\trepeat 6 times\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter);
		running.profilingEnabled = true;
		running.start();
		simulate(running, emitter, 1 / 60, 90);

		assertTrue(running.profile.updateTicks > 0, "Expected profiled update tick count > 0.");
		assertTrue(running.profile.actionSeconds >= 0, "Expected actionSeconds metric to be valid.");
		assertTrue(running.profile.cleanupSeconds >= 0, "Expected cleanupSeconds metric to be valid.");
		assertTrue(running.profile.scriptEvalSeconds >= 0, "Expected scriptEvalSeconds metric to be valid.");
		assertTrue(running.profile.nativeScriptEvals > 0, "Expected native script eval count > 0.");
		assertTrue(running.profile.fallbackScriptEvals > 0, "Expected fallback script eval count > 0.");
		assertTrue(running.profile.targetQueries > 0, "Expected target queries count > 0.");
		assertTrue(running.profile.bulletsSpawned > 0, "Expected spawned bullet count > 0.");
		assertTrue(running.profile.peakActiveBullets > 0, "Expected peak active bullets > 0.");
	}

	static function testVmParity():Void {
		final source =
			"barrage called vm_parity\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 120\n"
			+ "\t\tdo action\n"
			+ "\t\t\twait 10 frames\n"
			+ "\t\t\tdie\n"
			+ "\taction called start\n"
			+ "\t\tfire source in aimed direction 0\n"
			+ "\t\tdo action\n"
			+ "\t\t\twait 2 frames\n"
			+ "\t\t\tfire source in incremental direction 15\n"
			+ "\t\t\trepeat 8 times\n";

		final legacy = runSimulation(source, false, 180);
		final vm = runSimulation(source, true, 180);
		assertIntEquals(legacy.emitCount, vm.emitCount, "VM and legacy emit count should match.");
		assertIntEquals(legacy.killCount, vm.killCount, "VM and legacy kill count should match.");
		assertStringEquals(simulationDigest(legacy), simulationDigest(vm), "VM and legacy simulation digest should match.");
	}

	static function testVmParityExamples():Void {
		final files = [
			"examples/waveburst.brg",
			"examples/swarm.brg",
			"examples/inchworm.brg",
			"examples/multitarget_demo.brg",
			"examples/dev.brg",
			"examples/exhaustive_stress.brg"
		];
		for (path in files) {
			final source = File.getContent(path);
			final legacy = runSimulation(source, false, 600);
			final vm = runSimulation(source, true, 600);
			assertStringEquals(simulationDigest(legacy), simulationDigest(vm), "Parity mismatch for " + path);
		}
	}

	static function benchmarkVmVsLegacy():Void {
		final source = File.getContent("examples/exhaustive_stress.brg");

		final iterations = 30;
		final legacyTime = benchmark(source, false, iterations, 720);
		final vmTime = benchmark(source, true, iterations, 720);
		Sys.println('BENCH legacy=${legacyTime}s vm=${vmTime}s iterations=${iterations}');
		assertTrue(legacyTime > 0 && vmTime > 0, "Benchmark timings must be positive.");
		// Guardrail only: VM should be in same order of magnitude while we iterate.
		assertTrue(vmTime < legacyTime * 5.0, "VM path is unexpectedly slower than legacy.");
	}

	static function benchmarkStressProfiles():Void {
		final profiles = [
			{
				name: "exhaustive_stress_file",
				source: File.getContent("examples/exhaustive_stress.brg"),
				iterations: 20,
				steps: 720,
				maxSlowdown: 5.0
			},
			{
				name: "spawn_storm_dense",
				source: buildSpawnStormProfileSource(),
				iterations: 40,
				steps: 360,
				maxSlowdown: 5.0
			},
			{
				name: "scripted_churn",
				source: buildScriptedChurnProfileSource(),
				iterations: 30,
				steps: 480,
				maxSlowdown: 5.0
			}
		];

		for (p in profiles) {
			final legacyTime = benchmark(p.source, false, p.iterations, p.steps);
			final vmTime = benchmark(p.source, true, p.iterations, p.steps);
			final ratio = vmTime / legacyTime;
			Sys.println('PROFILE ${p.name} legacy=${legacyTime}s vm=${vmTime}s ratio=${ratio} iterations=${p.iterations} steps=${p.steps}');
			assertTrue(legacyTime > 0 && vmTime > 0, "Profile benchmark timings must be positive for " + p.name);
			assertTrue(ratio < p.maxSlowdown, "VM slowdown too high for " + p.name + " (ratio=" + ratio + ")");
		}
	}

	static function buildSpawnStormProfileSource():String {
		return "barrage called spawn_storm_dense\n"
			+ "\tbullet called pellet\n"
			+ "\t\tspeed is 280\n"
			+ "\taction called ring\n"
			+ "\t\tfire pellet in absolute direction 0\n"
			+ "\t\tdo action\n"
			+ "\t\t\tfire pellet in incremental direction (360/24)\n"
			+ "\t\t\trepeat 23 times\n"
			+ "\t\trepeat 5 times\n"
			+ "\taction called start\n"
			+ "\t\tdo ring\n"
			+ "\t\twait 1 frames\n"
			+ "\t\trepeat 12 times\n";
	}

	static function buildScriptedChurnProfileSource():String {
		return "barrage called scripted_churn\n"
			+ "\tbullet called worker\n"
			+ "\t\tspeed is (120 + rand()*60)\n"
			+ "\t\tdirection is (rand()*360)\n"
			+ "\t\tdo action\n"
			+ "\t\t\tset direction to aimed over 1 frames\n"
			+ "\t\t\tincrement speed by (5 + rand()*5) over 1 frames\n"
			+ "\t\t\tset acceleration to (-20 + rand()*40) over 1 frames\n"
			+ "\t\t\twait 1 frames\n"
			+ "\t\t\trepeat forever\n"
			+ "\taction called start\n"
			+ "\t\tfire worker in absolute direction (rand()*360)\n"
			+ "\t\tdo action\n"
			+ "\t\t\twait 2 frames\n"
			+ "\t\t\tfire worker in absolute direction (rand()*360 + repeatCount*3)\n"
			+ "\t\t\trepeat 80 times\n";
	}

	static function collectRandomFireAngles(?rng:SeededRng):Array<Float> {
		final barrage = new Barrage();
		final action = new ActionDef("start");
		final fire = new FireEventDef();
		final direction = new Property("Direction");
		direction.modifier = new EnumFlags<PropertyModifier>();
		direction.modifier.set(PropertyModifier.RANDOM);
		fire.direction = direction;
		action.events.push(fire);
		action.repeatCount.constValue = 3;
		barrage.start = action;
		barrage.actions.push(action);

		final emitter = new MockEmitter();
		final running = rng == null ? barrage.run(emitter) : barrage.run(emitter, 1.0, 1.0, rng);
		running.start();
		running.update(1 / 60);
		running.update(1 / 60);
		return emitter.angles;
	}

	static function collectScriptRandSpeeds(rng:SeededRng):Array<Float> {
		final source =
			"barrage called scripted_rng\n"
			+ "\tbullet called source\n"
			+ "\t\tspeed is 10\n"
			+ "\taction called start\n"
			+ "\t\tfire source at absolute speed (50 + rand()*20) in aimed direction 0\n"
			+ "\t\trepeat 3 times\n";
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = barrage.run(emitter, 1.0, 1.0, rng);
		running.start();
		running.update(1 / 60);
		running.update(1 / 60);
		return emitter.speeds;
	}

	static function assertFalse(value:Bool, message:String):Void {
		if (value) {
			throw message;
		}
	}

	static function assertTrue(value:Bool, message:String):Void {
		if (!value) {
			throw message;
		}
	}

	static function assertParseError(source:String, expectedText:String):Void {
		try {
			Barrage.fromString(source, false);
			throw "Expected parse error containing: " + expectedText;
		} catch (e:Dynamic) {
			final parseError:ParseError = Std.isOfType(e, ParseError) ? cast e : null;
			final msg = parseError == null ? Std.string(e) : parseError.info;
			if (msg.indexOf(expectedText) == -1) {
				throw 'Expected parse error containing "' + expectedText + '", actual: ' + msg;
			}
		}
	}

	static function assertIntEquals(expected:Int, actual:Int, message:String):Void {
		if (expected != actual) {
			throw message + " Expected: " + expected + ", actual: " + actual;
		}
	}

	static function assertFloatEquals(expected:Float, actual:Float, epsilon:Float, message:String):Void {
		if (Math.abs(expected - actual) > epsilon) {
			throw message + " Expected: " + expected + ", actual: " + actual;
		}
	}

	static function assertEventType(expected:EventType, actual:EventType, label:String):Void {
		if (expected != actual) {
			throw label + " Expected: " + expected + ", actual: " + actual;
		}
	}

	static function assertStringEquals(expected:String, actual:String, message:String):Void {
		if (expected != actual) {
			throw message + " Expected: " + expected + ", actual: " + actual;
		}
	}

	static function assertTargetSelector(expected:TargetSelector, actual:TargetSelector, message:String):Void {
		final expectedText = Std.string(expected);
		final actualText = Std.string(actual);
		if (expectedText != actualText) {
			throw message + " Expected: " + expectedText + ", actual: " + actualText;
		}
	}

	static function findActionId(barrage:Barrage, name:String):Int {
		for (action in barrage.actions) {
			if (action != null && action.name == name) {
				return action.id;
			}
		}
		throw "Could not find action by name: " + name;
	}

	static function assertStartEventTypes(path:String, expected:Array<EventType>):Void {
		final barrage = Barrage.fromString(File.getContent(path), false);
		final events = barrage.start.events;
		assertIntEquals(expected.length, events.length, "Unexpected start event count for " + path);
		for (i in 0...expected.length) {
			assertEventType(expected[i], events[i].type, path + " event " + i);
		}
	}

	static function simulate(running:RunningBarrage, emitter:MockEmitter, dt:Float, steps:Int):Void {
		for (_ in 0...steps) {
			running.update(dt);
			emitter.update(dt);
		}
	}

	static function runSimulation(source:String, useVm:Bool, steps:Int):MockEmitter {
		final barrage = Barrage.fromString(source, false);
		final emitter = new MockEmitter();
		final running = useVm ? barrage.runVm(emitter) : barrage.run(emitter);
		running.start();
		simulate(running, emitter, 1 / 60, steps);
		return emitter;
	}

	static function simulationDigest(emitter:MockEmitter):String {
		final out = new Array<String>();
		out.push("emit=" + emitter.emitCount);
		out.push("kill=" + emitter.killCount);
		out.push("active=" + emitter.activeCount());
		final n = emitter.emitted.length;
		out.push("spawned=" + n);
		for (i in 0...n) {
			final b = emitter.emitted[i];
			out.push(i
				+ ":id=" + b.id
				+ ",x=" + fmt(b.posX)
				+ ",y=" + fmt(b.posY)
				+ ",a=" + fmt(b.angle)
				+ ",s=" + fmt(b.speed)
				+ ",acc=" + fmt(b.acceleration)
				+ ",on=" + (b.active ? "1" : "0"));
		}
		return out.join("|");
	}

	static inline function fmt(v:Float):String {
		return Std.string(Math.fround(v * 10000) / 10000);
	}

	static function benchmark(source:String, useVm:Bool, iterations:Int, steps:Int):Float {
		final start = Timer.stamp();
		for (_ in 0...iterations) {
			runSimulation(source, useVm, steps);
		}
		return Timer.stamp() - start;
	}
}

private class MockEmitter implements IBulletEmitter {
	public var posX:Float = 0;
	public var posY:Float = 0;
	public var emitCount:Int = 0;
	public var killCount:Int = 0;
	public var angles:Array<Float> = [];
	public var speeds:Array<Float> = [];
	public var accelerations:Array<Float> = [];
	public var xs:Array<Float> = [];
	public var ys:Array<Float> = [];
	public var emitted:Array<MockBullet> = [];

	var nextBulletId:Int = 1;

	public function new() {}

	public function emit(x:Float, y:Float, angleRad:Float, speed:Float, acceleration:Float, delta:Float):IBarrageBullet {
		emitCount++;
		angles.push(angleRad);
		speeds.push(speed);
		accelerations.push(acceleration);
		xs.push(x);
		ys.push(y);
		final bullet = new MockBullet(nextBulletId++, x, y, angleRad, speed, acceleration);
		emitted.push(bullet);
		return bullet;
	}

	public function getAngleToEmitter(posX:Float, posY:Float):Float {
		return 0;
	}

	public function getAngleToPlayer(posX:Float, posY:Float):Float {
		return 0;
	}

	public function kill(bullet:IBarrageBullet):Void {
		killCount++;
		bullet.active = false;
	}

	public function update(delta:Float):Void {
		for (bullet in emitted) {
			if (!bullet.active)
				continue;
			bullet.speed += bullet.acceleration * delta;
			final angleRad = bullet.angle * Math.PI / 180;
			bullet.velocityX = Math.cos(angleRad) * bullet.speed;
			bullet.velocityY = Math.sin(angleRad) * bullet.speed;
			bullet.posX += bullet.velocityX * delta;
			bullet.posY += bullet.velocityY * delta;
		}
	}

	public function activeCount():Int {
		var count = 0;
		for (bullet in emitted) {
			if (bullet.active)
				count++;
		}
		return count;
	}
}

private class MockBullet implements IBarrageBullet {
	public var id:Int;
	public var posX:Float;
	public var posY:Float;
	public var acceleration:Float;
	public var velocityX:Float = 0;
	public var velocityY:Float = 0;
	public var angle:Float;
	public var speed:Float;
	public var active:Bool = true;

	public function new(id:Int, posX:Float, posY:Float, angle:Float, speed:Float, acceleration:Float) {
		this.id = id;
		this.posX = posX;
		this.posY = posY;
		this.angle = angle;
		this.speed = speed;
		this.acceleration = acceleration;
	}
}
