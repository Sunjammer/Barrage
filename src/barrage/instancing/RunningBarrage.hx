package barrage.instancing;

import barrage.Barrage;
import barrage.data.BulletDef;
import barrage.data.events.FireEventDef;
import barrage.data.properties.Property;
import barrage.ir.CompiledBarrage;
import barrage.data.targets.TargetSelector;
import barrage.instancing.events.FireEvent;
import barrage.instancing.ActionStateStore.ActionHandle;
import barrage.instancing.IOrigin;
import barrage.instancing.SoaBulletStore.BulletHandle;
import barrage.script.ScriptContext;
#if barrage_profile
import haxe.Timer;
#end
import haxe.ds.IntMap;

typedef Vec2 = {x:Float, y:Float}

class RunningBarrage {
	public var owner:Barrage;
	public var initAction:RunningAction;
	// public var allActions:Vector<RunningAction>;
	public var activeActions:Array<RunningAction>;
	public var time:Float = 0;
	public var onComplete:RunningBarrage->Void;
	public var lastBulletFired:IBarrageBullet;
	public var bullets:Array<BulletHandle>;
	public var speedScale:Float;
	public var accelScale:Float;
	public var rng:IRng;
	#if barrage_profile
	public var profile:RuntimeProfile;
	#end
	public var scriptContext:ScriptContext;
	public var useVmExecution:Bool;
	public var strictNativeExpressions:Bool;
	public var compiledProgram:Null<CompiledBarrage>;
	public var tickCount:Int = 0;

	static var basePositionVec:Vec2 = {x: 0, y: 0};

	var started:Bool;
	var lastDelta:Float = 0;
	var bulletNameToId:Map<String, Int>;
	var bulletsByDef:Array<Array<BulletHandle>>;
	var spatialByType:Array<IntMap<Array<BulletHandle>>>;
	var spatialTickByType:Array<Int>;
	var spatialCellSize:Float = 128;
	var actionStore:ActionStateStore;
	var bulletStore:SoaBulletStore;
	var tweenStore:SoaTweenStore;
	var slotDifficulty:Int;
	var slotBarrageTimeLower:Int;
	var slotBarrageTimeCamel:Int;
	var slotActionTimeLower:Int;
	var slotActionTimeCamel:Int;
	var slotRepeatCountLower:Int;
	var slotRepeatCountCamel:Int;

	public var emitter:IBulletEmitter;

	public function new(emitter:IBulletEmitter, owner:Barrage, speedScale:Float = 1.0, accelScale:Float = 1.0, rng:IRng, useVmExecution:Bool = false,
			strictNativeExpressions:Bool = false) {
		this.speedScale = speedScale;
		this.accelScale = accelScale;
		this.rng = rng;
		this.useVmExecution = useVmExecution;
		this.strictNativeExpressions = strictNativeExpressions;
		this.emitter = emitter;
		this.owner = owner;
		#if barrage_profile
		this.profile = new RuntimeProfile();
		this.scriptContext = new ScriptContext(rng, strictNativeExpressions, profile);
		#else
		this.scriptContext = new ScriptContext(rng, strictNativeExpressions);
		#end
		this.compiledProgram = useVmExecution ? owner.compile() : null;
		activeActions = [];
		bullets = [];
		actionStore = new ActionStateStore();
		bulletStore = new SoaBulletStore();
		tweenStore = new SoaTweenStore();
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
		slotDifficulty = scriptContext.resolveSlot("difficulty");
		slotBarrageTimeLower = scriptContext.resolveSlot("barragetime");
		slotBarrageTimeCamel = scriptContext.resolveSlot("barrageTime");
		slotActionTimeLower = scriptContext.resolveSlot("actiontime");
		slotActionTimeCamel = scriptContext.resolveSlot("actionTime");
		slotRepeatCountLower = scriptContext.resolveSlot("repeatcount");
		slotRepeatCountCamel = scriptContext.resolveSlot("repeatCount");
		scriptContext.setVarBySlot(slotDifficulty, owner.difficulty);
	}

	public function start():Void {
		time = lastDelta = 0;
		tickCount = 0;
		#if barrage_profile
		profile.reset();
		#end
		scriptContext.setVarBySlot(slotBarrageTimeLower, time);
		scriptContext.setVarBySlot(slotBarrageTimeCamel, time);
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
		#if barrage_profile
		final tUpdate = Timer.stamp();
		#end
		time += delta;
		lastDelta = delta;
		tickCount++;

		#if barrage_profile
		final tCleanup = Timer.stamp();
		#end
		cleanBullets();
		if ((tickCount % 120) == 0) {
			pruneBulletBuckets();
		}
		updateTweens(delta);
		#if barrage_profile
			profile.cleanupSeconds += Timer.stamp() - tCleanup;
		#end

		scriptContext.setVarBySlot(slotBarrageTimeLower, time);
		scriptContext.setVarBySlot(slotBarrageTimeCamel, time);

		if (activeActions.length == 0) {
			stop();
			if (onComplete != null)
				onComplete(this);
		} else {
			#if barrage_profile
			final tActions = Timer.stamp();
			#end
			var i = activeActions.length;
			while (i-- > 0) {
				activeActions[i].update(this, delta);
			}
			#if barrage_profile
				profile.actionSeconds += Timer.stamp() - tActions;
			#end
		}
		simulateBullets(delta);
		#if barrage_profile
		profile.updateTicks++;
		profile.updateSeconds += Timer.stamp() - tUpdate;
		if (bullets.length > profile.peakActiveBullets) {
			profile.peakActiveBullets = bullets.length;
		}
		#end
	}

	inline function cleanBullets():Void {
		var i = bullets.length;
		while (i-- > 0) {
			final handle = bullets[i];
			if (!bulletStore.isActive(handle) || !bulletStore.getSource(handle).active) {
				bulletStore.release(handle);
				final last = bullets.pop();
				if (i < bullets.length) {
					bullets[i] = last;
				}
			}
		}
	}

	inline function simulateBullets(delta:Float):Void {
		for (handle in bullets) {
			if (!bulletStore.isActive(handle)) {
				continue;
			}
			bulletStore.stepHandle(handle, delta);
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
				if (!bulletStore.isActive(bucket[i])) {
					bucket.splice(i, 1);
					removedAny = true;
				}
			}
			if (removedAny) {
				spatialTickByType[bucketId] = -1;
			}
		}
	}

	inline function updateTweens(delta:Float):Void {
		for (handle in bullets) {
			if (!bulletStore.isActive(handle)) {
				continue;
			}
			tweenStore.updateHandle(handle, delta, bulletStore);
		}
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

	public inline function allocActionState():ActionHandle {
		return actionStore.alloc();
	}

	public inline function releaseActionState(handle:ActionHandle):Void {
		actionStore.release(handle);
	}

	public inline function getActionStore():ActionStateStore {
		return actionStore;
	}

	public function dispose() {
		while (activeActions.length > 0) {
			stopAction(activeActions[0]);
		}
		emitter = null;
		bulletsByDef = [];
		spatialByType = [];
		spatialTickByType = [];
		actionStore = new ActionStateStore();
		bulletStore = new SoaBulletStore();
		tweenStore = new SoaTweenStore();
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

	function applyPropertyConst(origin:Vec2, base:Float, prev:Float, prop:Property, runningAction:RunningAction):Float {
		var other = prop.constValue;
		if (prop.modifier.has(INCREMENTAL)) {
			return prev + other;
		} else if (prop.modifier.has(RELATIVE)) {
			return base + other;
		} else if (prop.modifier.has(AIMED)) {
			return getAngleToTarget(origin.x, origin.y, runningAction, prop.target) + other;
		} else if (prop.modifier.has(RANDOM)) {
			return randomAngle() + other;
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
		#if barrage_profile
		final t0 = Timer.stamp();
		profile.targetQueries++;
		#end
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
				#if barrage_profile
				profile.targetingSeconds += Timer.stamp() - t0;
				#end
				return spatialHit;
			}
		}

		var nearest:BulletHandle = BulletHandle.INVALID;
		var bestDist2 = Math.POSITIVE_INFINITY;
		for (handle in bucket) {
			if (!bulletStore.isActive(handle))
				continue;
			final dx = bulletStore.getPosX(handle) - origin.posX;
			final dy = bulletStore.getPosY(handle) - origin.posY;
			final dist2 = dx * dx + dy * dy;
			if (dist2 < bestDist2) {
				bestDist2 = dist2;
				nearest = handle;
			}
		}
		#if barrage_profile
		profile.targetingSeconds += Timer.stamp() - t0;
		#end
		return nearest != BulletHandle.INVALID ? bulletStore.getSource(nearest) : emitter;
	}

	inline function spatialKey(ix:Int, iy:Int):Int {
		return ((ix & 0xFFFF) << 16) ^ (iy & 0xFFFF);
	}

	function ensureSpatialForType(typeId:Int, bucket:Array<BulletHandle>):IntMap<Array<BulletHandle>> {
		if (spatialTickByType[typeId] == tickCount && spatialByType[typeId] != null) {
			return spatialByType[typeId];
		}
		final map = new IntMap<Array<BulletHandle>>();
		for (handle in bucket) {
			if (!bulletStore.isActive(handle))
				continue;
			final ix = Std.int(Math.floor(bulletStore.getPosX(handle) / spatialCellSize));
			final iy = Std.int(Math.floor(bulletStore.getPosY(handle) / spatialCellSize));
			final key = spatialKey(ix, iy);
			var cell = map.get(key);
			if (cell == null) {
				cell = [];
				map.set(key, cell);
			}
			cell.push(handle);
		}
		spatialByType[typeId] = map;
		spatialTickByType[typeId] = tickCount;
		return map;
	}

	function querySpatialNearest(spatial:IntMap<Array<BulletHandle>>, x:Float, y:Float):IOrigin {
		final baseX = Std.int(Math.floor(x / spatialCellSize));
		final baseY = Std.int(Math.floor(y / spatialCellSize));
		var nearest:BulletHandle = BulletHandle.INVALID;
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
					for (handle in cell) {
						if (!bulletStore.isActive(handle))
							continue;
						final dx = bulletStore.getPosX(handle) - x;
						final dy = bulletStore.getPosY(handle) - y;
						final dist2 = dx * dx + dy * dy;
						if (dist2 < bestDist2) {
							bestDist2 = dist2;
							nearest = handle;
						}
					}
				}
			}
			if (nearest != BulletHandle.INVALID) {
				final safeBest = bestDist2 <= 0 ? 0 : Math.sqrt(bestDist2);
				if ((r + 1) * spatialCellSize > safeBest) {
					return bulletStore.getSource(nearest);
				}
			}
		}
		return nearest != BulletHandle.INVALID ? bulletStore.getSource(nearest) : null;
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
		final emitted = emitter.emit(action.prevPositionX, action.prevPositionY, baseDirection, spd, baseAccel * accelScale, delta);
		emitted.id = bulletID;
		emitted.speed = spd;
		emitted.angle = baseDirection;
		final handle = bulletStore.alloc(emitted, bulletID);
		lastBulletFired = bulletStore.getSource(handle);
		bullets.push(handle);
		#if barrage_profile
		profile.bulletsSpawned++;
		#end
		if (bulletID >= 0) {
			if (bulletsByDef[bulletID] == null) {
				bulletsByDef[bulletID] = [];
			}
			bulletsByDef[bulletID].push(handle);
			spatialTickByType[bulletID] = -1;
		}
		return lastBulletFired;
	}

	public function fireDefConst(action:RunningAction, eventDef:FireEventDef, bulletID:Int, delta:Float):IBarrageBullet {
		var bd:BulletDef = bulletID == -1 ? owner.defaultBullet : owner.bullets[bulletID];
		var origin = getOrigin(action);

		var baseSpeed:Float = bd.speed.scripted ? bd.speed.get(this, action) : bd.speed.constValue;
		var baseAccel:Float = bd.acceleration.scripted ? bd.acceleration.get(this, action) : bd.acceleration.constValue;
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
			var vec = eventDef.position.constValueVec;
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
			baseDirection = bd.direction.scripted ? bd.direction.get(this, action) : bd.direction.constValue;
		}

		if (eventDef.speed != null) {
			baseSpeed = applyPropertyConst(basePosition, baseSpeed, lastSpeed, eventDef.speed, action);
		}
		if (eventDef.acceleration != null) {
			baseAccel = applyPropertyConst(basePosition, baseAccel, lastAcceleration, eventDef.acceleration, action);
		}
		if (eventDef.direction != null) {
			baseDirection = applyPropertyConst(basePosition, baseDirection, lastDirection, eventDef.direction, action);
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
		final emitted = emitter.emit(action.prevPositionX, action.prevPositionY, baseDirection, spd, baseAccel * accelScale, delta);
		emitted.id = bulletID;
		emitted.speed = spd;
		emitted.angle = baseDirection;
		final handle = bulletStore.alloc(emitted, bulletID);
		lastBulletFired = bulletStore.getSource(handle);
		bullets.push(handle);
		#if barrage_profile
		profile.bulletsSpawned++;
		#end
		if (bulletID >= 0) {
			if (bulletsByDef[bulletID] == null) {
				bulletsByDef[bulletID] = [];
			}
			bulletsByDef[bulletID].push(handle);
			spatialTickByType[bulletID] = -1;
		}
		return lastBulletFired;
	}

	public function killBullet(bullet:IBarrageBullet):Void {
		final handle = getHandleForBullet(bullet);
		if (handle != BulletHandle.INVALID) {
			bulletStore.kill(handle, emitter);
		} else {
			emitter.kill(bullet);
		}
	}

	public function getHandleForBullet(bullet:IBarrageBullet):BulletHandle {
		return bulletStore.getHandleForBullet(bullet);
	}

	public function retargetSpeed(bullet:IBarrageBullet, target:Float, duration:Float, initDelta:Float = 0):Void {
		final handle = getHandleForBullet(bullet);
		if (handle == BulletHandle.INVALID) {
			return;
		}
		tweenStore.retargetSpeed(handle, bulletStore.getSpeed(handle), target, duration, initDelta);
	}

	public function retargetAngle(bullet:IBarrageBullet, target:Float, duration:Float, initDelta:Float = 0):Void {
		final handle = getHandleForBullet(bullet);
		if (handle == BulletHandle.INVALID) {
			return;
		}
		tweenStore.retargetAngle(handle, bulletStore.getAngle(handle), target, duration, initDelta);
	}

	public function retargetAcceleration(bullet:IBarrageBullet, target:Float, duration:Float, initDelta:Float = 0):Void {
		final handle = getHandleForBullet(bullet);
		if (handle == BulletHandle.INVALID) {
			return;
		}
		tweenStore.retargetAcceleration(handle, bulletStore.getAcceleration(handle), target, duration, initDelta);
	}

	public inline function setBulletSpeed(bullet:IBarrageBullet, value:Float):Void {
		final handle = getHandleForBullet(bullet);
		if (handle != BulletHandle.INVALID) {
			bulletStore.setSpeed(handle, value);
		} else {
			bullet.speed = value;
		}
	}

	public inline function setBulletAngle(bullet:IBarrageBullet, value:Float):Void {
		final handle = getHandleForBullet(bullet);
		if (handle != BulletHandle.INVALID) {
			bulletStore.setAngle(handle, value);
		} else {
			bullet.angle = value;
		}
	}

	public inline function setBulletAcceleration(bullet:IBarrageBullet, value:Float):Void {
		final handle = getHandleForBullet(bullet);
		if (handle != BulletHandle.INVALID) {
			bulletStore.setAcceleration(handle, value);
		} else {
			bullet.acceleration = value;
		}
	}

	public inline function setScriptActionTimeVars(value:Float):Void {
		scriptContext.setVarBySlot(slotActionTimeLower, value);
		scriptContext.setVarBySlot(slotActionTimeCamel, value);
	}

	public inline function setScriptRepeatCountVars(value:Int):Void {
		scriptContext.setVarBySlot(slotRepeatCountLower, value);
		scriptContext.setVarBySlot(slotRepeatCountCamel, value);
	}
}
