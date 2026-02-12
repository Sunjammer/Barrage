package barrage.data.targets;

enum TargetSelector {
	PLAYER;
	PARENT;
	SELF;
	NEAREST_BULLET_TYPE(typeName:String);
	TARGET_ALIAS(name:String);
}
