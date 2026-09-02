param(
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

$apiKey = if ([string]::IsNullOrWhiteSpace($env:API_KEY)) {
    "tfu-demo-key"
}
else {
    $env:API_KEY
}
$baseUrl = if ([string]::IsNullOrWhiteSpace($env:URL)) {
    "http://localhost:8080"
}
else {
    $env:URL.TrimEnd("/")
}
$qLarga = "a" * 101
$client = [System.Net.Http.HttpClient]::new()

function Write-Separator {
    Write-Host ""
    Write-Host "================================================================"
}

function Wait-Demo {
    if (-not $NoPause) {
        [void](Read-Host "`nPresione Enter para continuar")
    }
}

function Invoke-DemoCase {
    param(
        [string]$Title,
        [string]$VisibleRequest,
        [string]$Expected,
        [string]$Uri,
        [AllowNull()][string]$HeaderValue
    )

    Write-Separator
    Write-Host $Title
    Write-Host ""
    Write-Host "PETICION ENVIADA"
    Write-Host $VisibleRequest
    Write-Host ""
    Write-Host "CONTROL ESPERADO"
    Write-Host $Expected

    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Get,
        $Uri
    )
    if ($null -ne $HeaderValue) {
        [void]$request.Headers.TryAddWithoutValidation("X-API-Key", $HeaderValue)
    }

    $response = $null
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $body = $text | ConvertFrom-Json

        if ($body.PSObject.Properties.Name -contains "recetas") {
            $body.recetas = @($body.recetas | ForEach-Object { $_.nombre })
        }

        Write-Host ""
        Write-Host "RESPUESTA"
        Write-Host "HTTP $([int]$response.StatusCode)"
        Write-Host ($body | ConvertTo-Json -Depth 6)
        Write-Host ""

        if ($body.PSObject.Properties.Name -contains "huella_computo") {
            Write-Host "EVIDENCIA: hay huella_computo -> el computo protegido SI se ejecuto."
        }
        else {
            Write-Host "EVIDENCIA: no hay huella_computo -> el computo protegido NO se ejecuto."
        }
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
        $request.Dispose()
    }

    Wait-Demo
}

try {
    Write-Host "DEMO DE TACTICAS DE SEGURIDAD"
    Write-Host "Recurso protegido: GET /recetas"
    Write-Host "La huella_computo solamente existe si el pedido supera los controles."

    Write-Separator
    Write-Host "TACTICA 1 - LIMITAR EL ACCESO"
    Write-Host "Se mantiene igual el recurso solicitado y se cambia la credencial."

    Invoke-DemoCase `
        -Title "Caso 1.1 - Sin credencial" `
        -VisibleRequest "curl '$baseUrl/recetas?limite=1'" `
        -Expected "La API debe impedir el acceso con HTTP 401." `
        -Uri "$baseUrl/recetas?limite=1" `
        -HeaderValue $null

    Invoke-DemoCase `
        -Title "Caso 1.2 - Credencial incorrecta" `
        -VisibleRequest "curl -H 'X-API-Key: incorrecta' '$baseUrl/recetas?limite=1'" `
        -Expected "La API debe impedir el acceso con HTTP 401." `
        -Uri "$baseUrl/recetas?limite=1" `
        -HeaderValue "incorrecta"

    Invoke-DemoCase `
        -Title "Caso 1.3 - Credencial valida" `
        -VisibleRequest "curl -H 'X-API-Key: $apiKey' '$baseUrl/recetas?limite=1'" `
        -Expected "La API debe permitir el acceso y ejecutar el computo." `
        -Uri "$baseUrl/recetas?limite=1" `
        -HeaderValue $apiKey

    Write-Separator
    Write-Host "TACTICA 2 - VALIDAR LA ENTRADA"
    Write-Host "Todos los pedidos tienen una credencial valida; ahora cambia la entrada."

    Invoke-DemoCase `
        -Title "Caso 2.1 - Entrada de 101 caracteres" `
        -VisibleRequest "curl -H 'X-API-Key: $apiKey' '$baseUrl/recetas?q=$qLarga'" `
        -Expected "q admite hasta 100 caracteres: debe responder HTTP 400." `
        -Uri "$baseUrl/recetas?q=$qLarga" `
        -HeaderValue $apiKey

    Invoke-DemoCase `
        -Title "Caso 2.2 - Numero fuera del rango permitido" `
        -VisibleRequest "curl -H 'X-API-Key: $apiKey' '$baseUrl/recetas?limite=999'" `
        -Expected "limite admite solamente enteros entre 1 y 20: debe responder HTTP 400." `
        -Uri "$baseUrl/recetas?limite=999" `
        -HeaderValue $apiKey

    Invoke-DemoCase `
        -Title "Caso 2.3 - Parametro que no pertenece al contrato" `
        -VisibleRequest "curl -H 'X-API-Key: $apiKey' '$baseUrl/recetas?admin=true'" `
        -Expected "admin no esta permitido: debe responder HTTP 400." `
        -Uri "$baseUrl/recetas?admin=true" `
        -HeaderValue $apiKey

    Invoke-DemoCase `
        -Title "Caso 2.4 - Entrada valida" `
        -VisibleRequest "curl -H 'X-API-Key: $apiKey' '$baseUrl/recetas?q=vegetariano&limite=2'" `
        -Expected "q y limite cumplen el contrato: debe responder HTTP 200." `
        -Uri "$baseUrl/recetas?q=vegetariano&limite=2" `
        -HeaderValue $apiKey

    Write-Separator
    Write-Host "CONCLUSION"
    Write-Host "- Limitar acceso detuvo los pedidos sin una credencial valida."
    Write-Host "- Validar entrada detuvo valores y parametros fuera del contrato."
    Write-Host "- Solo los pedidos autorizados y validos generaron huella_computo."
}
finally {
    $client.Dispose()
    Pop-Location
}
