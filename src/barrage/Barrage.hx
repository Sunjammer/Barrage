package barrage;

import barrage.Barrage;
import barrage.data.ActionDef;
import barrage.data.BulletDef;
import barrage.data.targets.TargetSelector;
import barrage.instancing.IBulletEmitter;
import barrage.instancing.IRng;
import barrage.instancing.RunningBarrage;
import barrage.instancing.SeededRng;
import barrage.parser.Parser;
import hscript.Interp;

@:allow(barrage.parser.Parser)
class Barrage {
	static final cache = new Map<String, Barrage>();

	public var name:String;
	public var difficulty(get, set):Int;
	public var actions:Array<ActionDef>;
	public var start:ActionDef;
	public var bullets:Array<BulletDef>;
	public var defaultBullet:BulletDef;
	public var executor:Interp;
	public var frameRate:Int;
	public var targets:Map<String, TargetSelector>;

	public function new() {
		defaultBullet = new BulletDef("Default");
		defaultBullet.acceleration.set(0);
		defaultBullet.speed.set(50);
		frameRate = 60;
		executor = new Interp();
		executor.variables.set("math", Math);
		executor.variables.set("Math", Math);
		executor.variables.set("triangle", tri);
		executor.variables.set("square", sqr);
		difficulty = 1;
		actions = [];
		bullets = [];
		targets = new Map<String, TargetSelector>();
		targets.set("player", PLAYER);
	}

	static function tri(x:Float, a:Float = 0.5):Float {
		x = x / (2.0 * Math.PI);
		x = x % 1.0;
		if (x < 0.0)
			x = 1.0 + x;
		if (x < a)
			x = x / a;
		else
			x = 1.0 - (x - a) / (1.0 - a);
		return -1.0 + 2.0 * x;
	}

	static function sqr(x:Float, a:Float = 0.5):Float {
		if (Math.sin(x) > a)
			x = 1.0;
		else
			x = -1.0;
		return x;
	}

	inline function set_difficulty(i:Int):Int {
		executor.variables.set("difficulty", i);
		return i;
	}

	inline function get_difficulty():Int {
		return executor.variables.get("difficulty");
	}

	public function toString():String {
		return 'Barrage($name)';
	}

	public inline function run(emitter:IBulletEmitter, speedScale:Float = 1.0, accelScale:Float = 1.0, ?rng:IRng):RunningBarrage {
		// trace("Creating barrage runner");
		final activeRng = rng == null ? new SeededRng(0) : rng;
		executor.variables.set("rand", activeRng.nextFloat);
		final scriptMath = new ScriptMath(activeRng);
		executor.variables.set("math", scriptMath);
		executor.variables.set("Math", scriptMath);
		return new RunningBarrage(emitter, this, speedScale, accelScale, activeRng);
	}

	public static function clearCache():Void {
		cache.clear();
	}

	public static inline function fromString(str:String, useCache:Bool = true):Barrage {
		// trace("Creating barrage from string");
		if (useCache) {
			if (cache.exists(str))
				return cache.get(str);
			else {
				final b = Parser.parse(str);
				cache[str] = b;
				return b;
			}
		} else {
			return Parser.parse(str);
		}
	}
}

private class ScriptMath {
	public var PI(default, null):Float = Math.PI;
	public var E(default, null):Float = Math.exp(1);

	final rng:IRng;

	public function new(rng:IRng) {
		this.rng = rng;
	}

	public inline function random():Float {
		return rng.nextFloat();
	}

	public inline function sin(v:Float):Float {
		return Math.sin(v);
	}

	public inline function cos(v:Float):Float {
		return Math.cos(v);
	}

	public inline function tan(v:Float):Float {
		return Math.tan(v);
	}

	public inline function abs(v:Float):Float {
		return Math.abs(v);
	}

	public inline function sqrt(v:Float):Float {
		return Math.sqrt(v);
	}

	public inline function pow(v:Float, exp:Float):Float {
		return Math.pow(v, exp);
	}

	public inline function min(a:Float, b:Float):Float {
		return Math.min(a, b);
	}

	public inline function max(a:Float, b:Float):Float {
		return Math.max(a, b);
	}
}
