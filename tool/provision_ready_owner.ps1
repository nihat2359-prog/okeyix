param(
  [Parameter(Mandatory=$true)][string]$SupabaseUrl,
  [string]$ExistingOwnerId
)
# MANUAL ADMIN SETUP ONLY. Never invoked by migration, Flutter or tests.
# No key/password is saved or printed. No auth.users SQL insert is performed.
$ErrorActionPreference = 'Stop'
$projectUri = [Uri]$SupabaseUrl
if ($projectUri.Scheme -ne 'https' -or $projectUri.UserInfo -or $projectUri.Query -or
    $projectUri.AbsolutePath -ne '/') { throw 'Use the HTTPS Supabase project root URL.' }
$rootUrl = $SupabaseUrl.TrimEnd('/')
$secureKey = Read-Host 'Supabase service_role key (hidden; never paste into chat)' -AsSecureString
$keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
$keyText = $null
$headers = $null
try {
  $keyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
  $headers = @{ apikey=$keyText; Authorization="Bearer $keyText" }
  if ($ExistingOwnerId) {
    $ownerId = [guid]::Parse($ExistingOwnerId).ToString()
    $account = Invoke-RestMethod -Method Get -Uri "$rootUrl/auth/v1/admin/users/$ownerId" -Headers $headers
  } else {
    $bytes = New-Object byte[] 48
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    $payload = @{
      email='ready-tables-owner@okeyix.invalid'
      password=[Convert]::ToBase64String($bytes)
      email_confirm=$true
      ban_duration='876000h'
      app_metadata=@{ okeyix_system='ready_tables_owner' }
      user_metadata=@{ name='Okeyix System Tables' }
    } | ConvertTo-Json -Depth 4
    $account = Invoke-RestMethod -Method Post -Uri "$rootUrl/auth/v1/admin/users" -Headers $headers -ContentType 'application/json' -Body $payload
    $payload = $null
    [Array]::Clear($bytes,0,$bytes.Length)
  }
  if ($account.app_metadata.okeyix_system -ne 'ready_tables_owner' -or
      !$account.banned_until -or [DateTimeOffset]::Parse($account.banned_until) -le [DateTimeOffset]::UtcNow -or
      $account.last_sign_in_at) { throw 'Dedicated banned, never-signed-in system identity required.' }
  $ownerId = [guid]::Parse($account.id).ToString()
  Write-Output 'System owner ready. Run this SQL in the SAME project after the migration:'
  Write-Output "UPDATE okeyix_ready_private.policy SET owner_id='$ownerId'::uuid, enabled=true WHERE singleton;"
} catch {
  # REST exception details can contain sensitive request data; do not echo them.
  throw 'System owner setup failed. Check the project/admin key and Auth logs. If the account already exists, rerun with -ExistingOwnerId from Authentication > Users. No existing account was changed.'
} finally {
  if ($headers) { $headers.Clear() }
  $keyText = $null
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
}
