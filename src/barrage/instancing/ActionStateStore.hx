package barrage.instancing;

@:forward
abstract ActionHandle(Int) from Int to Int {
	public inline function new(v:Int) {
		this = v;
	}

	public static inline var INVALID:ActionHandle = cast -1;
}

class ActionStateStore {
	public var sleepTime:Array<Float>;
	public var currentBullet:Array<IBarrageBullet>;
	public var triggeringBullet:Array<IBarrageBullet>;
	public var prevAngle:Array<Float>;
	public var prevSpeed:Array<Float>;
	public var prevAccel:Array<Float>;
	public var prevPositionX:Array<Float>;
	public var prevPositionY:Array<Float>;
	public var actionTime:Array<Float>;
	public var prevDelta:Array<Float>;
	public var enterSerial:Array<Int>;
	public var completedCycles:Array<Int>;
	public var runEvents:Array<Int>;
	public var repeatCount:Array<Int>;
	public var endless:Array<Bool>;
	public var callingAction:Array<Null<RunningAction>>;
	public var active:Array<Bool>;

	final freeList:Array<Int>;

	public function new() {
		sleepTime = [];
		currentBullet = [];
		triggeringBullet = [];
		prevAngle = [];
		prevSpeed = [];
		prevAccel = [];
		prevPositionX = [];
		prevPositionY = [];
		actionTime = [];
		prevDelta = [];
		enterSerial = [];
		completedCycles = [];
		runEvents = [];
		repeatCount = [];
		endless = [];
		callingAction = [];
		active = [];
		freeList = [];
	}

	public function alloc():ActionHandle {
		final idx:Int = if (freeList.length > 0) cast freeList.pop() else active.length;
		if (idx == active.length) {
			sleepTime.push(0.0);
			currentBullet.push(null);
			triggeringBullet.push(null);
			prevAngle.push(0.0);
			prevSpeed.push(0.0);
			prevAccel.push(0.0);
			prevPositionX.push(0.0);
			prevPositionY.push(0.0);
			actionTime.push(0.0);
			prevDelta.push(0.0);
			enterSerial.push(0);
			completedCycles.push(0);
			runEvents.push(0);
			repeatCount.push(0);
			endless.push(false);
			callingAction.push(null);
			active.push(true);
		} else {
			sleepTime[idx] = 0.0;
			currentBullet[idx] = null;
			triggeringBullet[idx] = null;
			prevAngle[idx] = 0.0;
			prevSpeed[idx] = 0.0;
			prevAccel[idx] = 0.0;
			prevPositionX[idx] = 0.0;
			prevPositionY[idx] = 0.0;
			actionTime[idx] = 0.0;
			prevDelta[idx] = 0.0;
			enterSerial[idx] = 0;
			completedCycles[idx] = 0;
			runEvents[idx] = 0;
			repeatCount[idx] = 0;
			endless[idx] = false;
			callingAction[idx] = null;
			active[idx] = true;
		}
		return cast idx;
	}

	public inline function release(handle:ActionHandle):Void {
		if (!active[handle]) {
			return;
		}
		active[handle] = false;
		currentBullet[handle] = null;
		triggeringBullet[handle] = null;
		callingAction[handle] = null;
	}
}
