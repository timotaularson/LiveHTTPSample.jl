module LiveHTTPSample

using HTTP
using JSON3
using Revise

include("LiveHTTP.jl")

# Configuration
ip_addr = "0.0.0.0"
http_port = 8080
websocket_port = 8081

# Main entry point to start the program
function main()
    println("URL: http://host:$http_port  websocket_port: $websocket_port")
    start_http_and_websocket_servers(ip_addr, http_port, http_router, websocket_port, websocket_router)
end

# Map HTTP URLs to functions
function http_router(request)
    route_http_request(request;
        public=Dict(
            "/"      => url_root,
            "/somepage" => url_somepage,
        ),
        public_path=Dict(
            "/static/" => url_static,
        )
    )
end

# Map WebSocket messages to functions
function websocket_router(websocket, request)
    route_websocket_request(websocket, request;
        public=Dict(
            "button_clicked" => ws_button_clicked,
            "error" => ws_error,
        ),
        private=Dict(
            "private" => ws_private,
        ),
        default=ws_default
    )
end

function ws_button_clicked(ws, request)
    println("Received button_clicked message from browser: ", request[:msg])
    write(ws, JSON3.write(Dict(:type=>"update_span", :msg=>request[:msg])))
end

function ws_private(ws, request)
    println("Received private message from browser: ", request[:msg])
end

function ws_error(ws, request)
    println("Received error message from browser: ", request[:msg])
end

function ws_default(ws, request)
    println("Server received unexpected message from browser: ", JSON3.write(request))
    write(ws, JSON3.write(Dict(:type=>"log", :msg=>"Unexpected message was sent to server")))
end

# Home Page
function url_root(request, sessionid)
    response(sessionid, 200, [], body="""
        <html>
            <head>
                <title>Home Page</title>
            </head>
            </body>
                <h1>Home Page</h1>
                <a href="/static/StaticPage.html">Static Page</a><br />
                <a href="/somepage">Some Page</a>
            </body>
        </html>
        """
    )
end

# Some Page
function url_somepage(request, sessionid)
    css = """
        body { background:lightgray; }
        """

    js = """
        var socket;

        window.addEventListener('load', function(event) {

            var elem = document.getElementById("clicked")
            elem.focus();

            console.log("Connecting websocket to " + location.hostname + "...");

            // Create WebSocket connection
            socket = new WebSocket('ws://' + location.hostname + ':$websocket_port');

            // Connection opened
            socket.addEventListener('open', function (event) {
                console.log("Websocket connected");
            });

            // Listen for messages
            socket.addEventListener('message', function (event) {
                var request = JSON.parse(event.data);
                switch(request.type) {
                    case 'update_span':
                        ws_update_span(request);
                        break;
                    case 'log':
                        console.log("Msg: ", request.msg);
                        break;
                    case 'alert':
                        alert("Msg: " + request.msg);
                        break;
                    case 'error':
                        console.log("Error: ", request.msg);
                        break;
                    default:
                        console.log("Server sent an unexpected message to browser: ", request);
                }
            });
        });

        window.addEventListener('unload', function(event) {
            socket.close();
        });

        function button_onclick() {
            console.log("Sending button_clicked message to server");
            socket.send(JSON.stringify({'type': 'button_clicked', 'msg': event.target.innerHTML}));
        }

        function ws_update_span(request) {
            console.log("Received update_span message from server");
            var clicked = document.getElementById('clicked');
            clicked.value = 'You clicked ' + request.msg;
        }
        """

    html = """
        <html>
            <head>
                <title>Some Page</title>
                <style>
                <!--
                $css
                -->
                </style>
                <script>
                <!--
                $js
                -->
                </script>
            </head>
            </body>
            <h1>Some Page</h1>
            <a href="/">Home</a><br />
            <a href="/static/StaticPage.html">Static Page</a><br />
            <br />
            <input id="clicked"></input><br />
            <br />
            <button id="button1" onclick="button_onclick();">Button 1</button>
            <button id="button2" onclick="button_onclick();">Button 2</button>
            </body>
        </html>
        """

    response(sessionid, 200, [], body=html)
end

function url_static(request, path, sessionid)
    pkg_path = joinpath((splitpath(@__DIR__)[1:end-1])...)
    path = url_to_path(path, joinpath(pkg_path, "static"))
    println("Path: ", path)
    if !ismissing(path)
        if isdir(path)
            response(sessionid, 500, [], body="Sorry, no folders yet")
        elseif endswith(path, ".css")
            response(sessionid, 200, ["Content-Type"=>"text/css"], body=read(path))
        else
            response(sessionid, 200, [], body=read(path))
        end
    else
        response(sessionid, 404, [], body="Sorry, bad request")
    end
end

# Return a filesystem path under some directory or missing if it does not exist
function url_to_path(req_path::AbstractString, dir::AbstractString)
    r_parts = HTTP.URIs.unescapeuri.(split(HTTP.URI(req_path).path[2:end], "/"))
    fs_path = normpath(joinpath(r_parts...))
    println(fs_path)
    fs_path = joinpath(dir, fs_path)
    println(fs_path, " ", isfile(fs_path), " " , isdir(fs_path))
    isfile(fs_path) || isdir(fs_path) ? fs_path : missing
end

end # module
