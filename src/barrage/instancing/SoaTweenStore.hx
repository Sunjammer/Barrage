package barrage.instancing;

import barrage.instancing.SoaBulletStore.BulletHandle;

private class TweenChannel {
	public var active:Bool = false;
	public var start:Float = 0;
	public var target:Float = 0;
	public var duration:Float = 0;
	public var time:Float = 0;

	public function new() {}
}

class SoaTweenStore {
	final speed:Array<TweenChannel>;
	final angle:Array<TweenChannel>;
	final acceleration:Array<TweenChannel>;

	public function new() {
		speed = [];
		angle = [];
		acceleration = [];
	}

	public function clear():Void {
		speed.resize(0);
		angle.resize(0);
		acceleration.resize(0);
	}

	inline function ensure(ch:Array<TweenChannel>, h:BulletHandle):TweenChannel {
		if (ch[h] == null) {
			ch[h] = new TweenChannel();
		}
		return ch[h];
	}

	public function retargetSpeed(handle:BulletHandle, start:Float, target:Float, duration:Float, initDelta:Float = 0):Void {
		retarget(ensure(speed, handle), start, target, duration, initDelta);
	}

	public function retargetAngle(handle:BulletHandle, start:Float, target:Float, duration:Float, initDelta:Float = 0):Void {
		retarget(ensure(angle, handle), start, target, duration, initDelta);
	}

	public function retargetAcceleration(handle:BulletHandle, start:Float, target:Float, duration:Float, initDelta:Float = 0):Void {
		retarget(ensure(acceleration, handle), start, target, duration, initDelta);
	}

	inline function retarget(ch:TweenChannel, start:Float, target:Float, duration:Float, initDelta:Float):Void {
		ch.active = true;
		ch.start = start;
		ch.target = target;
		ch.duration = duration <= 0 ? 1e-9 : duration;
		ch.time = 0;
		if (initDelta > 0) {
			ch.time = initDelta;
			if (ch.time > ch.duration) {
				ch.time = ch.duration;
			}
		}
	}

	inline function eval(ch:TweenChannel):Float {
		if (ch.time >= ch.duration) {
			return ch.target;
		}
		final t = ch.time / ch.duration;
		return (ch.target - ch.start) * t + ch.start;
	}

	public function updateHandle(handle:BulletHandle, delta:Float, bullets:SoaBulletStore):Void {
		updateChannel(speed[handle], handle, delta, bullets, 0);
		updateChannel(angle[handle], handle, delta, bullets, 1);
		updateChannel(acceleration[handle], handle, delta, bullets, 2);
	}

	inline function updateChannel(ch:TweenChannel, handle:BulletHandle, delta:Float, bullets:SoaBulletStore, field:Int):Void {
		if (ch == null || !ch.active) {
			return;
		}
		ch.time += delta;
		if (ch.time >= ch.duration) {
			ch.time = ch.duration;
			ch.active = false;
		}
		final value = eval(ch);
		switch (field) {
			case 0:
				bullets.setSpeed(handle, value);
			case 1:
				bullets.setAngle(handle, value);
			case 2:
				bullets.setAcceleration(handle, value);
		}
	}
}
