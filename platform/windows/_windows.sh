# Helpers shared by the Windows platform scripts (sourced by them, not by PhoneConnect.sh).

SYSDIR="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32"
POWERSHELL="$SYSDIR/WindowsPowerShell/v1.0/powershell.exe"

# run_ps <code>: run PowerShell code without a window. Data goes in through PC_*
# environment variables (never pasted into the code), so quotes or non-English
# text can't break it. Output comes back as UTF-8; the exit code is passed on.
run_ps() {
  local f rc
  f="$TMPDIR/PhoneConnect.$$.$RANDOM.ps1"
  { print -r -- '[Console]::OutputEncoding = [Text.Encoding]::UTF8'
    print -r -- "$1"; } > "$f"
  if [[ -n "$PC_PS_CHECK" ]]; then
    # tests: only check that the code parses (dialogs can't be clicked there)
    PC_PS_FILE="$(cygpath -w "$f")" "$POWERSHELL" -NoProfile -NonInteractive -Command '
      $errors = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile($env:PC_PS_FILE, [ref]$null, [ref]$errors)
      if ($errors) { $errors | ForEach-Object { [Console]::Error.WriteLine($_.ToString()) }; exit 1 }
      exit 0'
  else
    "$POWERSHELL" -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File "$(cygpath -w "$f")"
  fi
  rc=$?
  rm -f "$f"
  return $rc
}

# scrcpy_winpid <pid>: the Windows process id of scrcpy.exe running under the
# background job <pid> (an MSYS process id). From `ps -l`: an optional status
# letter, then PID PPID PGID WINPID TTY UID STIME COMMAND.
scrcpy_winpid() {
  ps -l | awk -v root="$1" '
    NR == 1 { next }
    {
      line = substr($0, 2)                  # drop the status letter column
      n = split(line, f, " ")
      pid = f[1]; ppid[pid] = f[2]; winpid[pid] = f[4]
      cmd = ""; for (i = 8; i <= n; i++) cmd = cmd (i > 8 ? " " : "") f[i]
      command[pid] = tolower(cmd)
    }
    END {
      want[root] = 1
      for (level = 0; level < 6; level++)   # walk down from the job, a few levels
        for (p in ppid) if (ppid[p] in want) want[p] = 1
      for (p in want) if (command[p] ~ /scrcpy(\.exe)?$/) { print winpid[p]; exit 0 }
      exit 1
    }'
}
