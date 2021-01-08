package gmdebug.lua.handlers;
import gmdebug.lua.managers.VariableManager;


class HContinue implements IHandler<ContinueRequest> {
	public function new(vm:VariableManager) {
		variableManager = vm;
	}

	var variableManager:VariableManager;

	public function handle(contReq:ContinueRequest):HandlerResponse {
		var resp = contReq.compose(_continue, {allThreadsContinued: false});
		resp.send();
		variableManager.resetVariables();
		return CONTINUE;
	}
}
