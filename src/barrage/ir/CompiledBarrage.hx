package barrage.ir;

import barrage.Barrage;
import barrage.data.ActionDef;
import barrage.data.BulletDef;
import barrage.data.targets.TargetSelector;
import barrage.instancing.IBulletEmitter;
import barrage.instancing.IRng;
import barrage.instancing.RunningBarrage;
import haxe.io.Bytes;

class CompiledBarrage {
	public static final FORMAT_VERSION = 1;

	public var version:Int;
	public var name:String;
	public var frameRate:Int;
	public var difficulty:Int;
	public var startActionId:Int;
	public var actions:Array<CompiledAction>;
	public var bullets:Array<BulletDef>;
	public var defaultBullet:BulletDef;
	public var targets:Map<String, TargetSelector>;
	public var source:Null<String>;

	public function new(name:String, frameRate:Int, difficulty:Int, startActionId:Int, actions:Array<CompiledAction>, bullets:Array<BulletDef>,
			defaultBullet:BulletDef, targets:Map<String, TargetSelector>, ?source:String) {
		this.version = FORMAT_VERSION;
		this.name = name;
		this.frameRate = frameRate;
		this.difficulty = difficulty;
		this.startActionId = startActionId;
		this.actions = actions;
		this.bullets = bullets;
		this.defaultBullet = defaultBullet;
		this.targets = targets;
		this.source = source;
	}

	public function instantiate():Barrage {
		final barrage = new Barrage();
		barrage.name = name;
		barrage.frameRate = frameRate;
		barrage.difficulty = difficulty;
		barrage.actions = [];
		for (compiled in actions) {
			if (compiled == null)
				continue;
			barrage.actions[compiled.def.id] = compiled.def;
		}
		barrage.start = cast barrage.actions[startActionId];
		barrage.bullets = bullets;
		barrage.defaultBullet = defaultBullet;
		barrage.targets = targets;
		return barrage;
	}

	public inline function run(emitter:IBulletEmitter, speedScale:Float = 1.0, accelScale:Float = 1.0, ?rng:IRng):RunningBarrage {
		return instantiate().run(emitter, speedScale, accelScale, rng);
	}

	public function toBytes():Bytes {
		if (source == null) {
			throw "CompiledBarrage.toBytes requires source text; use Barrage.compileString(...) for AOT packaging.";
		}
		final payload = {
			version: FORMAT_VERSION,
			source: source
		};
		return Bytes.ofString(haxe.Serializer.run(payload));
	}

	public static function fromBytes(bytes:Bytes):CompiledBarrage {
		final payload:Dynamic = haxe.Unserializer.run(bytes.toString());
		if (payload.version != FORMAT_VERSION)
			throw "Unsupported CompiledBarrage format version " + payload.version;
		return Barrage.compileString(payload.source, false);
	}

	public function getActionDefs():Array<ActionDef> {
		final out = new Array<ActionDef>();
		for (compiled in actions) {
			if (compiled != null) {
				out[compiled.def.id] = compiled.def;
			}
		}
		return out;
	}
}
