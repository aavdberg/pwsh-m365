#Requires -Version 3.0
# Make sure to fill in all the required variables before running the script
# Also make sure the AppID used corresponds to an app with sufficient permissions, as follows:
#    Group.Read.All or Directory.Read.All to read all Groups
#    Group.Read.All to read Channel info

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "'tenant.onmicrosoft.com' your tenantID or tenant root domain")]
    [string]$tenantID,
    [Parameter(Mandatory = $true, HelpMessage = "'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' the GUID of your app.")]
    [string]$appID,
    [Parameter(Mandatory = $true, HelpMessage = "'verylongsecurestring' client secret for the app")]
    [string]$client_secret,
    [Parameter(Mandatory = $false, HelpMessage = "Do you want a output file")]
    [switch]$csv,
    [Parameter(Mandatory = $false, HelpMessage = "Do you want interactive mode")]
    [switch]$interactive
)

#==========================================================================
#Main script starts here
#==========================================================================

#Obtain access token
$url = 'https://login.microsoftonline.com/' + $tenantId + '/oauth2/v2.0/token'

$Scopes = New-Object System.Collections.Generic.List[string]
$Scope = "https://graph.microsoft.com/.default"
$Scopes.Add($Scope)

$body = @{
    grant_type    = "client_credentials"
    client_id     = $appID
    client_secret = $client_secret
    scope         = $Scopes
}

try { 
    Set-Variable -Name authenticationResult -Scope Global -Value (Invoke-WebRequest -Method Post -Uri $url -Debug -Verbose -Body $body)
    $token = ($authenticationResult.Content | ConvertFrom-Json).access_token
}
catch { $_; return }

if (!$token) {
    Write-Host "Failed to aquire token!"; return
}
else {
    Write-Verbose "Successfully acquired Access Token"
        
    #Use the access token to set the authentication header
    Set-Variable -Name authHeader -Scope Global -Value @{'Authorization' = "Bearer $token"; 'Content-Type' = 'application\json' }
}

#Use the /beta endpoint to fetch a list of all Teams
#Do not switch to https://graph.microsoft.com/beta/teams as we need the Group proxy address details
$uri = "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq `'Team`')&`$select=id,displayName,mail,proxyAddresses,resourceBehaviorOptions,resourceProvisioningOptions,visibility"
$result = Invoke-WebRequest -Headers $AuthHeader -Uri $uri -Verbose:$VerbosePreference
$teams = ($result.Content | ConvertFrom-Json).Value

#iterate over each Team and gather channel information
$output = @()
foreach ($team in $teams) {
    $uri = "https://graph.microsoft.com/v1.0/teams/$($team.id)/channels"
    $result = Invoke-WebRequest -Headers $AuthHeader -Uri $uri -Verbose:$VerbosePreference
    $channels = ($result.Content | ConvertFrom-Json).Value

    #$channels | select displayName,email,id,webUrl
    foreach ($channel in $channels) {
        $chaninfo = New-Object psobject
        $chaninfo | Add-Member -MemberType NoteProperty -Name "Id" -Value $channel.id
        $chaninfo | Add-Member -MemberType NoteProperty -Name "Team" -Value $team.displayName
        $chaninfo | Add-Member -MemberType NoteProperty -Name "TeamId" -Value $team.id
        $chaninfo | Add-Member -MemberType NoteProperty -Name "TeamEmailAddresses" -Value $($team.proxyAddresses -join ",")
        $chaninfo | Add-Member -MemberType NoteProperty -Name "Visibility" -Value $team.visibility
        $chaninfo | Add-Member -MemberType NoteProperty -Name "Channel" -Value $channel.displayName
        $chaninfo | Add-Member -MemberType NoteProperty -Name "ChannelEmail" -Value (& { If ($channel.email) { $channel.email } Else { "N/A" } })
        $output += $chaninfo
    }

}

#return the output
$global:varTeamChannels = $output | Select-Object Team, Visibility, Channel, ChannelEmail, TeamEmailAddresses, TeamId

if ($csv) {
    $output | Select-Object * | Export-Csv -Path "$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss'))_TeamsChannels.csv" -NoTypeInformation -Encoding UTF8 -UseCulture
}

if ($interactive) {
return $global:varTeamChannels | Where-Object {$_.ChannelEmail -ne $Null} | Out-GridView -OutputMode Single -Title 'Find the e-mail address of a teams channel'
}
