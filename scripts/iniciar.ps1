$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

try {
    if ([string]::IsNullOrWhiteSpace($env:API_KEY)) {
        $env:API_KEY = "tfu-demo-key"
    }

    & docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up fallo con codigo $LASTEXITCODE"
    }

    $headers = @{ "X-API-Key" = $env:API_KEY }
    $disponible = $false
    Write-Host -NoNewline "Esperando que la API quede disponible"

    for ($intento = 1; $intento -le 30; $intento++) {
        try {
            $respuesta = Invoke-WebRequest `
                -Uri "http://localhost:8080/salud" `
                -Headers $headers `
                -UseBasicParsing `
                -TimeoutSec 2
            if ($respuesta.StatusCode -eq 200) {
                $disponible = $true
                break
            }
        }
        catch {
            # Docker puede tardar unos segundos en iniciar los contenedores.
        }

        Write-Host -NoNewline "."
        Start-Sleep -Seconds 1
    }

    if (-not $disponible) {
        throw "La API no respondio a tiempo. Revise: docker compose logs"
    }

    Write-Host ""
    Write-Host "API lista en http://localhost:8080"
    Write-Host "Clave de demostracion: $env:API_KEY"
}
finally {
    Pop-Location
}
