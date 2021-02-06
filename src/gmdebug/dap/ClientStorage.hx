package gmdebug.dap;

typedef ReadFunc = (x:Buffer,id:Int) -> Void

typedef ClientID = Int
	
class ClientStorage {

	static final SERVER_ID = 0;

	final clients:Array<Client> = [];

	final clientGmodNameMap:Map<ClientID,String> = [];

	final readFunc:ReadFunc;

	public function new(readFunc:ReadFunc) {
		this.readFunc = readFunc; 
	}


	static function makeFifosIfNotExist(input:String, output:String) {
		if (!FileSystem.exists(input) && !FileSystem.exists(output)) {
			js.node.ChildProcess.execSync('mkfifo $input');
			js.node.ChildProcess.execSync('mkfifo $output');
			Fs.chmodSync(input, "744");
			Fs.chmodSync(output, "722");
		};
	}

	public function getClientGmodName() {
		return 
	}

	@:await public function newClient(gmodID:Int) {
		final data = haxe.io.Path.join([clientLoc, Cross.DATA]);
		final input = haxe.io.Path.join([data, Cross.INPUT]);
		final out = haxe.io.Path.join([data, Cross.OUTPUT]);
		makeFifosIfNotExist(input, out);
		final ready = haxe.io.Path.join([data, Cross.READY]);
		final readSock = @:await aquireReadSocket(out);
		final writeSock = @:await aquireWriteSocket(input);

		final client = new Client({readS : readSock, writeS : writeSock},{write : input,read : out});
		clients.push(client);
		sys.io.File.saveContent(ready, "");
		write.write("\004\r\n");
		new ComposedEvent(thread, {
			threadId: clientID,
			reason: Started
		}).send();
		
	}

	public function get(id:Int) {
		return clients[id];
	}

	public function sendServer() {
		clients[SERVER_ID].
	}

	public function sendClient(id:Int) {
		if (id == SERVER_ID) {
			throw "Attempt to send to server....";
		}
		
	}
}
