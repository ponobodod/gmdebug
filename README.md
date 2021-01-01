# gmdebug
Gmod debugger using the debug adapter protocol made using haxe targeting lua and javascript. 
Can be run as a vscode extension or as a standalone server

## Features

- Conditional breakpoints targeting functions and lines
- Stepping
- Evaluation
- Support for debugging gmod clients and servers simultaneously as seperate threads (must be on same computer)
- Support for exceptions (only exceptions that can be caught by lua)

Currently only supports named pipe socket connections on linux, aim to support windows and perhaps networked connections in the future

## Usage

### Building for vscode

Run the following commands in the root folder

`haxe extension.hxml`

Then run

`haxe lua_server.hxml`

which should produce a `generated` folder, which is necessary for the lua side.

### Running the addon

You can run the addon built by opening the root directory in vscode. Open up a lua file and the debug section to get started

Be sure to set the `serverFolder` property to the right location, or it will be unable to connect





