param(
    [int]$Requests = 60,
    [int]$Concurrency = 6
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
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(30)

function New-ApiRequest {
    param([string]$Uri)

    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Get,
        $Uri
    )
    [void]$request.Headers.TryAddWithoutValidation("X-API-Key", $apiKey)
    return $request
}

function Measure-Scenario {
    param(
        [string]$Name,
        [string]$Uri
    )

    Write-Host "Midiendo ${Name}: $Requests pedidos, concurrencia $Concurrency..."
    $pending = [System.Collections.ArrayList]::new()
    $latencies = [System.Collections.Generic.List[double]]::new()
    $launched = 0
    $completed = 0
    $correct = 0
    $frequency = [System.Diagnostics.Stopwatch]::Frequency
    $total = [System.Diagnostics.Stopwatch]::StartNew()

    while ($completed -lt $Requests) {
        while (($pending.Count -lt $Concurrency) -and ($launched -lt $Requests)) {
            $request = New-ApiRequest -Uri $Uri
            $start = [System.Diagnostics.Stopwatch]::GetTimestamp()
            $task = $client.SendAsync($request)
            [void]$pending.Add([PSCustomObject]@{
                Task = $task
                Request = $request
                Start = $start
            })
            $launched++
        }

        $foundCompleted = $false
        for ($index = $pending.Count - 1; $index -ge 0; $index--) {
            $item = $pending[$index]
            if (-not $item.Task.IsCompleted) {
                continue
            }

            $foundCompleted = $true
            $elapsed = (
                [System.Diagnostics.Stopwatch]::GetTimestamp() - $item.Start
            ) / $frequency
            $latencies.Add($elapsed * 1000)

            $response = $null
            try {
                $response = $item.Task.GetAwaiter().GetResult()
                $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $body = $text | ConvertFrom-Json
                if (([int]$response.StatusCode -eq 200) -and
                    ($body.PSObject.Properties.Name -contains "huella_computo")) {
                    $correct++
                }
            }
            finally {
                if ($null -ne $response) {
                    $response.Dispose()
                }
                $item.Request.Dispose()
                $pending.RemoveAt($index)
            }
            $completed++
        }

        if (-not $foundCompleted) {
            Start-Sleep -Milliseconds 1
        }
    }

    $total.Stop()
    $sorted = @($latencies | Sort-Object)
    if (($sorted.Count % 2) -eq 0) {
        $middle = $sorted.Count / 2
        $median = ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }
    else {
        $median = $sorted[[Math]::Floor($sorted.Count / 2)]
    }
    $p95Index = [Math]::Ceiling(0.95 * $sorted.Count) - 1

    return [PSCustomObject]@{
        Name = $Name
        Correct = $correct
        RequestsPerSecond = $Requests / $total.Elapsed.TotalSeconds
        MedianMs = $median
        P95Ms = $sorted[$p95Index]
    }
}

try {
    if (($Requests -lt 1) -or ($Concurrency -lt 1)) {
        throw "Requests y Concurrency deben ser mayores que cero"
    }

    Write-Host "DEMO - MANTENER MULTIPLES COPIAS DEL COMPUTO"
    Write-Host "================================================================"
    Write-Host "ETAPA 1: MOSTRAR EL REPARTO DE PEDIDOS"
    Write-Host ""
    Write-Host "Se enviaran 12 pedidos al unico punto de entrada:"
    Write-Host "curl -H 'X-API-Key: $apiKey' '$baseUrl/recetas?limite=1'"
    Write-Host ""

    $counts = @{}
    for ($index = 0; $index -lt 12; $index++) {
        $request = New-ApiRequest -Uri "$baseUrl/recetas?limite=1"
        $response = $null
        try {
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                throw "La API respondio HTTP $([int]$response.StatusCode): $text"
            }
            $instance = ($text | ConvertFrom-Json).atendido_por
            if (-not $counts.ContainsKey($instance)) {
                $counts[$instance] = 0
            }
            $counts[$instance]++
        }
        finally {
            if ($null -ne $response) {
                $response.Dispose()
            }
            $request.Dispose()
        }
    }

    $counts.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host ("{0,4} {1}" -f $_.Value, $_.Name)
    }

    Write-Host ""
    Write-Host "EVIDENCIA: nginx distribuyo los pedidos entre api1, api2 y api3."
    Write-Host ""
    Write-Host "================================================================"
    Write-Host "ETAPA 2: COMPARAR EL EFECTO SOBRE EL RENDIMIENTO"
    Write-Host ""
    Write-Host "A. Todos los pedidos dirigidos solamente a api1."
    Write-Host "B. Pedidos repartidos entre api1, api2 y api3."
    Write-Host ""

    $one = Measure-Scenario `
        -Name "1 copia" `
        -Uri "$baseUrl/demo/una-copia/recetas?limite=1"
    $three = Measure-Scenario `
        -Name "3 copias" `
        -Uri "$baseUrl/recetas?limite=1"

    Write-Host ""
    Write-Host "RESULTADOS - MISMA CARGA Y MISMO COMPUTO POR PEDIDO"
    Write-Host ("{0,-12} {1,10} {2,10} {3,12} {4,12}" -f `
        "Escenario", "Correctos", "req/s", "Mediana", "p95")
    Write-Host ("-" * 60)
    foreach ($result in @($one, $three)) {
        Write-Host ("{0,-12} {1,3}/{2,-6} {3,10:N2} {4,9:N0} ms {5,9:N0} ms" -f `
            $result.Name,
            $result.Correct,
            $Requests,
            $result.RequestsPerSecond,
            $result.MedianMs,
            $result.P95Ms)
    }

    if (($one.Correct -ne $Requests) -or ($three.Correct -ne $Requests)) {
        throw "Hubo pedidos fallidos; la comparacion no es valida"
    }

    $performanceImprovement = $three.RequestsPerSecond / $one.RequestsPerSecond
    $p95Reduction = $one.P95Ms / $three.P95Ms
    Write-Host ""
    Write-Host ("Con 3 copias, el rendimiento fue {0:N2} veces mayor." -f $performanceImprovement)
    Write-Host ("La latencia p95 fue {0:N2} veces menor." -f $p95Reduction)
    Write-Host "La mejora viene del procesamiento paralelo y la menor espera en cola."
}
finally {
    $client.Dispose()
    Pop-Location
}
