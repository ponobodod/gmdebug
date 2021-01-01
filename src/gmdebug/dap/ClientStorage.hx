package gmdebug.dap;

class ClientStorage {
	final clients:Array<Client> = []; // 0 = server.

	public function new() {}

	public function newClient() {}

	public function get(id:Int) {
		return clients[id];
	}
}
