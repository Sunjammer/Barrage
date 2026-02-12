package barrage.instancing;

import haxe.ds.ObjectMap;

@:forward
abstract BulletHandle(Int) from Int to Int {
	public inline function new(v:Int) {
		this = v;
	}

	public static inline var INVALID:BulletHandle = cast -1;
}

class SoaBulletStore {
	public var source:Array<IBarrageBullet>;
	public var posX:Array<Float>;
	public var posY:Array<Float>;
	public var speed:Array<Float>;
	public var angle:Array<Float>;
	public var acceleration:Array<Float>;
	public var velocityX:Array<Float>;
	public var velocityY:Array<Float>;
	public var active:Array<Bool>;
	public var typeId:Array<Int>;
	public var generation:Array<Int>;

	final freeList:Array<Int>;
	final handleByBullet:ObjectMap<IBarrageBullet, Int>;

	public function new() {
		source = [];
		posX = [];
		posY = [];
		speed = [];
		angle = [];
		acceleration = [];
		velocityX = [];
		velocityY = [];
		active = [];
		typeId = [];
		generation = [];
		freeList = [];
		handleByBullet = new ObjectMap<IBarrageBullet, Int>();
	}

	public function alloc(bullet:IBarrageBullet, bulletTypeId:Int):BulletHandle {
		final idx:Int = if (freeList.length > 0) freeList.pop() else source.length;
		if (idx == source.length) {
			source.push(bullet);
			posX.push(bullet.posX);
			posY.push(bullet.posY);
			speed.push(bullet.speed);
			angle.push(bullet.angle);
			acceleration.push(bullet.acceleration);
			velocityX.push(bullet.velocityX);
			velocityY.push(bullet.velocityY);
			active.push(bullet.active);
			typeId.push(bulletTypeId);
			generation.push(0);
		} else {
			source[idx] = bullet;
			posX[idx] = bullet.posX;
			posY[idx] = bullet.posY;
			speed[idx] = bullet.speed;
			angle[idx] = bullet.angle;
			acceleration[idx] = bullet.acceleration;
			velocityX[idx] = bullet.velocityX;
			velocityY[idx] = bullet.velocityY;
			active[idx] = bullet.active;
			typeId[idx] = bulletTypeId;
			generation[idx] = generation[idx] + 1;
		}
		handleByBullet.set(bullet, idx);
		return cast idx;
	}

	public inline function getSource(handle:BulletHandle):IBarrageBullet {
		return source[handle];
	}

	public inline function getType(handle:BulletHandle):Int {
		return typeId[handle];
	}

	public inline function getPosX(handle:BulletHandle):Float {
		return posX[handle];
	}

	public inline function getPosY(handle:BulletHandle):Float {
		return posY[handle];
	}

	public inline function isActive(handle:BulletHandle):Bool {
		return active[handle];
	}

	public inline function syncFromExternal(handle:BulletHandle):Void {
		final b = source[handle];
		posX[handle] = b.posX;
		posY[handle] = b.posY;
		speed[handle] = b.speed;
		angle[handle] = b.angle;
		acceleration[handle] = b.acceleration;
		velocityX[handle] = b.velocityX;
		velocityY[handle] = b.velocityY;
		active[handle] = b.active;
	}

	public inline function kill(handle:BulletHandle, emitter:IBulletEmitter):Void {
		if (!active[handle]) {
			return;
		}
		emitter.kill(source[handle]);
		active[handle] = false;
	}

	public inline function release(handle:BulletHandle):Void {
		final b = source[handle];
		if (b != null) {
			handleByBullet.remove(b);
		}
		active[handle] = false;
		freeList.push(handle);
	}

	public inline function getHandleForBullet(bullet:IBarrageBullet):BulletHandle {
		final h = handleByBullet.get(bullet);
		return h == null ? BulletHandle.INVALID : cast h;
	}
}
