package gmdebug;

typedef FrameIDValues = {
	clientID:Int,
	actualFrame:Int
}

abstract FrameID(Int) from Int to Int {
	public function getValue():FrameIDValues {
		final maskClientID = 0xF;
		final clientID = (this >>> 27);
		final actualFrame = (this & 0x7FFFFFF);
		return {
			clientID: clientID,
			actualFrame: actualFrame
		};
	}

	public static inline function encode(clientID:Int, frameID:Int) {
		final val = clientID << 27;
		return val | frameID;
	}
}
