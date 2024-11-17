local wezterm = require("wezterm")

---@class init_module
local pub = {} -- The public module to be returned as a plugin

---@class DistroboxContainers
---@field label string
---@field id string

-- List the available distrobox containers
---@return DistroboxContainers[]
local function get_distrobox_containers ()
	local flatpak_command = "flatpak-spawn --host " -- Command to prepend to host commands if using distrobox
	local distrobox_test = "distrobox list" -- Use to test presence of distrobox command
	local distrobox_list_full = "distrobox list --no-color | awk -v col=3 '{print $col}' - | tail -n +2"
	--[[
		The command utilises the distrobox list command and pipes the output to awk and tail,
		two commands found in any POSIX compliant shell. The commands do the following:
		1. distrobox list --no-color
			Print a table of all distrobox containers without formatting
		2. awk -v col=3 '{print $col}' -
			Split each row of the table (piped in from stdin using -) by the spaces and 
			return the values at the split of index 3 where 1 is the ID, 2 is the | 
			| splitting the table and 3 is the name of the distrobox container
		3. tail -n +2
			Remove the first row, in this case the column header "NAME"

		This command should theoretically work on any POSIX compliant shell. Please raise an
		issue if not so system specific adjustments can be added
	--]]
	local wt_is_host = os.execute(distrobox_test)
	local wt_is_flatpak = os.execute(flatpak_command .. distrobox_test)
	-- Prepend flatpak's "run command as host" command
	local cmd = ""
	if wt_is_flatpak then
		cmd = flatpak_command .. distrobox_list_full
		wezterm.log_info("Wezterm is running as a flatpak")
	elseif wt_is_host then
		cmd = distrobox_list_full
		wezterm.log_info("Wezterm is running as host")
	else
		wezterm.log_info("Distrobox command not found")
		return {}
	end
	local handle = io.popen(cmd)
	if handle == nil then
		return {}
	end
	local output = handle:read('*a')
	local dbox_options = {}
	for s in output:gmatch("[^\r\n]+") do
		wezterm.log_info("Found distrobox container: " .. s)
		table.insert(
			dbox_options,
			{
				label = tostring(s),
				id = "distrobox - " .. tostring(s)
			}
		)
	end
	return dbox_options
end

local function spawn_distrobox_mux_tab(action_window, pane, id, label)
	if not id and not label then
		wezterm.log_info('cancelled')
	else
		local cmd = {}
		if string.find(id, "distrobox - ") then
			cmd = {
				'distrobox',
				'enter',
				'--name',
				tostring(label),
				'--no-workdir'
			}
			if pub.entry_commands[label] then
				wezterm.log_info(
					"Entry command found for " .. label
				)
				wezterm.log_info(pub.entry_commands[label])
				table.insert(cmd, "--")
				table.insert(cmd, pub.entry_commands[label])
			end
		end
		local mux_win = action_window:mux_window()
		if id ~= "" then
			local _ = mux_win:spawn_tab(
				{
					args = cmd,
				}
			)
			wezterm.log_info('you selected ', label)
		else
			local _ = mux_win:spawn_tab(
				{
				}
			)
			wezterm.log_info('you selected host shell')
		end
	end
	return pane
end

-- Open a new wezterm tab and list all distrobox containers, allowing the user to select one to open in a new tab
---@param window MuxWindow
---@param pane MuxPane
function pub.distrobox_nvim_tab (window, pane)
	wezterm.log_info(pub.entry_commands)
	local act = wezterm.action
	local choices = {
		{
			id = "",
			label = wezterm.format {
				{ Foreground = { AnsiColor = 'Teal' } },
				{ Text = 'Host Shell' }
			},
		}
	}
	for _, v in ipairs(get_distrobox_containers()) do
		table.insert(choices, v)
	end

	window:perform_action(
		act.InputSelector {
			action = wezterm.action_callback(
					spawn_distrobox_mux_tab
				),
				title = 'Containers',
				choices = choices,
				description = 'Choose your container',
			},
		pane
	)
end

---@type table<string, string>
pub.entry_commands = {}

-- Add keybinding to wezterm
---@alias container_name string The name of the container
---@alias command string The command to use when entering the container
---@alias container_entry_commands table<container_name, command>
---@param config ConfigBuilder
---@param opts { key: string?, mods: string?, entry_commands: container_entry_commands? }?
function pub.apply_to_config(config, opts)
	local key = "mapped:r"
	local mods = "CTRL|SHIFT"
	local next = next
	wezterm.log_info(config)
	wezterm.log_info(opts)
	---@type container_entry_commands
	if opts then
		wezterm.log_info("Extra options provided")
		if opts.entry_commands then
			wezterm.log_info(opts.entry_commands)
			---@type container_entry_commands
			for k, v in pairs(opts.entry_commands) do
				wezterm.log_info(k)
				wezterm.log_info(v)
				pub.entry_commands[k] = v
			end
		end
		if opts.key then
			wezterm.log_info("Alternative keymap: " .. opts.key)
			key = opts.key
		end
		if opts.mods then
			wezterm.log_info("Alternative modifier: " .. opts.mods)
			mods = opts.mods
		end
	end
	wezterm.log_info(pub.entry_commands)

	if config.keys == nil then
		config.keys = {}
	end

	table.insert(config.keys, {
		key = key,
		mods = mods,
		action = wezterm.action_callback(pub.distrobox_nvim_tab)
	})
end
return pub
