#!/bin/bash
# Windows toast notification from WSL. Wire up in ~/.a2a/config.json:
#   "notify_command": ["/mnt/c/code/github/a2a/notify-windows.sh"]
# The daemon appends the item summary as the final argument.
SUMMARY="${1:-a2a item received}"
powershell.exe -NoProfile -Command "
\$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
\$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$texts = \$xml.GetElementsByTagName('text')
\$null = \$texts.Item(0).AppendChild(\$xml.CreateTextNode('a2a'))
\$null = \$texts.Item(1).AppendChild(\$xml.CreateTextNode('$(printf %s "$SUMMARY" | sed "s/'/''/g")'))
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('a2a').Show(\$toast)
" 2>/dev/null
