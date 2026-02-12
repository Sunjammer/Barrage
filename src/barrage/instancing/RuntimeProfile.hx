package barrage.instancing;

class RuntimeProfile {
	public var updateSeconds:Float = 0;
	public var updateTicks:Int = 0;
	public var actionSeconds:Float = 0;
	public var cleanupSeconds:Float = 0;
	public var targetingSeconds:Float = 0;
	public var scriptEvalSeconds:Float = 0;
	public var nativeScriptEvals:Int = 0;
	public var fallbackScriptEvals:Int = 0;
	public var bulletsSpawned:Int = 0;
	public var targetQueries:Int = 0;
	public var peakActiveBullets:Int = 0;

	public function new() {}

	public function reset():Void {
		updateSeconds = 0;
		updateTicks = 0;
		actionSeconds = 0;
		cleanupSeconds = 0;
		targetingSeconds = 0;
		scriptEvalSeconds = 0;
		nativeScriptEvals = 0;
		fallbackScriptEvals = 0;
		bulletsSpawned = 0;
		targetQueries = 0;
		peakActiveBullets = 0;
	}
}
