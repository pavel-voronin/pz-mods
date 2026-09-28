-- Optional external scenario protocol v1. This module has no UI or PZ3D dependency.
-- command: start(context, step), optional tick(context, step, elapsed) -> completed,
-- optional validate(step). start without tick completes immediately.
-- provider: begin(context) -> ready, update(context), boundary(context),
-- phase(context, name), finish(context, status, reason) -> flushed.
-- begin/finish may be polled and must be idempotent. Cleanup runs in reverse order.
ModStudio=ModStudio or {}
ModStudio.Scenarios=ModStudio.Scenarios or {version=1,commands={},providers={}}
local API=ModStudio.Scenarios
function API.register(owner, provider, commands)
    assert(type(owner)=="string" and string.match(owner,"^[a-z][a-z0-9_]*$"),"Invalid scenario provider")
    assert(not API.providers[owner],"Scenario provider already registered: "..owner)
    assert(type(provider)=="table" and type(commands)=="table","Invalid provider")
    for name,handler in pairs(commands) do
        assert(type(name)=="string" and type(handler)=="table" and type(handler.start)=="function","Invalid command")
        API.commands[owner.."."..name]=handler
    end
    API.providers[owner]=provider
end
