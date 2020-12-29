package gmdebug.lua;

import gmdebug.lua.Handlers;

interface IHandler<T:Request<Dynamic>> {
    
    function handle(req:T):HandlerResponse; 

}
