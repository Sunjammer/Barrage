package barrage.instancing;

import barrage.Barrage;
import barrage.data.BulletDef;
import barrage.data.events.FireEventDef;
import barrage.data.properties.Property;
import barrage.ir.CompiledBarrage;
import barrage.data.targets.TargetSelector;
import barrage.instancing.animation.Animator;
import barrage.instancing.events.FireEvent;
import barrage.instancing.IOrigin;
import barrage.script.ScriptContext;
import haxe.Timer;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;

typedef Vec2 = {x:Float, y:Float}

class RunningBarrage {
	public var owner:Barrage;
	public var initAction:RunningAction;
	// public var allActions:Vector<RunningAction>;
	public var activeActions:Array<RunningAction>;
	public var time:Float = 0;
	public var onComplete:RunningBarrage->Void;
	public var lastBulletFired:IBarrageBullet;
	public var animators:Array<Animator>;
	public var bullets:Array<IBarrageBullet>;
	public var speedScale:Float;
	public var accelScale:Float;
	public var rng:IRng;
	public var profile:RuntimeProfile;
	public var profilingEnabled:Bool = false;
	public var scriptContext:ScriptContext;
	public var useVmExecution:Bool;
	public var compiledProgram:Null<CompiledBarrage>;
	public var tickCount:Int = 0;

	static var basePositionVec:Vec2 = {x: 0, y: 0};

	var started:Bool;
	var lastDelta:Float = 0;
	var animatorByTarget:ObjectMap<IBarrageBullet, Animator>;
	var bulletNameToId:Map<String, Int>;
	var bulletsByDef:Array<Array<IBarrageBullet>>;
	var spatialByType:Array<IntMap<Array<IBarrageBullet>>>;
	var spatialTickByType:Array<Int>;
	var spatialCellSize:Float = 128;

	public var emitter:IBulletEmitter;

	public function new(emitter:IBulletEmitter, owner:Barrage, speedScale:Float = 1.0, accelScale:Float = 1.0, rng:IRng, useVmExecution:Bool = false) {
		this.speedScale = speedScale;
		this.accelScale = accelScale;
		this.rng = rng;
		this.useVmExecution = useVmExecution;
		this.emitter = emitter;
		this.owner = owner;
		this.profile = new RuntimeProfile();
		this.scriptContext = new ScriptContext(rng, profile);
		this.compiledProgram = useVmExecution ? owner.compile() : null;
		activeActions = [];
		bullets = [];
		animators = [];
		animatorByTarget = new ObjectMap<IBarrageBullet, Animator>();
		bulletNameToId = new Map<String, Int>();
		bulletsByDef = [];
		spatialByType = [];
		spatialTickByType = [];
		for (i in 0...owner.bullets.length) {
			final def = owner.bullets[i];
			if (def != null) {
				bulletNameToId.set(def.name.toLowerCase(), i);
			}
		}
		scriptContext.setVar("difficulty", owner.difficulty);
	}

	public function start():Void {
		time = lastDelta = 0;
		tickCount = 0;
		profile.reset();
		scriptContext.setVar("barragetime", time);
		scriptContext.setVar("barrageTime", time);
		runAction(null, new RunningAction(this, owner.start, useVmExecution));
		started = true;
	}

	public function stop():Void {
		while (activeActions.length > 0) {
			stopAction(activeActions[0]);
		}
		started = false;
	}

	public inline function update(delta:Float) {
		if (!started)
			return;
		final tUpdate = profilingEnabled ? Timer.stamp() : 0.0;
		time += delta;
		lastDelta = delta;
		tickCount++;

		final tCleanup = profilingEnabled ? Timer.stamp() : 0.0;
		cleanBullets();
		if ((tickCount % 120) == 0) {
			pruneBulletBuckets();
		}
		updateAnimators(delta);
		if (profilingEnabled) {
			profile.cleanupSeconds += Timer.stamp() - tCleanup;
		}

		scriptContext.setVar("barragetime", time);
		scriptContext.setVar("barrageTime", time);

		if (activeActions.length == 0) {
			stop();
			if (onComplete != null)
				onComplete(this);
		} else {
			final tActions = profilingEnabled ? Timer.stamp() : 0.0;
			var i = activeActions.length;
			while (i-- > 0) {
				activeActions[i].update(this, delta);
			}
			if (profilingEnabled) {
				profile.actionSeconds += Timer.stamp() - tActions;
			}
		}
		if (profilingEnabled) {
			profile.updateTicks++;
			profile.updateSeconds += Timer.stamp() - tUpdate;
			if (bullets.length > profile.peakActiveBullets) {
				profile.peakActiveBullets = bullets.length;
			}
		}
	}

	inline function cleanBullets():Void {
		var i = bullets.length;
		while (i-- > 0) {
			if (!bullets[i].active) {
				final last = bullets.pop();
				if (i < bullets.length) {
					bullets[i] = last;
				}
			}
		}
	}

	inline function pruneBulletBuckets():Void {
		for (bucketId in 0...bulletsByDef.length) {
			final bucket = bulletsByDef[bucketId];
			if (bucket == null)
				continue;
			var i = bucket.length;
			var removedAny = false;
			while (i-- > 0) {
				if (!bucket[i].active) {
					bucket.splice(i, 1);
					removedAny = true;
				}
			}
			if (removedAny) {
				spatialTickByType[bucketId] = -1;
			}
		}
	}

	inline function updateAnimators(delta:Float) {
		var i = animators.length;
		while (i-- > 0) {
			final a = animators[i];
			if (a.update(delta) == false) {
				animatorByTarget.remove(a.target);
				final last = animators.pop();
				if (i < animators.length) {
					animators[i] = last;
				}
			}
		}
	}

	public function getAnimator(target:IBarrageBullet):Animator {
		if (animatorByTarget.exists(target)) {
			return animatorByTarget.get(target);
		}
		var a = new Animator(target);
		animators.push(a);
		animatorByTarget.set(target, a);
		return a;
	}

	public inline function runActionByID(triggerAction:RunningAction, id:Int, ?triggerBullet:IBarrageBullet, ?overrides:Array<Property>,
			delta:Float = 0):RunningAction {
		return runAction(triggerAction, new RunningAction(this, owner.actions[id], useVmExecution), triggerBullet, overrides, delta);
	}

	public inline function runAction(triggerAction:RunningAction, action:RunningAction, ?triggerBullet:IBarrageBullet, ?overrides:Array<Property>,
			delta:Float = 0):RunningAction {
		activeActions.push(action);
		if (triggerAction != null) {
			action.prevAccel = triggerAction.prevAccel;
			action.prevSpeed = triggerAction.prevSpeed;
			action.prevAngle = triggerAction.prevAngle;
			action.prevPositionX = triggerAction.prevPositionX;
			action.prevPositionY = triggerAction.prevPositionY;
		}
		action.enter(triggerAction, this, overrides);
		if (triggerBullet != null) {
			action.currentBullet = action.triggeringBullet = triggerBullet;
		}
		action.update(this, delta);
		return action;
	}

	public inline function stopAction(action:RunningAction) {
		action.exit(this);
		activeActions.remove(action);
		// trace("Stop action: "+action.def.name);
	}

	public function dispose() {
		while (activeActions.length > 0) {
			stopAction(activeActions[0]);
		}
		emitter = null;
		animatorByTarget = new ObjectMap<IBarrageBullet, Animator>();
		bulletsByDef = [];
		spatialByType = [];
		spatialTickByType = [];
	}

	function applyProperty(origin:Vec2, base:Float, prev:Float, prop:Property, runningBarrage:RunningBarrage, runningAction:RunningAction):Float {
		var other = prop.get(runningBarrage, runningAction);
		if (prop.modifier.has(INCREMENTAL)) {
			return prev + other;
		} else if (prop.modifier.has(RELATIVE)) {
			return base + other;
		} else if (prop.modifier.has(AIMED)) {
			return getAngleToTarget(origin.x, origin.y, runningAction, prop.target) + other;
		} else if (prop.modifier.has(RANDOM)) {
			return runningBarrage.randomAngle() + other;
		} else {
			return other;
		}
	}

	function resolveTargetSelector(action:RunningAction, selector:TargetSelector):TargetSelector {
		return switch (selector) {
			case TARGET_ALIAS(name):
				if (owner.targets.exists(name))
					resolveTargetSelector(action, owner.targets.get(name));
				else
					PLAYER;
			default:
				selector;
		}
	}

	function resolveTargetOrigin(action:RunningAction, selector:TargetSelector):IOrigin {
		final resolved = resolveTargetSelector(action, selector);
		return switch (resolved) {
			case PLAYER:
				emitter;
			case PARENT:
				action.triggeringBullet != null ? action.triggeringBullet : getOrigin(action);
			case SELF:
				action.currentBullet != null ? action.currentBullet : (action.triggeringBullet != null ? action.triggeringBullet : getOrigin(action));
			case NEAREST_BULLET_TYPE(typeName):
				findNearestBulletByType(typeName, action);
			case TARGET_ALIAS(_):
				emitter;
		}
	}

	function findNearestBulletByType(typeName:String, action:RunningAction):IOrigin {
		final t0 = profilingEnabled ? Timer.stamp() : 0.0;
		profile.targetQueries++;
		final origin = getOrigin(action);
		final targetId = bulletNameToId.get(typeName.toLowerCase());
		if (targetId == null)
			return emitter;
		final bucket = bulletsByDef[targetId];
		if (bucket == null)
			return emitter;

		if (bucket.length >= 64) {
			final spatial = ensureSpatialForType(targetId, bucket);
			final spatialHit = querySpatialNearest(spatial, origin.posX, origin.posY);
			if (spatialHit != null) {
				if (profilingEnabled) {
					profile.targetingSeconds += Timer.stamp() - t0;
				}
				return spatialHit;
			}
		}

		var nearest:IBarrageBullet = null;
		var bestDist2 = Math.POSITIVE_INFINITY;
		for (bullet in bucket) {
			if (!bullet.active)
				continue;
			final dx = bullet.posX - origin.posX;
			final dy = bullet.posY - origin.posY;
			final dist2 = dx * dx + dy * dy;
			if (dist2 < bestDist2) {
				bestDist2 = dist2;
				nearest = bullet;
			}
		}
		if (profilingEnabled) {
			profile.targetingSeconds += Timer.stamp() - t0;
		}
		return nearest != null ? nearest : emitter;
	}

	inline function spatialKey(ix:Int, iy:Int):Int {
		return ((ix & 0xFFFF) << 16) ^ (iy & 0xFFFF);
	}

	function ensureSpatialForType(typeId:Int, bucket:Array<IBarrageBullet>):IntMap<Array<IBarrageBullet>> {
		if (spatialTickByType[typeId] == tickCount && spatialByType[typeId] != null) {
			return spatialByType[typeId];
		}
		final map = new IntMap<Array<IBarrageBullet>>();
		for (b in bucket) {
			if (!b.active)
				continue;
			final ix = Std.int(Math.floor(b.posX / spatialCellSize));
			final iy = Std.int(Math.floor(b.posY / spatialCellSize));
			final key = spatialKey(ix, iy);
			var cell = map.get(key);
			if (cell == null) {
				cell = [];
				map.set(key, cell);
			}
			cell.push(b);
		}
		spatialByType[typeId] = map;
		spatialTickByType[typeId] = tickCount;
		return map;
	}

	function querySpatialNearest(spatial:IntMap<Array<IBarrageBullet>>, x:Float, y:Float):IBarrageBullet {
		final baseX = Std.int(Math.floor(x / spatialCellSize));
		final baseY = Std.int(Math.floor(y / spatialCellSize));
		var nearest:IBarrageBullet = null;
		var bestDist2 = Math.POSITIVE_INFINITY;
		final maxRadius = 12;
		for (r in 0...maxRadius + 1) {
			final minX = baseX - r;
			final maxX = baseX + r;
			final minY = baseY - r;
			final maxY = baseY + r;
			for (iy in minY...maxY + 1) {
				for (ix in minX...maxX + 1) {
					if (r > 0 && ix > minX && ix < maxX && iy > minY && iy < maxY)
						continue;
					final cell = spatial.get(spatialKey(ix, iy));
					if (cell == null)
						continue;
					for (b in cell) {
						if (!b.active)
							continue;
						final dx = b.posX - x;
						final dy = b.posY - y;
						final dist2 = dx * dx + dy * dy;
						if (dist2 < bestDist2) {
							bestDist2 = dist2;
							nearest = b;
						}
					}
				}
			}
			if (nearest != null) {
				final safeBest = bestDist2 <= 0 ? 0 : Math.sqrt(bestDist2);
				if ((r + 1) * spatialCellSize > safeBest) {
					return nearest;
				}
			}
		}
		return nearest;
	}

	public function getAngleToTarget(originX:Float, originY:Float, action:RunningAction, selector:TargetSelector):Float {
		final resolved = resolveTargetSelector(action, selector);
		if (resolved == PLAYER) {
			return emitter.getAngleToPlayer(originX, originY);
		}
		final target = resolveTargetOrigin(action, resolved);
		final dx = target.posX - originX;
		final dy = target.posY - originY;
		if (dx == 0 && dy == 0)
			return 0;
		return Math.atan2(dy, dx) * 180 / Math.PI;
	}

	public function randomAngle():Float {
		return rng.nextFloat() * 360;
	}

	inline function getOrigin(action:RunningAction):IOrigin {
		if (action.triggeringBullet == null) {
			if (action.callingAction != null)
				return getOrigin(action.callingAction);
			return emitter;
		} else
			return action.triggeringBullet;
	}

	public function fire(action:RunningAction, event:FireEvent, bulletID:Int, delta:Float):IBarrageBullet {
		return fireDef(action, event.def, bulletID, delta);
	}

	public function fireDef(action:RunningAction, eventDef:FireEventDef, bulletID:Int, delta:Float):IBarrageBullet {
		var bd:BulletDef = bulletID == -1 ? owner.defaultBullet : owner.bullets[bulletID];

		var origin = getOrigin(action);

		var baseSpeed:Float = bd.speed.get(this, action);
		var baseAccel:Float = bd.acceleration.get(this, action);
		var baseDirection:Float = 0;
		var basePosition = basePositionVec;

		var lastSpeed = action.prevSpeed;
		var lastDirection = action.prevAngle;
		var lastAcceleration = action.prevAccel;
		var lastPositionX = action.prevPositionX;
		var lastPositionY = action.prevPositionY;

		basePosition.x = origin.posX;
		basePosition.y = origin.posY;
		if (eventDef.position != null) {
			var vec = eventDef.position.getVector(this, action);
			if (eventDef.position.modifier.has(RELATIVE)) {
				basePosition.x = origin.posX + vec[0];
				basePosition.y = origin.posY + vec[1];
			} else if (eventDef.position.modifier.has(INCREMENTAL)) {
				basePosition.x = lastPositionX + vec[0];
				basePosition.y = lastPositionY + vec[1];
			}
		}

		if (bd == owner.defaultBullet) {
			baseDirection = emitter.getAngleToPlayer(basePosition.x, basePosition.y);
		} else {
			baseDirection = bd.direction.get(this, action);
		}

		if (eventDef.speed != null) {
			baseSpeed = applyProperty(basePosition, baseSpeed, lastSpeed, eventDef.speed, this, action);
		}
		if (eventDef.acceleration != null) {
			baseAccel = applyProperty(basePosition, baseAccel, lastAcceleration, eventDef.acceleration, this, action);
		}
		if (eventDef.direction != null) {
			baseDirection = applyProperty(basePosition, baseDirection, lastDirection, eventDef.direction, this, action);
			if (eventDef.direction.modifier.has(RELATIVE)) {
				baseDirection = action.triggeringBullet.angle + baseDirection;
			}
		}

		action.prevSpeed = baseSpeed;
		action.prevAngle = baseDirection;
		action.prevAccel = baseAccel;
		action.prevPositionX = basePosition.x;
		action.prevPositionY = basePosition.y;

		var spd = baseSpeed * speedScale;
		lastBulletFired = emitter.emit(action.prevPositionX, action.prevPositionY, baseDirection, spd, baseAccel * accelScale, delta);
		lastBulletFired.id = bulletID;
		lastBulletFired.speed = spd;
		lastBulletFired.angle = baseDirection;
		bullets.push(lastBulletFired);
		profile.bulletsSpawned++;
		if (bulletID >= 0) {
			if (bulletsByDef[bulletID] == null) {
				bulletsByDef[bulletID] = [];
			}
			bulletsByDef[bulletID].push(lastBulletFired);
			spatialTickByType[bulletID] = -1;
		}
		return lastBulletFired;
	}
}
