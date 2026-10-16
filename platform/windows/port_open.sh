#!/bin/zsh
# port_open.sh IP PORT — succeeds if something answers there (about 2 s, never hangs)
source "${0:A:h}/_windows.sh"
PC_IP="$1" PC_PORT="$2" run_ps '
$client = New-Object System.Net.Sockets.TcpClient
try {
  $task = $client.ConnectAsync($env:PC_IP, [int]$env:PC_PORT)
  if ($task.Wait(2000) -and $client.Connected) { exit 0 }
  exit 1
} catch { exit 1 } finally { $client.Close() }' >/dev/null 2>&1
