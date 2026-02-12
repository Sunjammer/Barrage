package tests;

import barrage.Barrage;
import barrage.data.ActionDef;
import barrage.data.EventDef.EventType;
import barrage.data.events.FireEventDef;
import barrage.data.events.WaitDef;
import barrage.parser.ParseError;
import barrage.instancing.IBarrageBullet;
import barrage.instancing.IBulletEmitter;
import barrage.instancing.RunningBarrage;
import barrage.instancing.SeededRng;
import barrage.data.properties.Property;
import barrage.data.properties.Property.PropertyModifier;
import haxe.EnumFlags;
import sys.io.File;

class TestMain {
	static function main():Void {
		var failures = 0;
		failures += run("parser evaluates constant math expressions", testConstMathParsing);
		failures += run("parser statement types are classified correctly", testStatementTypes);
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
			"examples/multitarget_demo.brg"
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
}

private class MockEmitter implements IBulletEmitter {
	public var posX:Float = 0;
	public var posY:Float = 0;
	public var emitCount:Int = 0;
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
