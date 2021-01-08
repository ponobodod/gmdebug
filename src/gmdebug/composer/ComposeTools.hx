package gmdebug.composer;

class ComposeTools {
	/**
		Compose a response
		RequestString is not physically used, but ensures response is type checked
	**/
	public static function compose<X, Y>(req:Request<X>, str:RequestString<Request<X>, Response<Y>>, ?body:Y):ComposedResponse<Null<Y>> {
		// return ;
		var response = new ComposedResponse(req, body);
		response.success = true;
		return response;
	}

	public static function composeFail<X, Y>(req:Request<X>, ?rawerror:String, ?error:Message):ComposedResponse<Null<Message>> {
		var response = new ComposedResponse(req, error);
		response.message = rawerror;
		response.success = false;
		return response;
	}

	
}
