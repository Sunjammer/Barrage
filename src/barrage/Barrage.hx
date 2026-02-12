package barrage;

import barrage.Barrage;
import barrage.data.ActionDef;
import barrage.data.BulletDef;
import barrage.data.targets.TargetSelector;
import barrage.ir.CompiledBarrage;
import barrage.ir.IRCompiler;
import barrage.instancing.IBulletEmitter;
import barrage.instancing.IRng;
import barrage.instancing.RunningBarrage;
import barrage.instancing.SeededRng;
import barrage.parser.Parser;

@:allow(barrage.parser.Parser)
class Barrage {
	static final cache = new Map<String, Barrage>();
	static final compiledCache = new Map<String, CompiledBarrage>();

	public var name:String;
	public var difficulty(get, set):Int;
	public var actions:Array<ActionDef>;
	public var start:ActionDef;
	public var bullets:Array<BulletDef>;
	public var defaultBullet:BulletDef;
	public var frameRate:Int;
	public var targets:Map<String, TargetSelector>;
	var _difficulty:Int = 1;
	var compiled:Null<CompiledBarrage>;

	public function new() {
		defaultBullet = new BulletDef("Default");
		defaultBullet.acceleration.set(0);
		defaultBullet.speed.set(50);
		frameRate = 60;
		difficulty = 1;
		actions = [];
		bullets = [];
		targets = new Map<String, TargetSelector>();
		targets.set("player", PLAYER);
	}

	inline function set_difficulty(i:Int):Int {
		_difficulty = i;
		return _difficulty;
	}

	inline function get_difficulty():Int {
		return _difficulty;
	}

	public function toString():String {
		return 'Barrage($name)';
	}

	public inline function run(emitter:IBulletEmitter, speedScale:Float = 1.0, accelScale:Float = 1.0, ?rng:IRng):RunningBarrage {
		// trace("Creating barrage runner");
		final activeRng = rng == null ? new SeededRng(0) : rng;
		// run() always defaults to VM execution.
		return new RunningBarrage(emitter, this, speedScale, accelScale, activeRng, false);
	}

	public inline function runVm(emitter:IBulletEmitter, speedScale:Float = 1.0, accelScale:Float = 1.0, ?rng:IRng,
			strictNativeExpressions:Bool = true):RunningBarrage {
		final activeRng = rng == null ? new SeededRng(0) : rng;
		return new RunningBarrage(emitter, this, speedScale, accelScale, activeRng, strictNativeExpressions);
	}

	public static function clearCache():Void {
		cache.clear();
		compiledCache.clear();
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

	public function compile(useCache:Bool = true):CompiledBarrage {
		if (!useCache) {
			return compiled = IRCompiler.compile(this);
		}
		if (compiled != null) {
			return compiled;
		}
		return compiled = IRCompiler.compile(this);
	}

	public inline function compileToBytes(useCache:Bool = true):haxe.io.Bytes {
		return compile(useCache).toBytes();
	}

	public static inline function compileString(source:String, useCache:Bool = true):CompiledBarrage {
		if (useCache && compiledCache.exists(source)) {
			return compiledCache.get(source);
		}
		final barrage = fromString(source, useCache);
		final compiled = IRCompiler.compile(barrage, source);
		barrage.compiled = compiled;
		if (useCache) {
			compiledCache.set(source, compiled);
		}
		return compiled;
	}

	public static inline function compileStringToBytes(source:String, useCache:Bool = true):haxe.io.Bytes {
		return compileString(source, useCache).toBytes();
	}

	public static inline function fromCompiledBytes(bytes:haxe.io.Bytes):Barrage {
		return CompiledBarrage.fromBytes(bytes).instantiate();
	}
}
