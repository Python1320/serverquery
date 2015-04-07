--setfenv(1,_G)
local meta={}
local co=setmetatable({},meta)
_G.co=co

-- todo
--	error handler wrapper?
--	select() polling support (epoll() please :c)
--	co.make steal parameters
--	?


local waitticks = {}
local -- internal identifiers for error control
	SLEEP,
	CO_RET,
	SLEEP_TICK,
	CO_END,
	CALLBACK,
	CALL_OUTSIDE,
	ENDED
	
	={},{},{},{},{},{},{},{}

local extra_state = setmetatable({},{__mode='k'})

local function check_coroutine(thread)
	if thread==nil then
		thread = coroutine.running()
	end
	if not thread then
		error("Can not call outside coroutine",2)
	end
end

local function __re(thread,ok,t,val,...)

	if not ok then
		ErrorNoHalt("[CO] "..tostring(t)..'\n')
		return
	end
	
	if t==SLEEP then
		--Msg"[CO] Sleep "print(val)
		timer.Simple(val,function()
			co._re(thread,SLEEP)
		end)
		
		return
		
	elseif t==SLEEP_TICK then
		table.insert(waitticks,thread)
	elseif t==CALLBACK then -- wait for callback
	--elseif t==CB_ONE then -- wait for any one callback 
	elseif t==CALL_OUTSIDE then
		co._re(thread,CALL_OUTSIDE,val(...))
	elseif t==CO_END then
		--Msg"[CO] END "print("OK")
		extra_state[thread]=ENDED
	elseif t==CO_RET then -- return some stuff to the callback, continue coroutine
		co._re(thread,CO_RET)
		return val,...
	else
		ErrorNoHalt("[CO] Unhandled "..tostring(t)..'\n')
	end
end

co._re=function(thread,...)
	
	local status = coroutine.status(thread)
	if status=="running" then
		-- uhoh?
	elseif status=="dead" then
		-- we can do nothing
		return
	elseif status=="suspended" then
		-- all ok
	else
		error"Unknown coroutine status!?"
	end
	
	-- do we need this
	if extra_state[thread] == ENDED then return end
	
	return __re(thread,coroutine.resume(thread,...))
	
end


hook.Add(MENU_DLL and "Think" or "Tick","colib",function()
	local count=#waitticks
	for i=count,1,-1 do
		local thread = table.remove(waitticks,i)
		co._re(thread,SLEEP_TICK)
	end
end)

function meta:__call(func,...)
	
	assert(isfunction(func),"invalid parameter supplied")
	
	local thread = coroutine.create(function(...)
		func(...)
		return CO_END
	end)
	
	return thread,co._re(thread,...)
end

function co.wrap(func,...)
	
	assert(isfunction(func),"invalid parameter supplied")
	
	local thread = coroutine.create(function(...)
		func(...)
		return CO_END
	end)
	
	return function(...)
		return co._re(thread,...)
	end
end

--- make a thread out of this function
--- If we are already in a thread, reuse it. It has to be a co thread though!
function co.make(...)

	local thread = coroutine.running()
	if thread then return false,thread end
	
	local func = debug.getinfo(2).func
	return true,co(func,...)
end

local function wrap(ok,a,...)
	if ok then
		return ...
	end
end

--[[ -- TODO
function co.cox(...)
	local t={...}
	local tc =#t
	local func = t[tc-1]
	local err = t[tc]
	t[tc]=nil
	t[tc-1]=nil
	
	assert(isfunction(func),"invalid parameter supplied")
	
	local thread = coroutine.create(function(unpack(t))
		xpcall(func,err,...)
	end)
	co._re(thread,...)
	
	return thread
end
--]]

function co.wait(delay)
	
	check_coroutine()
	local ret = coroutine.yield(SLEEP,tonumber(delay) or 0)
	if ret ~= SLEEP then
		error("Invalid return value from yield: "..tostring(ret))
	end
	--Msg"[CO] End wait "print(ret)
end

function co.waittick()
	
	check_coroutine()
	
	local ret = coroutine.yield(SLEEP_TICK)
	if ret ~= SLEEP_TICK then
		error("Invalid return value from yield: "..tostring(ret))
	end
	--Msg"[CO] End wait "print(ret)
end

co.sleep=co.wait

local function wrap(ret,...)
	if ret ~= CALL_OUTSIDE then 
		error("Invalid return value from yield: "..tostring(ret))
	end
	
	return ...
	
end

function co.extern(func,...)

	check_coroutine()
	
	return wrap(coroutine.yield(CALL_OUTSIDE,func,...))
	
end
function co.expcall(...)

	return co.extern(xpcall,...)
	
end



function co.newcb()
	
	local thread = coroutine.running()

	check_coroutine(thread)
	
	--Msg"[CO] Created cb for thread "print(thread)
	local CB CB = function(...)
		--Msg("[CO] Callback called for thread ",thread)print("OK")
		return co._re(thread,CALLBACK,CB,...)
	end
	return CB
end

function co.ret(...)
	local ret = coroutine.yield(CO_RET,...)
	if ret ~= CO_RET then
		error("Invalid return value from yield: "..tostring(ret))
	end
end

local function _waitonewrap(caller,...)
	return ...
end
function co.waitcb(cb)

	if cb==nil then
		return _waitonewrap(co.waitone())
	end
	
	check_coroutine()
		
	local function wrap(ret,caller,...)
		if ret ~= CALLBACK then
			error("Invalid return value from yield: "..tostring(ret))
		end
		if caller~=cb then
			error("Wrong callback returned")
		end
		return ...
	end
	
	return wrap(coroutine.yield(CALLBACK))
	
end

--same as above but returns the CB too
local function wrap(ret,caller,...)
	if ret ~= CALLBACK then
		error("Invalid return value from yield: "..tostring(ret))
	end
	return caller,...
end

function co.waitone()
	
	check_coroutine()
	
	return wrap(coroutine.yield(CALLBACK))
	
end

-- extensions --

function co.fetch(url)
	
	local ok,err = co.newcb(),co.newcb()
	http.Fetch(url,ok,err)
	
	local cb,a,b,c,d=co.waitone()
	if cb==ok then
		return true,a,b,c,d
	elseif cb==err then
		return false,a,b,c,d
	end
	
	error"Invalid fetch callback called"
	
end

co.PlayURL=function(url,params)
	local cb=co.newcb()
	sound.PlayURL(url,params or '',cb)
	return co.waitcb(cb)
end

co.PlayFile=function(url,params)
	local cb=co.newcb()
	sound.PlayFile(url,params or '',cb)
	return co.waitcb(cb)
end

-- testing --

--[[

co.wrap(function()
	
	local w = co.extern(function(...) return ... end,"extern")
	
	assert(w=="extern")
	
	local ct = CurTime()
	co.waittick()
	assert(ct~=CurTime())

	
	local ct = CurTime()
	co.sleep(0.2)
	assert(ct~=CurTime())
	
	local ok,dat,a,b,c,d = co.fetch("http://iriz.uk.to/404")

	assert(isstring(dat))
	
end)()

--]]--
