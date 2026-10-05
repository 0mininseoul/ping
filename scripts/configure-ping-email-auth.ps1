param([switch]$Apply, [switch]$AllowTeamOnlyEmail)

$ErrorActionPreference = 'Stop'
$pingProjectRef = 'qxjtprxvjmaxlbtljcjw'
$pingOrganizationId = 'nvyhcwxyemylsqjlbdpo'
$pingManagementToken = $env:PING_SUPABASE_MANAGEMENT_TOKEN
if ([string]::IsNullOrWhiteSpace($pingManagementToken)) {
    throw 'Set PING_SUPABASE_MANAGEMENT_TOKEN locally to a Supabase management access token. Do not put it in chat or Git.'
}
$pingHeaders = @{ Authorization = "Bearer $pingManagementToken" }

function Invoke-PingManagement([string]$Method, [string]$Path, $Body = $null) {
    $pingRequest = @{ Method = $Method; Uri = "https://api.supabase.com/v1/projects/$pingProjectRef$Path"; Headers = $pingHeaders }
    if ($null -ne $Body) {
        $pingRequest.ContentType = 'application/json; charset=utf-8'
        $pingRequest.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 8 -Compress))
    }
    try { Invoke-RestMethod @pingRequest }
    catch { throw 'Ping management request failed. Check project access and the local management token. No credentials or response body are printed.' }
}

$pingProject = Invoke-PingManagement GET ''
if ($pingProject.id -ne $pingProjectRef -or $pingProject.organization_id -ne $pingOrganizationId -or $pingProject.name -ne 'Ping') {
    throw 'Refusing to change an unexpected project. Expected pinned Ping project and organization.'
}
$pingAuth = Invoke-PingManagement GET '/config/auth'
$pingCodeTemplate = '<p>Ping 앱에 아래 인증번호를 입력해 주세요.</p><p style="font-size:24px;font-weight:bold;letter-spacing:4px">{{ .Token }}</p>'
function Add-PingCode([string]$Content) {
    if ($Content -match '\{\{\s*\.Token\s*\}\}') { return $Content }
    if ([string]::IsNullOrWhiteSpace($Content)) { return "<h2>Ping 이메일 인증</h2>$pingCodeTemplate" }
    return "$Content`n$pingCodeTemplate"
}
$pingPatch = @{
    external_email_enabled = $true
    security_manual_linking_enabled = $true
    mailer_autoconfirm = $false
    sessions_single_per_user = $false
    mailer_templates_email_change_content = (Add-PingCode $pingAuth.mailer_templates_email_change_content)
    mailer_templates_magic_link_content = (Add-PingCode $pingAuth.mailer_templates_magic_link_content)
}
$pingHasSmtp = -not [string]::IsNullOrWhiteSpace($pingAuth.smtp_host)
Write-Output "Pinned Ping project. Custom SMTP configured: $pingHasSmtp"
Write-Output ('Auth fields prepared: ' + (($pingPatch.Keys | Sort-Object) -join ', '))
if (-not $Apply) {
    Write-Output 'No changes applied. Use -Apply after configuring SMTP in the existing Ping Supabase project.'
    return
}
if (-not $pingHasSmtp -and -not $AllowTeamOnlyEmail) {
    throw 'Custom SMTP is missing. Configure it in Supabase first. -AllowTeamOnlyEmail explicitly limits delivery to project team addresses.'
}
$null = Invoke-PingManagement PATCH '/config/auth' $pingPatch
Write-Output 'Requested Auth fields applied. No test emails, login tests, SQL migrations, or post-change verification were run.'
