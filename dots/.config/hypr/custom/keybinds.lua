hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("CTRL+SUPER+ALT+I", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/session-init.sh"), {description = "Initialize work session"} )
hl.bind("SUPER+ALT+J", hl.dsp.global("quickshell:jiraTicketToggle"), {description = "Shell: Toggle Jira ticket"} )
