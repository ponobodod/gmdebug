package gmdebug.lua.handlers;

class HSetExceptionBreakpoints implements IHandler<SetExceptionBreakpointsRequest> {
	public function new() {}

	public function handle(x:SetExceptionBreakpointsRequest):HandlerResponse {
		var rep = x.compose(setExceptionBreakpoints);
		var gamemodeSet = false;
		var entitiesSet = false;
		for (filter in x.arguments.unsafe().filters) {
			switch (filter) {
				case gamemode:
					Exceptions.hookGamemodeHooks();
					gamemodeSet = true;
				case entities:
					Exceptions.hookEntityHooks();
					entitiesSet = true;
			}
		}
		if (!gamemodeSet)
			Exceptions.unhookGamemodeHooks();
		if (!entitiesSet)
			Exceptions.unhookEntityHooks();
		rep.send();
		return WAIT;
	}
}
