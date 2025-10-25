param(
    [string]$Prefix = 'http://localhost:8123/',
    [string]$TasksDir = (Join-Path (Join-Path $PSScriptRoot '..') '.tasks'),
    [int]$MaxRequestBodyKB = 256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tasksPath = [System.IO.Path]::GetFullPath($TasksDir)
New-Item -ItemType Directory -Force -Path $tasksPath | Out-Null
$inbox = Join-Path $tasksPath 'inbox'
New-Item -ItemType Directory -Force -Path $inbox | Out-Null

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($Prefix)
$listener.Start()
Write-Host "Task webhook listening on $Prefix (CTRL+C to stop)"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            if ($ctx.Request.HttpMethod -ne 'POST') {
                $ctx.Response.StatusCode = 405
                continue
            }
            $path = $ctx.Request.Url.AbsolutePath.TrimEnd('/')
            if ($path -ne '' -and $path -ne '/enqueue') {
                $ctx.Response.StatusCode = 404
                continue
            }
            $len = [Math]::Min($ctx.Request.ContentLength64, $MaxRequestBodyKB * 1024)
            $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            if ($body.Length -gt $len) { $body = $body.Substring(0, [int]$len) }
            $reader.Close()
            $payload = ConvertFrom-Json -InputObject $body
            $tasks = @()
            if ($payload -is [System.Collections.IEnumerable]) { $tasks = $payload } else { $tasks = @($payload) }
            foreach ($task in $tasks) {
                if (-not $task.id) { $task.id = (Get-Date).ToString('yyyyMMddHHmmssfff') }
                $file = Join-Path $inbox ("task_{0}.jsonl" -f $task.id)
                [System.IO.File]::WriteAllText($file, ($task | ConvertTo-Json -Compress) + "`n", [System.Text.UTF8Encoding]::new($true))
            }
            $ctx.Response.StatusCode = 202
        }
        catch {
            $ctx.Response.StatusCode = 500
            $ctx.Response.StatusDescription = $_.Exception.Message
        }
        finally {
            $ctx.Response.Close()
        }
    }
}
finally {
    $listener.Stop()
}
