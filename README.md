Barrage
=======
A small domain-specific language for scripting bullet behaviors for shooting games, inspired by [BulletML](http://www.asahi-net.or.jp/~cs8k-cyu/bulletml/index_e.html).

The following is hypothesis, more of a desired end goal if you will.

 - A declarative language defining bullet types and a sequence of events taking place across their lifespan.
 - A particle system wrapper that carries out the events described. 
 
Triggering a Barrage invokes its "initial event", and from there on the game engine must relinquish control of the particle system to the Barrage as it carries out its logic. For this reason, particle systems intended to be used with Barrage must implement some interface to facilitate this.

Barrage scripts can be parsed at runtime from loaded files or (eventually) at compile-time using Haxe macros. The latter approach means any used barrage script would be checked for errors during build and there would be no overhead from interpretation.

Script expressions can call `rand()` for deterministic randomness when a seeded RNG is supplied to `run(...)`.

Targeting now supports named target selectors and dynamic bullet queries:

	target called hero is player
	target called nearest_seed is nearest bullet where type is seed
	set direction to aimed at nearest_seed over 0.1 seconds
	fire mybullet in aimed at hero direction 0

Language Features Overview
========

This is a quick capability summary. See `Language Spec (Current)` below for concrete syntax details.

- Structure model:
  - `barrage` root
  - `bullet` definitions (initial properties + optional attached action)
  - `action` definitions (event timelines)
  - `target` aliases for reusable aiming selectors
- Event/control model:
  - `fire`, `wait`, `set`, `increment`, `die`/`vanish`
  - `repeat <n> times`, `repeat forever`
  - nested `do action` blocks
  - action references with per-call overrides
- Aiming/space modifiers:
  - `absolute`, `relative`, `incremental`, `aimed`
  - `aimed at <target>` on direction operations
  - vector spawn offsets (`from ... position [x,y]`)
- Targeting:
  - built-ins: `player`, `parent`, `self`
  - aliases via `target called ...`
  - dynamic query: `nearest bullet where type is <name>`
- Expression system:
  - constants + folded constant math in parens
  - scripted numeric expressions in parens
  - scripted vector components (`[(expr),(expr)]`)
  - deterministic `rand()` via injected/seeded RNG
  - native math functions (`Math.sin`, `Math.atan2`, `Math.pow`, etc.)
- Runtime behavior:
  - deterministic default RNG (`SeededRng(0)`)
  - `onComplete` when actions finish
  - bullets continue simulating after action completion
  - runner idles only when both actions and bullets are done
- Tooling:
  - parse/grammar/runtime tests in `tests/TestMain.hx`
  - benchmark profiles in the same harness
  - optional C++ benchmark build target via `benchmark-cpp.hxml`

Authoring Guide (Practical)
========

Use this as a quick manual for writing maintainable barrages.

- Start with this skeleton:

	barrage called my_pattern
		bullet called pellet
			speed is 150
		action called start
			fire pellet in aimed direction 0

- Split intent by action role:
  - `start`: entrypoint / scheduling
  - helper actions: one behavior each (ring, burst, chase, pause)
  - bullet-attached actions: per-bullet long-lived behaviors
- Prefer explicit target aliases for readability:
  - `target called hero is player`
  - `set direction to aimed at hero over 0.2 seconds`
- Use modifiers consistently:
  - `absolute`: world-space value
  - `relative`: relative to current owner/origin context
  - `incremental`: sequential offset from previous emitted/assigned value
  - `aimed`: compute direction to a target, then apply offset
- Keep timelines legible:
  - pair burst blocks with waits (`fire ...`, then `wait ...`)
  - isolate repeating blocks in helper actions
  - use named override properties instead of duplicating action bodies
- Recommended pattern composition:
  - base lane pressure: aimed bursts + cooldown
  - area denial: periodic radial rings
  - trap pressure: delayed retargeting bullets
  - combine with staggered waits for layered difficulty
- Determinism tips:
  - inject a known seed for reproducible replays/tests
  - keep randomness in explicit expressions (`rand()*spread`)
  - verify digest outputs in tests when changing grammar/runtime
- Common failure modes:
  - unknown action/bullet references
  - unsupported expressions (parser throws)
  - mistaken relative vs incremental semantics in `fire` clauses
  - finite `start` action without restart logic in game loop

Language
========
The following describes a bullet system where the initial action fires a slow bullet towards the player that "bursts" 6 times into a circular spread of more bullets before disappearing. The spawned bullets first spread, then gradually form into "waves" that flow towards the player. 

	# Comments are prefixed with pound sign

	# A Barrage has a starting Action that results in bullets being created
	# Actions can have sub-actions
	# Bullets can trigger actions
	# Actions triggered by bullets use the bullet's position as origin
	
	# Barrage root declaration
	barrage called waveburst
		# Define and name a bullet.
		# This bullet initially moves backwards, but accelerates towards a positive velocity
		bullet called offspring
			speed is -100
			acceleration is 150
			# This bullet action waits a second before turning towards the player
			do action
				wait 1 seconds
				set direction to aimed over 1 seconds
	
		# This is our base bullet
		bullet called source
			speed is 100
			do action
				# This action immediately triggers a sub-action
				do action
					# fires 6 360 degree spreads of 11 bullets, one every quarter second
					wait 0.25 seconds
					# Math expressions in parentheses are evaluated to constants at build time 
					fire offspring in aimed direction (360/10*0.5)
					do action
						fire offspring in incremental direction (360/10)
						repeat 10 times
					repeat 6 times
				# wait for the sub-action to complete..
				wait (6*0.25) seconds
				# then die 
				die
	
		# Barrage entry point. Every barrage must have a start action 
		action called start
			# Fire a source bullet directly towards the player 
			fire source in aimed direction 0

Language Spec (Current)
========

Indentation + comments

- Indentation is tab-based (`\t`) and defines block structure.
- Comments start with `#` and can appear inline.

Top-level declarations

- `barrage called <name>`
- `bullet called <name>`
- `action called <name>`
- `target called <alias> is <target expression>`

Supported target expressions

- `player`
- `parent`
- `self`
- `<target alias>` (references a previously declared alias)
- `nearest bullet where type is <bulletName>`

Action references

- `do <actionName>`
- Overrides are allowed inside a referenced action block:
  - `do helper`
  - `\tmyoverride is 7`

Core statements

- Wait:
  - `wait <expr> frames`
  - `wait <expr> seconds`
- Repeat:
  - `repeat <expr> times`
  - `repeat forever`
- End current bullet:
  - `die`
  - `vanish` (alias of `die`)
- Property initialization (inside `bullet` or `action`):
  - `<identifier> is <expr>`
  - `speed is <expr>`
  - `direction is <expr>`
  - `acceleration is <expr>`
- Property set/increment:
  - `set <speed|direction|acceleration> to <expr|aimed>`
  - `increment <speed|direction|acceleration> by <expr|aimed>`
  - Timed variants:
    - `... over <expr> frames`
    - `... over <expr> seconds`
  - Aimed target form:
    - `set direction to aimed at <targetExpr> [over ...]`
    - `increment direction by aimed at <targetExpr> [over ...]`

Fire statement

- Base:
  - `fire <bulletName> ...`
- Optional clauses (order-independent by 4-token groups):
  - `at <absolute|relative|incremental> speed <expr>`
  - `in <absolute|relative|incremental|aimed> direction <expr>`
  - `in aimed at <targetExpr> direction <expr>`
  - `from <absolute|relative|incremental|aimed> position <vectorExpr>`
  - `with <absolute|relative|incremental> acceleration <expr>`
- If direction is omitted, default is aimed at `player`.

Expressions

- Numeric literals and constant math in parentheses are supported and folded when possible:
  - `(360/10*0.5)`
- Script expressions are parenthesized and evaluated natively in the VM.
- Supported operators: `+`, `-`, `*`, `/`, unary minus.
- Supported functions (case-insensitive with `Math.` or `math.` prefixes):
  - `sin`, `cos`, `tan`, `abs`, `sqrt`, `floor`, `ceil`, `round`, `exp`, `log`
  - `asin`, `acos`, `atan`, `pow`, `min`, `max`, `atan2`
- Supported constants:
  - `PI`, `Math.PI`, `math.PI`
  - `E`, `Math.E`, `math.E`
- `rand()` is supported and uses Barrage's seeded RNG.
- Unsupported grammar throws parse errors (for example, `fire x in random direction 0`).

Vector expressions

- Literal vector: `[x,y]`
- Scripted components: `[(expr),(expr)]`
- Example:
  - `from relative position [(repeatCount*10), (1 + repeatCount)]`

Runtime semantics

- `run(...)` uses VM execution and defaults to deterministic RNG (`SeededRng(0)`).
- `onComplete` fires when action execution finishes.
- Bullets continue simulating after actions complete; bullet lifetime is independent from script/action lifetime.
- Runner becomes inactive only after actions are complete and all bullets are gone (or killed externally).

Implementation
========

Barrage as an engine can be considered a "particle governor" in that it needs access to emission and removal functions as well as the properties of each bullet created. Thus, it needs to be mapped against an emitter that implements the `IBulletEmitter` interface, which needs to return bullets implementing the `IBarrageBullet` interface. When a Barrage is "run", a RunningBarrage instance is created which needs to be updated with an identical delta (in seconds) to the particle system. 

The following example code demonstrates this relationship.

	//Init
	var b = Barrage.fromString(sourceCode); 
	var runningBarrage = b.run(emitter); // defaults to a deterministic seeded RNG
	// or inject your own rng: b.run(emitter, 1.0, 1.0, new SeededRng(123));
	runningBarrage.onComplete = onBarrageComplete;
	runningBarrage.start();

	//Update
	runningBarrage.update(deltaSeconds);
	emitter.update(deltaSeconds);

This implementation is still in development. It's necessary for the emitter to be updated separately from the barrage, since an emitter typically won't be exclusive to barrage use.

Web IDE Preview
========

A lightweight local script IDE with live canvas preview is available in `tools/ide-web`.

Build and run instructions: `tools/ide-web/README.md`

Benchmark Targets
========

Run the existing test+benchmark harness in interpreter mode:

	haxe test.hxml

Build a native C++ benchmark/test binary (HXCPP):

	haxelib install hxcpp
	haxe benchmark-cpp.hxml

Then run:

	bin/cpp-benchmark/TestMain

IR Compile + AOT Packaging
========

The runtime now exposes a compiled program layer:

	// JIT compile and cache IR by source text
	var compiled = Barrage.compileString(sourceCode);

	// Optional AOT-style package (versioned payload)
	var bytes = Barrage.compileStringToBytes(sourceCode);
	var loadedBarrage = Barrage.fromCompiledBytes(bytes);

	// Run loaded barrage as usual
	var runner = loadedBarrage.run(emitter);

Current AOT payload stores source in a stable envelope and rebuilds IR on load.
