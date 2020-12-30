
class HContinue implements IHandler<ContinueRequest> {

    public function new() {

    }
    
    public function handle(pause:ContinueRequest):HandlerResponse {
        var resp = req.compose(_continue,{allThreadsContinued: false});
        resp.send();
        return CONTINUE;
    }
}