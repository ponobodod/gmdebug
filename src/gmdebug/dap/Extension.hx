package gmdebug.dap;

import Vscode;
import vscode.DebugAdapterExecutable;
import vscode.DebugAdapterInlineImplementation;
import vscode.ProviderResult;
import vscode.DebugAdapterDescriptorFactory;

import vscode.Uri;
using tink.CoreApi;
using Lambda;
class Extension {

    @:expose("activate")
    static function activate(context:vscode.ExtensionContext) {
        trace("gmdebug activated");
	   
        Vscode.commands.registerCommand("extension.gmdebug.FilePicker", (config) -> {
            final selectedFolderP = Vscode.window.showOpenDialog({
                    canSelectFiles: false,
                    canSelectFolders: true,
            });  
            return selectedFolderP.then((arr) -> {return arr[0].toString();});
        });
	    
        final fact:DebugAdapterDescriptorFactory = new InlineDebugAdapterProvide();
        context.subscriptions.push(Vscode.debug.registerDebugAdapterDescriptorFactory("gmdebug",fact));
        // provideDebugConfigurations: () -> {
        // context.subscriptions.push(fact);
    }
    @:expose("deactivate")
    static function deactivate() {

    }
    @:expose("runMode")    
    static var runMode = "inline";

}

private class DebugConfigProvider {

    // public function provideDebugConfigurations(?folder:vscode.WorkspaceFolder,?token:vscode.CancellationToken) {
    //     return [{
    //         type: "gmdebug",
    //         name: "Attach",
    //         request: "attach",
    //         communicationMethod : "pipe", //pipe/file tbd/tcp
    //         gmodServerLocation : "path/to/garrysmod/server",
    //         gmodClientLocations : ["path/to/garrysmod/client/","otherpath"]
    //     }];
    // }

    public var resolveDebugConfiguration = null;

    public var resolveDebugConfigurationWithSubstitutedVariables = null;


    public function new() {

    }

}

private class InlineDebugAdapterProvide {
    public function createDebugAdapterDescriptor(session:vscode.DebugSession,?executable:DebugAdapterExecutable):ProviderResult<vscode.DebugAdapterDescriptor> {
        return cast new DebugAdapterInlineImplementation(cast new LuaDebugger());
    }

    public function new() {

    }
}

