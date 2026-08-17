$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8765
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
$listener.Start()
Start-Process "http://127.0.0.1:$port/"
Write-Host "ROOT local server: http://127.0.0.1:$port/"
Write-Host "Laisse cette fenetre ouverte pendant la partie. Ctrl+C pour arreter."

$mimes = @{
  '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'; '.js'='application/javascript; charset=utf-8';
  '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.webp'='image/webp'; '.ico'='image/x-icon';
  '.mp3'='audio/mpeg'; '.wav'='audio/wav'; '.ttf'='font/ttf'; '.otf'='font/otf'; '.json'='application/json; charset=utf-8'
}

function Send-Response($stream, [int]$status, [string]$statusText, [byte[]]$body, [string]$contentType) {
  $header = "HTTP/1.1 $status $statusText`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`n`r`n"
  $hb = [Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($hb,0,$hb.Length)
  if($body.Length -gt 0){ $stream.Write($body,0,$body.Length) }
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 4096, $true)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }
      while (($line = $reader.ReadLine()) -ne '') { if ($null -eq $line) { break } }
      $parts = $requestLine.Split(' ')
      $method = $parts[0]
      $rawPath = if($parts.Length -gt 1){$parts[1]}else{'/'}
      $pathPart = $rawPath.Split('?')[0]
      $decoded = [Uri]::UnescapeDataString($pathPart)
      if ($decoded -eq '/') { $decoded = '/index.html' }
      $relative = $decoded.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
      $candidate = [IO.Path]::GetFullPath((Join-Path $root $relative))
      $rootFull = [IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar
      if (-not $candidate.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $body = [Text.Encoding]::UTF8.GetBytes('404')
        Send-Response $stream 404 'Not Found' $body 'text/plain; charset=utf-8'
      } else {
        $bytes = [IO.File]::ReadAllBytes($candidate)
        $ext = [IO.Path]::GetExtension($candidate).ToLowerInvariant()
        $mime = if($mimes.ContainsKey($ext)){$mimes[$ext]}else{'application/octet-stream'}
        if($method -eq 'HEAD'){ $bytes = [byte[]]@() }
        Send-Response $stream 200 'OK' $bytes $mime
      }
    } catch {
      try {
        $body = [Text.Encoding]::UTF8.GetBytes('500')
        Send-Response $stream 500 'Internal Server Error' $body 'text/plain; charset=utf-8'
      } catch {}
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
