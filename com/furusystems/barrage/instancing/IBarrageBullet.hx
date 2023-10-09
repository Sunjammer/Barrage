package com.furusystems.barrage.instancing;
/**
 * ...
 * @author Andreas Rønning
 */
interface IBarrageBullet extends IOrigin {
	var acceleration:Float;
	var velocityX:Float;
	var velocityY:Float;
	var angle:Float;
	var speed:Float;
	var active:Bool;
	var id:Int;
}
