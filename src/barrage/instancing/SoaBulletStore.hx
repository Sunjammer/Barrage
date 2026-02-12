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
	public var dirX:Array<Float>;
	public var dirY:Array<Float>;
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
		dirX = [];
		dirY = [];
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
			final rad = bullet.angle * Math.PI / 180;
			dirX.push(Math.cos(rad));
			dirY.push(Math.sin(rad));
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
			final rad = bullet.angle * Math.PI / 180;
			dirX[idx] = Math.cos(rad);
			dirY[idx] = Math.sin(rad);
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

	public inline function getSpeed(handle:BulletHandle):Float {
		return speed[handle];
	}

	public inline function getAngle(handle:BulletHandle):Float {
		return angle[handle];
	}

	public inline function getAcceleration(handle:BulletHandle):Float {
		return acceleration[handle];
	}

	public inline function isActive(handle:BulletHandle):Bool {
		return active[handle];
	}

	public inline function setSpeed(handle:BulletHandle, value:Float):Void {
		speed[handle] = value;
		final vx = dirX[handle] * value;
		final vy = dirY[handle] * value;
		velocityX[handle] = vx;
		velocityY[handle] = vy;
		final b = source[handle];
		b.speed = value;
		b.velocityX = vx;
		b.velocityY = vy;
	}

	public inline function setAngle(handle:BulletHandle, value:Float):Void {
		angle[handle] = value;
		final rad = value * Math.PI / 180;
		final dx = Math.cos(rad);
		final dy = Math.sin(rad);
		dirX[handle] = dx;
		dirY[handle] = dy;
		final spd = speed[handle];
		final vx = dx * spd;
		final vy = dy * spd;
		velocityX[handle] = vx;
		velocityY[handle] = vy;
		final b = source[handle];
		b.angle = value;
		b.velocityX = vx;
		b.velocityY = vy;
	}

	public inline function setAcceleration(handle:BulletHandle, value:Float):Void {
		acceleration[handle] = value;
		source[handle].acceleration = value;
	}

	public inline function stepHandle(handle:BulletHandle, delta:Float):Void {
		var spd = speed[handle] + acceleration[handle] * delta;
		speed[handle] = spd;
		final vx = dirX[handle] * spd;
		final vy = dirY[handle] * spd;
		velocityX[handle] = vx;
		velocityY[handle] = vy;
		final x = posX[handle] + vx * delta;
		final y = posY[handle] + vy * delta;
		posX[handle] = x;
		posY[handle] = y;

		final b = source[handle];
		b.speed = spd;
		b.velocityX = vx;
		b.velocityY = vy;
		b.posX = x;
		b.posY = y;
	}

	public inline function syncFromExternal(handle:BulletHandle):Void {
		final b = source[handle];
		final prevAngle = angle[handle];
		posX[handle] = b.posX;
		posY[handle] = b.posY;
		speed[handle] = b.speed;
		angle[handle] = b.angle;
		acceleration[handle] = b.acceleration;
		velocityX[handle] = b.velocityX;
		velocityY[handle] = b.velocityY;
		final spd = b.speed;
		if (Math.abs(spd) > 1e-9) {
			dirX[handle] = b.velocityX / spd;
			dirY[handle] = b.velocityY / spd;
		} else if (b.angle != prevAngle) {
			final rad = b.angle * Math.PI / 180;
			dirX[handle] = Math.cos(rad);
			dirY[handle] = Math.sin(rad);
		}
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
