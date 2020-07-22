
sessions = Dict()

function start_http_and_websocket_servers(ip_addr, http_port, http_router, websocket_port, websocket_router)
    websocket_task = @task HTTP.WebSockets.listen(ip_addr, UInt16(websocket_port)) do ws
        while !eof(ws)
            local data
            process = true
            try
                data = readavailable(ws)
            catch e
                process = false
            end
            process && report_ws_errors(ws, revise_function(websocket_router))(ws, data)
        end
    end

    try
        schedule(websocket_task)
        HTTP.serve(report_http_errors(revise_function(http_router)), ip_addr, http_port; reuse_limit=0,)
    finally
        schedule(websocket_task, "exit"; error=true)
    end
end

# Allow live editing of routes and request-handling code
# NOTE: Passed function must be named (not anonymous) for live revisions to work
function revise_function(func)
    (args...; kw...) -> begin
        try
            Revise.revise()
        catch x
            printstyled(x, '\n'; color=:red)
            for level in stacktrace(catch_backtrace())
                println(level)
            end
            return HTTP.Response(500, "There was a revision error")
        end

        Base.invokelatest(func, args...; kw...)
    end
end

# Used by route_pages function
const SCHEMES = Dict{String, Val}("http" => Val{:http}(), "https" => Val{:https}())
const EMPTYVAL = Val{()}()

#Match URL's to handler functions
#Attempts to get to private pages are rerouted to the login page if not currently logged in
function route_http_request(request::HTTP.Request; public=Dict(), private=Dict(), login=missing, default=missing, public_path=Dict())
    sessionid = get_sessionid(request)
    m = Val(Symbol(request.method))
    uri = HTTP.URI(request.target)
    s = get(SCHEMES, uri.scheme, EMPTYVAL)
    h = Val(Symbol(uri.host))
    p = uri.path
    segments = split(uri.path, '/'; keepempty=false)
    # Check if URL is private (requires a login)
    if haskey(private, uri.path)
        if isloggedin(sessionid)
            return private[uri.path](request, sessionid)
        else
            printstyled("Falling back to login\n", color=:red)
            if !ismissing(login)
                public[login](request, sessionid)
            else
                println("404 $(uri.path)")
                HTTP.Response(404, "No such page")
            end
        end
    # Handle public URL
    elseif haskey(public, uri.path)
        public[uri.path](request, sessionid)
    # Handle public URLs with certain prefixes
    else
        for (prefix, func) in pairs(public_path)
            if startswith(uri.path, prefix)
                return func(request, uri.path[length(prefix):end], sessionid)
            end
        end
        if !ismissing(default)
            default(request, sessionid)
        else
            println("404 $(uri.path)")
            HTTP.Response(404, "No such page")
        end
    end
end

function route_websocket_request(ws, data; public=Dict(), private=Dict(), default=missing)
    local msg
    is_json = true
    try
        msg = JSON3.read(data)
    catch e
        is_json = false
    end

    if is_json
        _type = msg[:type]
        if haskey(private, _type) private[_type](ws, msg)
        elseif haskey(public, _type) public[_type](ws, msg)
        elseif !ismissing(default) default(ws, msg)
        end
    end
end

# Output a response including the sessionid cookie
function response(sessionid, code, headers; body="")
    HTTP.Response(code, vcat(["Set-Cookie" => String(HTTP.Cookie("sessionid", string(sessionid)))], headers); body=body)
end

# Determine the current valid sessionid or empty string
function get_sessionid(request::HTTP.Request)
    for cookie in HTTP.Cookies.readcookies(request.headers, "sessionid")
        haskey(sessions, cookie.value) && return cookie.value
    end
    return ""
end

# Determine if user is logged in
isloggedin(sessionid) = haskey(sessions, sessionid)

# Show generic error in browser but details in console
function report_ws_errors(ws, func)
    (args...; kw...) -> begin
        try
            func(args...; kw...)
        catch x
            printstyled(x, '\n'; color=:red)
            for level in stacktrace(catch_backtrace())
                println(level)
            end
            write(ws, Dict(:type=>"error", :msg=>"There was an error"))
        end
    end
end

# Show generic error in browser but details in console
function report_http_errors(func)
    (args...; kw...) -> begin
        try
            func(args...; kw...)
        catch x
            printstyled(x, '\n'; color=:red)
            for level in stacktrace(catch_backtrace())
                println(level)
            end
            HTTP.Response(500, "There was an error")
        end
    end
end

