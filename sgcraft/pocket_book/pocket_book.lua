--Pocket_book revision 43
-- Minimal Stargate Address Book using native window() API (Restored to legacy style with colored entry highlight)
local completion = require("cc.completion")

local address_file = "saved_address.txt"
local address_book = {}
local config = { nearest_range = 200 }
local w, h = term.getSize()
local page = 1
local totalPages = 1
local input_line = ""
local highlight_y = nil
local highlight_timer = nil
local view_mode = "entries" -- can be: "entries", "help", "desc"
local selected_command = nil
local scroll_message = " enter list for a list of commands and their descriptions  "
local padded_message = scroll_message .. string.rep(" ", 2) .. scroll_message
local scroll_offset = 0
local scroll_timer = nil
local scroll_interval = 0.2
local prompt_active = false
local command_descriptions = {
    new = "Add a new entry to the address book. You'll be prompted for a name and a numeric address (e.g. 1-2-3) or any combination of , - and space.",
    
    edit = "Modify the name or address of an existing entry. Usage: edit <entry number>. Leave fields blank to keep them unchanged.",
    
    remove = "Delete an entry from the address book. Usage: remove <entry number>. You'll be asked to confirm before deletion.",
    
    dial = "Manually enter an address (e.g. 4-5-6) and send a dial request to the targeted Stargate.",
    
    dialgate = "Select a nearby gate by label and dial one of your saved entries. Usage: dialgate <entry number>.",
    
    list = "Display a list of all available commands. Clicking on one will show a detailed description.",
	
	stop = "Select a nearby gate by label and send a disconnect signal. Usage: stop",
    
    goto = "Jump directly to a specific page in the entry list. Usage: goto <page number>.",
    
    quit = "Exit the address book program and return to the terminal.",
	
	dialback = "Send a dialback command to the nearest gate. If EasyDial is present, it will redial the last address used. Future versions may support zzzv3 fallback.",
	
	chat = "Send the address of an entry via ChatBox. Usage: chat <entry> [player]"
}






-- Load addresses
if fs.exists(address_file) then
    local f = io.open(address_file, "r")
    address_book = textutils.unserialise(f:read("*a")) or {}
    f:close()
end

local function saveAddresses()
    local f = io.open(address_file, "w")
    f:write(textutils.serialise(address_book))
    f:close()
end


local per_page = h - 6

totalPages = math.max(1, math.ceil(#address_book / per_page))

-- Setup Rednet
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if modem then
    rednet.open(peripheral.getName(modem))
    rednet.host("jjs_sg_addressbook", tostring(os.getComputerID()))

    modem.open(2707)
end

local chatbox = peripheral.find("chatBox")
local chat_enabled = chatbox ~= nil

local function wrapText(text, width)
    local lines = {}
    for paragraph in text:gmatch("[^\n]+") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            if #line + #word + 1 <= width then
                if #line > 0 then
                    line = line .. " " .. word
                else
                    line = word
                end
            else
                table.insert(lines, line)
                line = word
            end
        end
        if #line > 0 then table.insert(lines, line) end
    end
    return lines
end

term.redirect(term.native()) -- reset to default first
local win = window.create(term.current(), 1, 1, w, h, false)
term.redirect(win) -- now redirect input/output to the window

local function renderScrollingMessage()
    win.setCursorPos(1, h - 3)
    win.setTextColor(colors.yellow)
    win.setBackgroundColor(colors.black)
    win.clearLine()
    local visible = padded_message:sub(scroll_offset, scroll_offset + w - 1)
    win.write(visible)
	
-- 🔧 Reset to UI defaults
win.setTextColor(colors.white)
win.setBackgroundColor(colors.black)
end



local function drawScrollingMessage()
    scroll_offset = scroll_offset + 1
    if scroll_offset > #scroll_message + w then
        scroll_offset = 1
    end
    renderScrollingMessage()
end


-- Window setup

local function draw()
    win.setVisible(false)
    win.setCursorPos(1, 1)
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    win.clear()

    if view_mode == "entries" then
        win.setCursorPos(1,1)
    win.setTextColor(colors.white)
    win.setBackgroundColor(colors.black)
    win.clear()

    win.setCursorPos(1, 1)
    win.write("[ Address Book - Page " .. page .. " ]")
    win.setCursorPos(1, 2)
    win.write(string.rep("=", w))

    local start = (page - 1) * per_page + 1
    local stop = math.min(start + per_page - 1, #address_book)
    for i = start, stop do
        local y = 2 + (i - start + 1)
        win.setCursorPos(1, y)
        if y == highlight_y then
            win.setTextColor(colors.lime)
        else
            win.setTextColor(colors.red)
        end
        win.write("[" .. i .. "]")
        win.setTextColor(colors.white)
        win.write(" " .. address_book[i].name .. string.rep(" ", w - #address_book[i].name - 4 - tostring(i):len()))
    end

    win.setCursorPos(1, h - 2)
    win.setTextColor(colors.white)
    win.write("> " .. input_line .. string.rep(" ", w - #input_line - 10))
	
	-- Move instruction up here
    win.setCursorPos(1, h - 1)
    win.write("(click entry to dial)" .. string.rep(" ", w))

    win.setCursorPos(1, h)
    win.write("[<]   [>]   [X]" .. string.rep(" ", w))

if not prompt_active then
    renderScrollingMessage()
end

    elseif view_mode == "help" then
        win.setCursorPos(1, 1)
        win.write("[ Command List ]")
        win.setCursorPos(1, 2)
        win.write(string.rep("=", w))

        local cmds = { "new", "edit", "remove", "dial", "dialgate", "dialback", "stop", "chat", "list", "quit" }
        for i, cmd in ipairs(cmds) do
    win.setCursorPos(1, i + 2)
    if cmd == "chat" and not peripheral.find("chatBox") then
        win.setTextColor(colors.gray)
    else
        win.setTextColor(colors.white)
    end
    win.write("[" .. i .. "] " .. cmd)
end

        win.setCursorPos(1, h)
        win.write("[Back]" .. string.rep(" ", w))

    elseif view_mode == "desc" and selected_command then
        win.setCursorPos(1, 1)
        win.write("[ " .. selected_command .. " ]")
        win.setCursorPos(1, 2)
        win.write(string.rep("=", w))

        win.setCursorPos(1, 4)
        local raw
if selected_command == "chat" and not peripheral.find("chatBox") then
    raw = "ChatBox not detected. This command is unavailable."
else
    raw = command_descriptions[selected_command] or "(no description yet)"
end
local desc_lines = wrapText(raw, w)

for i, line in ipairs(desc_lines) do
    if 3 + i < h - 2 then
        win.setCursorPos(1, 2 + i)
        win.clearLine()
        win.write(line)
    end
end



        win.setCursorPos(1, h)
        win.write("[Back]" .. string.rep(" ", w))
    end

    win.setVisible(true)
end



local function getNearestGate()
    modem.transmit(2707, 2707, {protocol="jjs_sg_dialer_ping", message="request_ping"})
    local timeout_timer = os.startTimer(1.0)
    local temp_gates = {}

    while true do
        local event = { os.pullEvent() }
        if event[1] == "modem_message" then
            local msg, dist = event[5], event[6]
            if type(msg) == "table" and msg.protocol == "jjs_sg_dialer_ping" and msg.message == "response_ping" then
                if type(msg.id) == "number" and dist and dist < config.nearest_range then
                    table.insert(temp_gates, {id=msg.id, distance=dist, label=msg.label or "unknown"})
                end
            end
        elseif event[1] == "timer" and event[2] == timeout_timer then
            break
        end
    end

    table.sort(temp_gates, function(a, b) return a.distance < b.distance end)
    return temp_gates[1]
end

local function dial(entry)
    local gate = getNearestGate()
    if gate and gate.id then
        rednet.send(gate.id, table.concat(entry.address, "-"), "jjs_sg_startdial")
        win.setCursorPos(1, h - 1)
        win.clearLine()
        win.write("Dialing: " .. entry.name .. string.rep(" ", w))

    else
        win.setCursorPos(1, h - 1)
        win.clearLine()
        win.write("No valid gate found." .. string.rep(" ", w))
    end

    -- Scroll recovery fix:
    scroll_timer = os.startTimer(scroll_interval)
    -- Flush scroll events after dialing
    while true do
        local e = { os.pullEventRaw() }
        if e[1] ~= "mouse_scroll" then
            os.queueEvent(table.unpack(e))
            break
        end
    end
    win.redraw()
end


local function quickstop()
    local gate = getNearestGate()
    if gate and gate.id then
        rednet.send(gate.id, "", "jjs_sg_disconnect")
        win.setCursorPos(1, h - 1)
        win.clearLine()
        win.write("Disconnected gate." .. string.rep(" ", w))
        sleep(1)
        draw()

    else
        win.setCursorPos(1, h - 1)
        win.clearLine()
        win.write("No valid gate found." .. string.rep(" ", w))
    end

    -- Scroll recovery fix:
    scroll_timer = os.startTimer(scroll_interval)
    -- Flush scroll events after dialing
    while true do
        local e = { os.pullEventRaw() }
        if e[1] ~= "mouse_scroll" then
            os.queueEvent(table.unpack(e))
            break
        end
    end
    win.redraw()
end


local function scanGates()
    modem.transmit(2707, 2707, { protocol = "jjs_sg_dialer_ping", message = "request_ping" })
    local timeout = os.startTimer(1.0)
    local results = {}

    while true do
        local event = { os.pullEvent() }
        if event[1] == "modem_message" then
            local msg = event[5]
            if type(msg) == "table" and msg.protocol == "jjs_sg_dialer_ping" and msg.message == "response_ping" then
                if type(msg.label) == "string" and type(msg.id) == "number" then
                    results[msg.label:lower()] = msg.id
                end
            end
        elseif event[1] == "timer" and event[2] == timeout then
            break
        end
    end

    return results
end


-- Main event loop
local function main()

draw()
scroll_timer = os.startTimer(scroll_interval)
local function promptInput(prompt)
    prompt_active = true
    win.setCursorPos(1, h - 3)
    win.clearLine()
    win.write(prompt)
    win.setCursorPos(1, h - 2)
    win.clearLine()

    term.redirect(term.native())
    write("> ")
    local input = read()
	prompt_active = false
    term.redirect(win)
scroll_timer = os.startTimer(scroll_interval)
-- Flush scroll events that may have occurred during read()
while true do
    local e = { os.pullEventRaw() }
    if e[1] ~= "mouse_scroll" then
        os.queueEvent(table.unpack(e))
        break
    end
end
	win.redraw() -- force re-focus

    
    return input
end



while true do
    local e = { os.pullEvent() }

    if e[1] == "mouse_click" then
        local _, btn, x, y = table.unpack(e)

        if view_mode == "entries" then
    if y == h then
        if x >= 1 and x <= 3 and page > 1 then
            page = page - 1
            draw()
        elseif x >= 8 and x <= 10 and page < totalPages then
            page = page + 1
            draw()
        elseif x >= 13 and x <= 15 then
            quickstop()
        end
    elseif y >= 3 and y <= 2 + per_page then
    if x >= 1 and x <= 4 then
                local idx = (page - 1) * per_page + (y - 2)
        if address_book[idx] then
            highlight_y = y
            draw()
            dial(address_book[idx])
            highlight_timer = os.startTimer(2)
        
    end
    end
    end

elseif view_mode == "help" then
    if y >= 3 and y <= 9 then
        local cmds = { "new", "edit", "remove", "dial", "dialgate", "dialback", "stop", "chat", "list", "quit" }
        local index = y - 2
        if cmds[index] then
            local cmd = cmds[index]
if cmd == "chat" and not chat_enabled then
    selected_command = "chat"
    view_mode = "desc"
else
    selected_command = cmd
    view_mode = "desc"
end
draw()
        end
    elseif y == h then
        view_mode = "entries"
        draw()
    end

elseif view_mode == "desc" then
    if y == h then
        view_mode = "help"
        draw()
    end
end


		


    elseif e[1] == "char" then
        input_line = input_line .. e[2]
        draw()
	elseif e[1] == "mouse_scroll" then
    local dir = e[2]
    if dir == 1 and page < totalPages then
        page = page + 1
        draw()
    elseif dir == -1 and page > 1 then
        page = page - 1
        draw()
    end

    elseif e[1] == "key" then
        if e[2] == keys.backspace then
            input_line = input_line:sub(1, -2)
            draw()
        elseif e[2] == keys.enter or e[2] == keys.numPadEnter then
            local input = input_line
            input_line = ""
            draw()
	
            local parts = {}
            for word in input:gmatch("%S+") do table.insert(parts, word) end
            local cmd = parts[1]
			
			if cmd == "new" then
    local name = promptInput("Enter name:")
    win.setCursorPos(1, h - 3)
win.clearLine()
win.write("Enter address:")
win.setCursorPos(1, h - 2)
win.clearLine()

prompt_active = true
term.redirect(term.native())
write("> ")
local rawaddr = read()
prompt_active = false
term.redirect(win)
scroll_timer = os.startTimer(scroll_interval)
-- Flush scroll events that may have occurred during read()
while true do
    local e = { os.pullEventRaw() }
    if e[1] ~= "mouse_scroll" then
        os.queueEvent(table.unpack(e))
        break
    end
end
win.redraw() -- force re-focus


    local addr = {}
    for n in rawaddr:gmatch("%d+") do
        table.insert(addr, tonumber(n))
    end
    table.insert(address_book, { name = name, address = addr })
    saveAddresses()
    totalPages = math.max(1, math.ceil(#address_book / per_page))
    page = totalPages
    draw()
win.setCursorPos(1, h - 3)
win.clearLine()


	elseif cmd == "edit" and tonumber(parts[2]) then
    local i = tonumber(parts[2])
    local entry = address_book[i]
    if entry then
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Enter name:")
        win.setCursorPos(1, h - 2)
        win.clearLine()
prompt_active = true
term.redirect(term.native())
write("> ")
local name = read(nil, nil, nil, entry.name)




prompt_active = false
term.redirect(win)
scroll_timer = os.startTimer(scroll_interval)
-- Flush scroll events that may have occurred during read()
while true do
    local e = { os.pullEventRaw() }
    if e[1] ~= "mouse_scroll" then
        os.queueEvent(table.unpack(e))
        break
    end
end
win.redraw() -- force re-focus


        if name == "" then name = entry.name end

        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Enter address:")
        win.setCursorPos(1, h - 2)
        win.clearLine()
prompt_active = true
term.redirect(term.native())
write("> ")
local rawaddr = read(nil, nil, nil, table.concat(entry.address, "-"))



prompt_active = false
term.redirect(win)
scroll_timer = os.startTimer(scroll_interval)
-- Flush scroll events that may have occurred during read()
while true do
    local e = { os.pullEventRaw() }
    if e[1] ~= "mouse_scroll" then
        os.queueEvent(table.unpack(e))
        break
    end
end
win.redraw() -- force re-focus


        if rawaddr == "" then
            rawaddr = table.concat(entry.address, "-")
        end

        local addr = {}
        for n in rawaddr:gmatch("%d+") do
            table.insert(addr, tonumber(n))
        end

        address_book[i] = { name = name, address = addr }
        saveAddresses()
        draw()
    else
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Invalid index.")
        sleep(1)
        draw()
    end
elseif cmd == "remove" and tonumber(parts[2]) then
    local i = tonumber(parts[2])
    local entry = address_book[i]
    if entry then
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Delete [" .. i .. "] " .. entry.name .. "? (y/N)")
        win.setCursorPos(1, h - 2)
        win.clearLine()
prompt_active = true
term.redirect(term.native())
write("> ")
local confirm = read():lower()
prompt_active = false
term.redirect(win)
scroll_timer = os.startTimer(scroll_interval)
-- Flush scroll events that may have occurred during read()
while true do
    local e = { os.pullEventRaw() }
    if e[1] ~= "mouse_scroll" then
        os.queueEvent(table.unpack(e))
        break
    end
end
win.redraw() -- force re-focus



        if confirm == "y" or confirm == "yes" then
            table.remove(address_book, i)
            saveAddresses()
            totalPages = math.max(1, math.ceil(#address_book / per_page))
            if page > totalPages then page = totalPages end
            draw()
        else
            draw()
        end
    else
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Invalid index.")
        sleep(1)
        draw()
    end
elseif cmd == "dial" and not parts[2] then
    local rawaddr = promptInput("Enter address:")
    local addr = {}
    for n in rawaddr:gmatch("%d+") do
        table.insert(addr, tonumber(n))
    end
    if #addr < 2 then
        win.setCursorPos(1, h - 4)
        win.clearLine()
        win.write("Invalid address.")
        sleep(1)
        draw()
    else
        local gate = getNearestGate()
        if gate and gate.id then
            rednet.send(gate.id, table.concat(addr, "-"), "jjs_sg_startdial")
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("Dialing raw address..." .. string.rep(" ", w))
        else
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("No gate found." .. string.rep(" ", w))
        end
		scroll_timer = os.startTimer(scroll_interval)

        draw()
    end

elseif cmd == "chat" and tonumber(parts[2]) then
    if not chat_enabled then
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("ChatBox not detected.")
        sleep(1)
        draw()
        return
    end

    local i = tonumber(parts[2])
    local entry = address_book[i]
    if entry then
local addr = table.concat(entry.address, "-")
local header = {}

if parts[3] then
  table.insert(header, { text = " (whisper)\n", color = "gray" })
else
  table.insert(header, { text = "\n" })
end

local json = textutils.serializeJSON({
  table.unpack(header),
  { text = "Name: ", color = "gold" },
  { text = entry.name .. "\n", color = "yellow" },
  { text = "Address: ", color = "gold" },
  {
    text = addr,
    color = "aqua",
    clickEvent = {
      action = "copy_to_clipboard",
      value = addr
    },
    hoverEvent = {
      action = "show_text",
      contents = "Click to copy address"
    }
  }
})
        if parts[3] then
		local target = parts[3]
            chatbox.sendFormattedMessageToPlayer(json, parts[3], "Pocket Book")
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("Sent to " .. target)
        else
            chatbox.sendFormattedMessage(json, "Pocket Book")
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("Broadcast: Successful ")
        end
    else
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Invalid entry number.")
        sleep(1)
    end
    draw()

elseif cmd == "dialgate" and tonumber(parts[2]) then
    local i = tonumber(parts[2])
    local entry = address_book[i]
    if not entry then
        win.setCursorPos(1, h - 4)
        win.clearLine()
        win.write("Invalid entry number.")
        sleep(1)
        draw()
        return
    else
        local gates = scanGates()
        local labels = {}
        for label in pairs(gates) do
            table.insert(labels, label)
        end
        table.sort(labels)

        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Gate label:")

        win.setCursorPos(1, h - 2)
        win.clearLine()

        local native = term.native()
        term.redirect(native)
        write("> ")
        prompt_active = true
        local selected = read(nil, nil, function(text)
    return completion.choice(text, labels)
end)


        prompt_active = false
        term.redirect(win)
        scroll_timer = os.startTimer(scroll_interval)
        -- Flush scroll events after dialing
        while true do
            local e = { os.pullEventRaw() }
            if e[1] ~= "mouse_scroll" then
                os.queueEvent(table.unpack(e))
                break
            end
        end
        win.redraw()

        local targetID = gates[selected:lower()]
        if targetID then
            rednet.send(targetID, table.concat(entry.address, "-"), "jjs_sg_startdial")
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("Dialed " .. selected .. " with entry " .. i .. string.rep(" ", w))
        else
            win.setCursorPos(1, h - 3)
            win.clearLine()
            win.write("Label not found.")
            sleep(1)
        end

        draw()
    end
elseif cmd == "stop" then
    local gates = scanGates()
    local labels = {}
    for label in pairs(gates) do
        table.insert(labels, label)
    end
    table.sort(labels)

    win.setCursorPos(1, h - 3)
    win.clearLine()
    win.write("Gate label:")

    win.setCursorPos(1, h - 2)
    win.clearLine()

    term.redirect(term.native())
    write("> ")
    prompt_active = true
    local selected = read(nil, nil, function(text)
        return completion.choice(text, labels)
    end)
    prompt_active = false
    term.redirect(win)
    scroll_timer = os.startTimer(scroll_interval)
    while true do
        local e = { os.pullEventRaw() }
        if e[1] ~= "mouse_scroll" then
            os.queueEvent(table.unpack(e))
            break
        end
    end
    win.redraw()

    local targetID = gates[selected:lower()]
    if targetID then
        rednet.send(targetID, "", "jjs_sg_disconnect")
        win.setCursorPos(1, h - 1)
        win.clearLine()
        win.write("Sent stop signal to: " .. selected .. string.rep(" ", w))
    else
        win.setCursorPos(1, h - 3)
        win.clearLine()
        win.write("Label not found.")
        sleep(1)
    end

    draw()

elseif cmd == "dialback" then
    local gate = getNearestGate()
    if gate and gate.id then
        rednet.send(gate.id, "gate_dialback", "jjs_sg_rawcommand")
        local timeout = os.startTimer(1.0)
        local answered = false

        while true do
            local e = { os.pullEvent() }
            if e[1] == "modem_message" and e[4] == "jjs_sg_rawcommand" then
                if e[5] == "dialback_ack" then
                    answered = true
                    break
                end
            elseif e[1] == "timer" and e[2] == timeout then
                break
            end
        end

        if answered then
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("Dialback sent (EasyDial acknowledged).")
        else
            win.setCursorPos(1, h - 1)
            win.clearLine()
            win.write("No EasyDial response. zzzv3 fallback pending.")
        end
    else
        win.setCursorPos(1, h - 1)
        win.clearLine()
        win.write("No valid gate found.")
    end
    sleep(1)
    draw()
    scroll_timer = os.startTimer(scroll_interval)

elseif cmd == "list" then
    view_mode = "help"
    draw()


            elseif cmd == "goto" and parts[2] then
                local p = tonumber(parts[2])
                if p and p >= 1 and p <= totalPages then
                    page = p
                end
            elseif cmd == "quit" then
                break
            end
            draw()
        end
    elseif e[1] == "timer" and highlight_timer and e[2] == highlight_timer then
        highlight_y = nil
        highlight_timer = nil
        draw()
	elseif e[1] == "timer" and e[2] == scroll_timer then
    if view_mode == "entries" and not prompt_active then
        drawScrollingMessage()
    end
    scroll_timer = os.startTimer(scroll_interval)

    end

end


end
local ok, err = pcall(main)
-- Clear screen on exit
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

if not ok then
    print("Error: " .. tostring(err))
end