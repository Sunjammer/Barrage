package ide;

import barrage.Barrage;
import barrage.instancing.IBarrageBullet;
import barrage.instancing.IBulletEmitter;
import barrage.instancing.RunningBarrage;
import barrage.instancing.SeededRng;
import js.Browser;
import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.InputElement;
import js.html.KeyboardEvent;
import js.html.MouseEvent;
import js.html.PreElement;
import js.html.SelectElement;
import js.html.TextAreaElement;

class Main {
	static final FIXED_DT = 1.0 / 60.0;
	static final PRESETS:Array<{name:String, script:String}> = [
		{name: "Waveburst", script: Scripts.waveburst},
		{name: "Inchworm", script: Scripts.inchworm},
		{name: "Swarm", script: Scripts.swarm},
		{name: "Multitarget Demo", script: Scripts.multitarget},
		{name: "Exhaustive Stress", script: Scripts.exhaustive},
		{name: "Dev Sandbox", script: Scripts.dev}
	];

	static var editor:TextAreaElement;
	static var highlightEl:PreElement;
	static var statusEl:js.html.Element;
	static var presetEl:SelectElement;
	static var seedEl:InputElement;
	static var speedEl:InputElement;
	static var autoRestartEl:InputElement;
	static var playPauseEl:js.html.ButtonElement;
	static var canvas:CanvasElement;
	static var ctx:CanvasRenderingContext2D;

	static var emitter:PreviewEmitter;
	static var running:Null<RunningBarrage>;
	static var playing = true;
	static var simSpeed = 1.0;
	static var lastTs = 0.0;
	static var accumulator = 0.0;
	static var debounceHandle:Null<Int>;
	static var draggingTarget = false;
	static var completionIdleTime = 0.0;

	static function main():Void {
		editor = cast Browser.document.getElementById("editor");
		highlightEl = cast Browser.document.getElementById("highlight");
		statusEl = Browser.document.getElementById("status");
		presetEl = cast Browser.document.getElementById("preset");
		seedEl = cast Browser.document.getElementById("seed");
		speedEl = cast Browser.document.getElementById("speed");
		autoRestartEl = cast Browser.document.getElementById("autoRestart");
		playPauseEl = cast Browser.document.getElementById("playPause");
		canvas = cast Browser.document.getElementById("preview");
		ctx = cast canvas.getContext2d();

		emitter = new PreviewEmitter();
		wireUi();
		loadPresets();
		editor.value = PRESETS[0].script;
		updateHighlight();
		rebuild();
		Browser.window.requestAnimationFrame(loop);
	}

	static function wireUi():Void {
		editor.oninput = function(_) {
			updateHighlight();
			if (debounceHandle != null) {
				Browser.window.clearTimeout(debounceHandle);
			}
			debounceHandle = Browser.window.setTimeout(function() {
				rebuild();
			}, 250);
		};
		editor.onscroll = function(_) {
			highlightEl.scrollTop = editor.scrollTop;
			highlightEl.scrollLeft = editor.scrollLeft;
		};
		editor.onkeydown = function(ev:KeyboardEvent) {
			if (ev.key != "Tab")
				return;
			ev.preventDefault();
			insertTabAtCursor();
		};

		cast(Browser.document.getElementById("loadPreset"), js.html.ButtonElement).onclick = function(_) {
			final idx = presetEl.selectedIndex;
			if (idx >= 0 && idx < PRESETS.length) {
				editor.value = PRESETS[idx].script;
				updateHighlight();
				rebuild();
			}
		};

		cast(Browser.document.getElementById("rebuild"), js.html.ButtonElement).onclick = function(_) {
			rebuild();
		};
		cast(Browser.document.getElementById("reset"), js.html.ButtonElement).onclick = function(_) {
			rebuild();
		};
		cast(Browser.document.getElementById("step"), js.html.ButtonElement).onclick = function(_) {
			tick(FIXED_DT);
			render();
		};
		playPauseEl.onclick = function(_) {
			playing = !playing;
			playPauseEl.textContent = playing ? "Pause" : "Play";
		};

		seedEl.onchange = function(_) {
			rebuild();
		};
		speedEl.onchange = function(_) {
			final parsed = Std.parseFloat(speedEl.value);
			if (!Math.isNaN(parsed) && parsed > 0) {
				simSpeed = parsed;
			}
		};

		inline function updateTargetFromMouse(ev:MouseEvent):Void {
			final rect = canvas.getBoundingClientRect();
			final scaleX = canvas.width / rect.width;
			final scaleY = canvas.height / rect.height;
			final mx = (ev.clientX - rect.left) * scaleX;
			final my = (ev.clientY - rect.top) * scaleY;
			emitter.playerX = mx - canvas.width * 0.5;
			emitter.playerY = my - canvas.height * 0.5;
		}

		canvas.onmousedown = function(ev:MouseEvent) {
			draggingTarget = true;
			updateTargetFromMouse(ev);
		};

		canvas.onmousemove = function(ev:MouseEvent) {
			if (!draggingTarget)
				return;
			updateTargetFromMouse(ev);
		};

		Browser.window.onmouseup = function(_) {
			if (!draggingTarget)
				return;
			draggingTarget = false;
			rebuild();
		};
	}

	static function loadPresets():Void {
		for (preset in PRESETS) {
			final option = Browser.document.createOptionElement();
			option.text = preset.name;
			presetEl.add(option);
		}
	}

	static function rebuild():Void {
		final seed = Std.parseInt(seedEl.value);
		final safeSeed = seed == null ? 1 : seed;
		emitter.reset();
		completionIdleTime = 0;
		try {
			final barrage = Barrage.fromString(editor.value, false);
			running = barrage.run(emitter, 1.0, 1.0, new SeededRng(safeSeed));
			running.onComplete = function(_) {
				completionIdleTime = 0;
			};
			running.start();
			setStatus('Parsed OK. Barrage: ${barrage.name}', true);
		} catch (e:Dynamic) {
			running = null;
			setStatus("Parse/runtime error: " + Std.string(e), false);
		}
	}

	static function updateHighlight():Void {
		highlightEl.innerHTML = highlightScript(editor.value);
	}

	static function insertTabAtCursor():Void {
		final start = editor.selectionStart;
		final end = editor.selectionEnd;
		final value = editor.value;
		editor.value = value.substring(0, start) + "\t" + value.substring(end);
		editor.selectionStart = start + 1;
		editor.selectionEnd = start + 1;
		updateHighlight();
		if (debounceHandle != null) {
			Browser.window.clearTimeout(debounceHandle);
		}
		debounceHandle = Browser.window.setTimeout(function() {
			rebuild();
		}, 250);
	}

	static function highlightScript(source:String):String {
		final lines = source.split("\n");
		final out = new Array<String>();
		for (line in lines) {
			final commentIdx = line.indexOf("#");
			if (commentIdx == -1) {
				out.push(highlightCode(line));
			} else {
				final code = line.substr(0, commentIdx);
				final comment = line.substr(commentIdx);
				out.push(highlightCode(code) + '<span class="com">' + escapeHtml(comment) + "</span>");
			}
		}
		return out.join("\n");
	}

	static function highlightCode(code:String):String {
		var html = escapeHtml(code);
		html = ~/\([^)\n]*\)/g.map(html, function(re) return '<span class="expr">' + re.matched(0) + "</span>");
		html = ~/\b-?\d+(?:\.\d+)?\b/g.map(html, function(re) return '<span class="num">' + re.matched(0) + "</span>");

		final keywords = [
			"barrage", "bullet", "action", "start", "do", "fire", "set", "increment", "wait", "repeat", "die", "vanish", "called", "is", "to", "over",
			"in", "at", "from", "with", "speed", "direction", "acceleration", "position", "absolute", "relative", "incremental", "aimed", "seconds",
			"frames", "forever", "target", "player", "parent", "self", "nearest", "where", "type"
		];
		for (kw in keywords) {
			final reg = new EReg("\\b" + kw + "\\b", "g");
			html = reg.map(html, function(re) return '<span class="kw">' + re.matched(0) + "</span>");
		}
		return html;
	}

	static function escapeHtml(v:String):String {
		return v.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");
	}

	static function loop(ts:Float):Void {
		if (lastTs == 0) {
			lastTs = ts;
		}
		final delta = (ts - lastTs) / 1000.0;
		lastTs = ts;
		accumulator += delta * simSpeed;

		var safety = 0;
		while (accumulator >= FIXED_DT && safety++ < 6) {
			if (playing) {
				tick(FIXED_DT);
			}
			accumulator -= FIXED_DT;
		}

		render();
		Browser.window.requestAnimationFrame(loop);
	}

	static function tick(dt:Float):Void {
		if (running != null) {
			running.update(dt);
		}
		emitter.setCullBounds(canvas.width * 0.5, canvas.height * 0.5);
		emitter.update(dt);
		updateAutoRestart(dt);
	}

	static function updateAutoRestart(dt:Float):Void {
		if (!autoRestartEl.checked)
			return;
		if (running == null)
			return;
		final idle = emitter.activeCount() == 0 && running.activeActions.length == 0;
		if (!idle) {
			completionIdleTime = 0;
			return;
		}
		completionIdleTime += dt;
		if (completionIdleTime >= 1.0) {
			rebuild();
		}
	}

	static function render():Void {
		ctx.setTransform(1, 0, 0, 1, 0, 0);
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		ctx.fillStyle = "#0b1016";
		ctx.fillRect(0, 0, canvas.width, canvas.height);

		ctx.translate(canvas.width * 0.5, canvas.height * 0.5);

		// Crosshair for player target.
		ctx.strokeStyle = "#58c4ff";
		ctx.lineWidth = 1;
		ctx.beginPath();
		ctx.moveTo(emitter.playerX - 8, emitter.playerY);
		ctx.lineTo(emitter.playerX + 8, emitter.playerY);
		ctx.moveTo(emitter.playerX, emitter.playerY - 8);
		ctx.lineTo(emitter.playerX, emitter.playerY + 8);
		ctx.stroke();

		// Emitter origin.
		ctx.fillStyle = "#ffd166";
		ctx.beginPath();
		ctx.arc(emitter.posX, emitter.posY, 4, 0, Math.PI * 2);
		ctx.fill();

		for (b in emitter.bullets) {
			if (!b.active) continue;
			final hue = (b.id * 53) % 360;
			ctx.fillStyle = 'hsl(${hue}, 85%, 62%)';
			ctx.beginPath();
			ctx.arc(b.posX, b.posY, 2.5, 0, Math.PI * 2);
			ctx.fill();
		}

		ctx.setTransform(1, 0, 0, 1, 0, 0);
		ctx.fillStyle = "#8ca0b5";
		ctx.fillText('Bullets: ${emitter.activeCount()}', 12, canvas.height - 16);
		if (running != null) {
			ctx.fillText('Time: ${Std.string(Std.int(running.time * 1000) / 1000)}s', 110, canvas.height - 16);
		}
	}

	static function setStatus(msg:String, ok:Bool):Void {
		statusEl.textContent = msg;
		statusEl.className = ok ? "ok" : "error";
	}
}

private class PreviewEmitter implements IBulletEmitter {
	public var posX:Float = 0;
	public var posY:Float = 0;

	public var playerX:Float = 200;
	public var playerY:Float = 0;
	public var bullets:Array<PreviewBullet> = [];
	public var cullHalfW:Float = 480;
	public var cullHalfH:Float = 360;
	public var offscreenKillDelay:Float = 1.0;

	var nextId:Int = 1;

	public function new() {}

	public function emit(x:Float, y:Float, angleRad:Float, speed:Float, acceleration:Float, delta:Float):IBarrageBullet {
		final b = new PreviewBullet(nextId++, x, y, angleRad, speed, acceleration);
		bullets.push(b);
		return b;
	}

	public function getAngleToEmitter(fromX:Float, fromY:Float):Float {
		final dx = posX - fromX;
		final dy = posY - fromY;
		return Math.atan2(dy, dx) * 180.0 / Math.PI;
	}

	public function getAngleToPlayer(fromX:Float, fromY:Float):Float {
		final dx = playerX - fromX;
		final dy = playerY - fromY;
		return Math.atan2(dy, dx) * 180.0 / Math.PI;
	}

	public function kill(bullet:IBarrageBullet):Void {
		bullet.active = false;
	}

	public function update(dt:Float):Void {
		for (b in bullets) {
			if (!b.active) continue;
			final outOfBounds = Math.abs(b.posX) > cullHalfW || Math.abs(b.posY) > cullHalfH;
			if (outOfBounds) {
				b.offscreenTime += dt;
				if (b.offscreenTime > offscreenKillDelay) {
					b.active = false;
				}
			} else {
				b.offscreenTime = 0;
			}
		}
	}

	public inline function setCullBounds(halfW:Float, halfH:Float):Void {
		cullHalfW = halfW;
		cullHalfH = halfH;
	}

	public function reset():Void {
		bullets = [];
		nextId = 1;
	}

	public function activeCount():Int {
		var c = 0;
		for (b in bullets) if (b.active) c++;
		return c;
	}
}

private class PreviewBullet implements IBarrageBullet {
	public var acceleration:Float;
	public var velocityX:Float;
	public var velocityY:Float;
	public var angle:Float;
	public var speed:Float;
	public var active:Bool;
	public var id:Int;
	public var posX:Float;
	public var posY:Float;
	public var offscreenTime:Float;

	public function new(id:Int, x:Float, y:Float, angle:Float, speed:Float, acceleration:Float) {
		this.id = id;
		this.posX = x;
		this.posY = y;
		this.angle = angle;
		this.speed = speed;
		this.acceleration = acceleration;
		this.velocityX = 0;
		this.velocityY = 0;
		this.active = true;
		this.offscreenTime = 0;
	}
}

private class Scripts {
	public static final waveburst = "# Comments are prefixed with pound sign\n"
		+ "\n"
		+ "# A Barrage has a starting Action that results in bullets being created\n"
		+ "# Actions can have sub-actions\n"
		+ "# Bullets can trigger actions\n"
		+ "# Actions triggered by bullets use the bullet's position as origin\n"
		+ "\n"
		+ "# Barrage root declaration\n"
		+ "barrage called waveburst\n"
		+ "\tbullet called offspring\n"
		+ "\t\tspeed is -100\n"
		+ "\t\tacceleration is 150\n"
		+ "\t\tdo action\n"
		+ "\t\t\twait 1 seconds\n"
		+ "\t\t\tset direction to aimed over 1 seconds\n"
		+ "\tbullet called source\n"
		+ "\t\tspeed is 100\n"
		+ "\t\tdo action\n"
		+ "\t\t\tdo action\n"
		+ "\t\t\t\twait 0.25 seconds\n"
		+ "\t\t\t\tfire offspring in aimed direction (360/10*0.5)\n"
		+ "\t\t\t\tdo action\n"
		+ "\t\t\t\t\tfire offspring in incremental direction (360/10)\n"
		+ "\t\t\t\t\trepeat 10 times\n"
		+ "\t\t\t\trepeat 6 times\n"
		+ "\t\t\twait (6*0.25) seconds\n"
		+ "\t\t\tdie\n"
		+ "\taction called start\n"
		+ "\t\tfire source in aimed direction 0\n";

	public static final inchworm = "# Inchworm pattern:\n"
		+ "# - \"wormsegment\" bullets oscillate speed while curving\n"
		+ "# - \"worm\" action emits a circular chain with a rotating phase offset\n"
		+ "\n"
		+ "barrage called inchworm\n"
		+ "\tbullet called wormsegment\n"
		+ "\t\tspeed is 100\n"
		+ "\t\tdo action\n"
		+ "\t\t\tincrement direction by 10 over 1 seconds\n"
		+ "\t\t\tset speed to 0\n"
		+ "\t\t\twait 0.5 seconds\n"
		+ "\t\t\tset speed to 100\n"
		+ "\t\t\twait 0.5 seconds\n"
		+ "\t\t\trepeat 7 times\n"
		+ "\n"
		+ "\taction called worm\n"
		+ "\t\tmyvalue is 0\n"
		+ "\t\tfire wormsegment in absolute direction (myvalue)\n"
		+ "\t\tdo action\n"
		+ "\t\t\tfire wormsegment in incremental direction (360/30)\n"
		+ "\t\t\trepeat 29 times\n"
		+ "\t\twait 0.1 seconds\n"
		+ "\t\trepeat 4 times\n"
		+ "\n"
		+ "\taction called start\n"
		+ "\t\tdo worm\n"
		+ "\t\t\tmyvalue is (repeatCount*6)\n"
		+ "\t\twait 1 seconds\n"
		+ "\t\trepeat 4 times\n";

	public static final swarm = "# Swarm pattern:\n"
		+ "# - \"seed\" bullets fan out from the center\n"
		+ "# - each seed pauses and bursts \"homer\" bullets\n"
		+ "# - homers continuously re-aim while accelerating\n"
		+ "\n"
		+ "barrage called swarm\n"
		+ "\tbullet called homer\n"
		+ "\t\tdo action\n"
		+ "\t\t\tset speed to 0 over 0.7 seconds\n"
		+ "\t\t\twait 0.7 seconds\n"
		+ "\t\t\tdo action\n"
		+ "\t\t\t\tset direction to aimed over 0.1 seconds\n"
		+ "\t\t\t\twait 0.1 seconds\n"
		+ "\t\t\t\trepeat forever\n"
		+ "\t\t\tset speed to 800 over 2 seconds\n"
		+ "\tbullet called seed\n"
		+ "\t\tspeed is 180\n"
		+ "\t\tdo action\n"
		+ "\t\t\tset speed to 0 over 60 frames\n"
		+ "\t\t\twait 60 frames\n"
		+ "\t\t\tdo action\n"
		+ "\t\t\t\tfire homer at absolute speed (50 + rand()*80) in aimed direction (-180 + (rand()-0.5)*2*45)\n"
		+ "\t\t\t\trepeat 8 times\n"
		+ "\t\t\tdie\n"
		+ "\taction called start\n"
		+ "\t\tfire seed in aimed direction 90\n"
		+ "\t\tdo action\n"
		+ "\t\t\twait 0.1 seconds\n"
		+ "\t\t\tfire seed in incremental direction (180/16)\n"
		+ "\t\t\trepeat 16 times\n";

	public static final multitarget = "barrage called multitarget_demo\n"
		+ "\ttarget called hero is player\n"
		+ "\ttarget called parent_source is parent\n"
		+ "\ttarget called nearest_seed is nearest bullet where type is seed\n"
		+ "\tbullet called seeker_player\n"
		+ "\t\tspeed is 180\n"
		+ "\t\tdo action\n"
		+ "\t\t\tset direction to aimed at hero over 0.15 seconds\n"
		+ "\t\t\twait 0.15 seconds\n"
		+ "\t\t\trepeat forever\n"
		+ "\tbullet called seeker_parent\n"
		+ "\t\tspeed is 140\n"
		+ "\t\tdo action\n"
		+ "\t\t\tset direction to aimed at parent_source over 0.1 seconds\n"
		+ "\t\t\twait 0.1 seconds\n"
		+ "\t\t\trepeat forever\n"
		+ "\tbullet called seed\n"
		+ "\t\tspeed is 90\n"
		+ "\t\tdo action\n"
		+ "\t\t\twait 0.4 seconds\n"
		+ "\t\t\tfire seeker_player in aimed at hero direction 0\n"
		+ "\t\t\tfire seeker_parent in aimed at parent_source direction 0\n"
		+ "\t\t\twait 0.4 seconds\n"
		+ "\t\t\trepeat 6 times\n"
		+ "\tbullet called hunter\n"
		+ "\t\tspeed is 160\n"
		+ "\t\tdo action\n"
		+ "\t\t\tset direction to aimed at nearest_seed over 0.1 seconds\n"
		+ "\t\t\twait 0.1 seconds\n"
		+ "\t\t\trepeat forever\n"
		+ "\taction called start\n"
		+ "\t\tfire seed in aimed at hero direction 0\n"
		+ "\t\tdo action\n"
		+ "\t\t\tfire seed in incremental direction (360/8)\n"
		+ "\t\t\trepeat 7 times\n"
		+ "\t\twait 0.5 seconds\n"
		+ "\t\tfire hunter in aimed at nearest_seed direction 0\n"
		+ "\t\tdo action\n"
		+ "\t\t\tfire hunter in incremental direction (360/5)\n"
		+ "\t\t\trepeat 4 times\n";

	public static final dev = "# Development sandbox pattern:\n"
		+ "# - demonstrates relative/incremental spawn positions\n"
		+ "# - demonstrates absolute/incremental acceleration modifiers\n"
		+ "\n"
		+ "barrage called dev\n"
		+ "\tbullet called mybullet\n"
		+ "\t\tspeed is 100\n"
		+ "\n"
		+ "\taction called start\n"
		+ "\t\tfire mybullet from relative position [10,0] with absolute acceleration 100\n"
		+ "\t\tdo action\n"
		+ "\t\t\twait 0.1 seconds\n"
		+ "\t\t\tfire mybullet from incremental position [10,0] with incremental acceleration -50\n"
		+ "\t\t\trepeat 30 times\n";

	public static final exhaustive = "# Exhaustive stress pattern:\n"
		+ "# - target aliases (player / parent / nearest bullet type)\n"
		+ "# - scripted constants + rand() expressions\n"
		+ "# - relative/incremental/aimed modifiers\n"
		+ "# - property set + tween + increment statements\n"
		+ "# - action references with property overrides\n"
		+ "# - nested loops with bounded repeat counts for benchmarking\n"
		+ "\n"
		+ "barrage called exhaustive_stress\n"
		+ "\ttarget called hero is player\n"
		+ "\ttarget called parent_source is parent\n"
		+ "\ttarget called nearest_anchor is nearest bullet where type is anchor\n"
		+ "\n"
		+ "\tbullet called shard\n"
		+ "\t\tspeed is (20 + rand()*40)\n"
		+ "\t\tacceleration is -4\n"
		+ "\t\tdo action\n"
		+ "\t\t\tincrement direction by 15 over 5 frames\n"
		+ "\t\t\twait 5 frames\n"
		+ "\t\t\tset direction to aimed at hero over 6 frames\n"
		+ "\t\t\tset speed to 120 over 20 frames\n"
		+ "\t\t\twait 12 frames\n"
		+ "\t\t\tdie\n"
		+ "\n"
		+ "\tbullet called anchor\n"
		+ "\t\tspeed is (30 + rand()*20)\n"
		+ "\t\tdirection is (rand()*360)\n"
		+ "\t\tacceleration is -1\n"
		+ "\t\tdo action\n"
		+ "\t\t\twait 8 frames\n"
		+ "\t\t\tfire shard in aimed at parent_source direction 0 with incremental acceleration 2\n"
		+ "\t\t\twait 4 frames\n"
		+ "\t\t\tset speed to 0 over 6 frames\n"
		+ "\t\t\twait 6 frames\n"
		+ "\t\t\tset speed to 40\n"
		+ "\t\t\trepeat 3 times\n"
		+ "\t\t\tdie\n"
		+ "\n"
		+ "\taction called burst\n"
		+ "\t\tspread is (360/7)\n"
		+ "\t\tfire shard from relative position [8,0] in aimed at hero direction (-spread*0.5) with relative acceleration -1\n"
		+ "\t\tdo action\n"
		+ "\t\t\tfire shard from incremental position [2,0] in incremental direction (spread)\n"
		+ "\t\t\trepeat 6 times\n"
		+ "\t\twait 8 frames\n"
		+ "\n"
		+ "\taction called cycle\n"
		+ "\t\tfire anchor in aimed at hero direction (repeatCount*11)\n"
		+ "\t\tdo burst\n"
		+ "\t\t\tspread is (24 + repeatCount*2)\n"
		+ "\t\twait 3 frames\n"
		+ "\t\tfire anchor from relative position [10,0] in aimed at nearest_anchor direction (-repeatCount*11)\n"
		+ "\t\trepeat 12 times\n"
		+ "\n"
		+ "\taction called start\n"
		+ "\t\tdo cycle\n"
		+ "\t\twait 2 seconds\n"
		+ "\t\trepeat 3 times\n";
}
