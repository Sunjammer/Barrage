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
		{name: "Swarm", script: Scripts.swarm},
		{name: "Multitarget Demo", script: Scripts.multitarget}
	];

	static var editor:TextAreaElement;
	static var highlightEl:PreElement;
	static var statusEl:js.html.Element;
	static var presetEl:SelectElement;
	static var seedEl:InputElement;
	static var speedEl:InputElement;
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

	static function main():Void {
		editor = cast Browser.document.getElementById("editor");
		highlightEl = cast Browser.document.getElementById("highlight");
		statusEl = Browser.document.getElementById("status");
		presetEl = cast Browser.document.getElementById("preset");
		seedEl = cast Browser.document.getElementById("seed");
		speedEl = cast Browser.document.getElementById("speed");
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
		try {
			final barrage = Barrage.fromString(editor.value, false);
			running = barrage.run(emitter, 1.0, 1.0, new SeededRng(safeSeed));
			running.onComplete = function(_) {};
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
		emitter.update(dt);
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
			b.speed += b.acceleration * dt;
			final a = b.angle * Math.PI / 180.0;
			b.velocityX = Math.cos(a) * b.speed;
			b.velocityY = Math.sin(a) * b.speed;
			b.posX += b.velocityX * dt;
			b.posY += b.velocityY * dt;
		}
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
	}
}

private class Scripts {
	public static final waveburst = "barrage called waveburst\n"
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

	public static final swarm = "barrage called swarm\n"
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
}
