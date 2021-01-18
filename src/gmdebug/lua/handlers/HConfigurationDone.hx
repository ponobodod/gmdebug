package gmdebug.lua.handlers;

class HConfigurationDone implements IHandler<ConfigurationDoneRequest> {

    public function new() {

    }

    public function handle(configRequest:ConfigurationDoneRequest) {
        var rep = configRequest.compose(configurationDone, {});
		rep.send();
		return CONFIG_DONE;
    }

}