package barrage.instancing;

class SeededRng implements IRng {
	var state:Int;

	public function new(seed:Int = 0) {
		state = seed;
	}

	public inline function nextFloat():Float {
		// LCG parameters from Numerical Recipes (32-bit arithmetic).
		state = state * 1664525 + 1013904223;
		final unsigned = state >>> 0;
		return unsigned / 4294967296.0;
	}
}
