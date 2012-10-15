local utils = require("mch.util")

module('mch.console', package.seeall)

function getMembers(t, o)
  local tp
  for i, j in pairs(o) do
    if type(i) == 'string' then
      if type(j) == 'function' then
        tp = true
      else
        tp = false
      end
      t[i] = tp
    end
  end
  return t
end

function table2array(t, funcOnly)
  local ret = {}
  for k, v in pairs(t) do
    if v then
      table.insert(ret, k .. '(')
    elseif funcOnly then
    else
      table.insert(ret, k)
    end
  end
  return ret
end

function interact(host, port)
  local sock = ngx.socket.tcp()
  local ok, err
  ok, err = sock:connect(host, port)
  if not ok then
    logger:error('Error while connecting back to %s:%d, %s', host, port, err)
    return
  end
  logger:info('console socket connected.')
  sock:settimeout(86400000)
  while true do
    local req = utils.read_jsonresponse(sock)
    local res = {}
    logger:info('console socket got request: %s', req)
    if not req then break end
    local res = {}
    if req.cmd == 'code' then
      local ok, chunk, ret, err

      -- must come first
      chunk, err = loadstring('return ' .. req.data, 'console')
      if not chunk then
        chunk, err = loadstring(req.data, 'console')
      end

      if err then
        res.error = err
      else
        ok, ret = pcall(chunk)
        if not ok then
          res.error = ret
        else
          if ret ~= nil then
            res.result = logger.tostring(ret)
          end
        end
      end
    elseif req.cmd == 'dir' then
      local t = {}
      local o
      local chunk, ok, ret
      chunk, _ = loadstring('return ' .. req.data, 'input')
      if chunk then
        ok, ret = pcall(chunk)
        if ok then
          o = ret
        end
      end
      if o then
        getMembers(t, o)
        local meta = getmetatable(o) or {}
        if type(meta.__index) == 'table' then
          getMembers(t, meta.__index)
        end
      end
      res.result = table2array(t, req.funcOnly)
    else
      res.error = 'unknown cmd: ' .. logger.tostring(req.cmd)
    end
    logger:info('reply: %s', res)
    utils.write_jsonresponse(sock, res)
  end
  logger:info('console session ends.')
end

function start(req, res)
  res.headers['Content-Type'] = 'text/plain'
  local host = req.uri_args.host or ngx.var.remote_addr
  local port = req.uri_args.port
  res:defer(function()
    interact(host, port)
  end)
  res:writeln("ok.")
end
