<###### UCS Configuration Utilities ######>

# Storage initilization at end, after function definitions.

<#### Function definitions ####>

<## INTERNAL ##>
Function New-UcsConfig
{
  <#
  .NOTES
  For internal use only - used to create initial config objects.

  .PARAMETER Priority
  The item with the lowest numerical value priority goes first in order. In case of a tie, APIs are ranked alphabetically.
  #>
  Param (
    [Parameter(Mandatory)][ValidateSet('REST','SIP','Poll','Push','Web','FTP')][String]$API,
    [Nullable[Timespan]]$Timeout = (New-TimeSpan -Seconds 3),
    [Nullable[Int]][ValidateRange(1,100)]$Retries = 2,
    [Nullable[Int]][ValidateRange(0,65535)]$Port = 80,
    [Nullable[bool]]$EnableEncryption = $false,
    [Nullable[Int]]$Priority = 50,
    [Nullable[bool]]$Enabled = $true
  )

  if($Timeout.TotalSeconds -le 0)
  {
    Write-Error "Couldn't create options because timeout was set to 0 or less." -ErrorAction Stop -Category InvalidArgument
  }

  $OutputObject = $API | Select-Object @{Name='API';Expression={$API}},
    @{Name='Timeout';Expression={$Timeout}},
    @{Name='Retries';Expression={$Retries}},
    @{Name='Port';Expression={$Port}},
    @{Name='EnableEncryption';Expression={$EnableEncryption}},
    @{Name='Priority';Expression={$Priority}},
    @{Name='Enabled';Expression={$Enabled}}
  
  Return $OutputObject
}

Function Get-UcsConfig
{
  Param (
    [Parameter(Mandatory)][ValidateSet('REST','SIP','Poll','Push','Web','FTP')][String]$API
  )

  $RequestedConfig = $Script:MasterConfig | Where-Object -Property API -EQ -Value $API

  Return $RequestedConfig
}

Function Get-UcsConfigPriority
{
  $AllConfigs = $Script:MasterConfig
  $EnabledConfigs = $AllConfigs | Where-Object -Property Enabled -EQ -Value $true
  $SortedConfigs = $EnabledConfigs | Sort-Object -Property Priority,API
  $SortedConfigNames = $SortedConfigs | Select-Object -ExpandProperty API

  Return $SortedConfigNames
}

Function Set-UcsConfig
{
  Param (
    [Parameter(Mandatory)][ValidateSet('REST','SIP','Poll','Push','Web','FTP')][String]$API,
    [Nullable[Timespan]]$Timeout = $null,
    [Nullable[Int]][ValidateRange(1,100)]$Retries = $null,
    [Nullable[Int]][ValidateRange(0,65535)]$Port = $null,
    [Nullable[bool]]$EnableEncryption = $null,
    [Nullable[Int]]$Priority = $null,
    [Nullable[bool]]$Enabled = $null
  )

  $WorkingConfig = Get-UcsConfig -API $API

  if($Retries -ne $null)
  {
    $WorkingConfig.Retries = $Retries
  }

  if($Timeout -ne $null)
  {
    if($Timeout.TotalSeconds -lt 0)
    {
      Write-Error "Couldn't create options because timeout was set to less than 0." -ErrorAction Stop -Category InvalidArgument
    }
    else
    {
      $WorkingConfig.Timeout = $Timeout
    }
  }

  if($Port -ne $null)
  {
    $WorkingConfig.Port = $Port
  }

  if($EnableEncryption -ne $null)
  {
    $WorkingConfig.EnableEncryption = $EnableEncryption
  }

  if($Priority -ne $null)
  {
    $WorkingConfig.Priority = $Priority
  }

  if($Enabled -ne $null)
  {
    $WorkingConfig.Enabled = $Enabled
  }

  Foreach($Configuration in $Script:MasterConfig)
  {
    if($Configuration.API -eq $API)
    {
     $Configuration = $WorkingConfig
    }
  }
}

Function New-UcsConfigCredential
{
  Param (
    [Parameter(Mandatory)][ValidateSet('REST','SIP','Poll','Push','Web','FTP')][String]$API,
    [Parameter(Mandatory)][PSCredential]$Credential,
    [String]$DisplayName = '',
    [Int]$Priority = 50,
    [String]$Identity = '*',
    [Boolean]$Enabled = $true
  )

  $OutputObject = $API | Select-Object @{Name='API';Expression={$API}},
    @{Name='Identity';Expression={$Identity}},
    @{Name='DisplayName';Expression={$DisplayName}},
    @{Name='Credential';Expression={$Credential}},
    @{Name='Priority';Expression={$Priority}},
    @{Name='Enabled';Expression={$Enabled}}

  Return $OutputObject
}

Function New-UcsConfigCredentialPlaintext
{
  Param (
    [Parameter(Mandatory)][String]$Username,
    [Parameter(Mandatory)][String]$Password
  )

  $SecureStringPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
  $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($Username,$SecureStringPassword)

  Return $Credential
}

Function Get-UcsCredential
{
  Param (
    [Parameter(Mandatory)][ValidateSet('REST','SIP','Poll','Push','Web','FTP')][String]$API,
    [Switch]$IncludeDisabled,
    [Switch]$CredentialOnly
  )

  $AllCredentials = $Script:MasterCredentials
  
  if(!$IncludeDisabled)
  {
    $AllCredentials = $AllCredentials | Where-Object -Property Enabled -EQ -Value $true
  }

  $ThisAPICredentials = $AllCredentials | Where-Object -Property API -EQ -Value $API
  $SortedCredentials = $ThisAPICredentials | Sort-Object -Property Priority,API

  if($CredentialOnly)
  {
    Return $SortedCredentials.Credential
  }
  else
  {
    Return $SortedCredentials
  }
}

<#### Create Credentials ####>
$Script:MasterCredentials = (
  (New-UcsConfigCredential -API REST -Credential (New-UcsConfigCredentialPlaintext -Username 'Polycom' -Password '456') -DisplayName "Polycom default REST credential" -Priority 1000),
  (New-UcsConfigCredential -API Web -Credential (New-UcsConfigCredentialPlaintext -Username 'Polycom' -Password '456') -DisplayName "Polycom default Web credential" -Priority 1000),
  (New-UcsConfigCredential -API Poll -Credential (New-UcsConfigCredentialPlaintext -Username 'UCSToolkit' -Password 'UCSToolkit') -DisplayName "Script default Polling credential" -Priority 1000),
  (New-UcsConfigCredential -API Push -Credential (New-UcsConfigCredentialPlaintext -Username 'UCSToolkit' -Password 'UCSToolkit') -DisplayName "Script default Push credential" -Priority 1000),
  (New-UcsConfigCredential -API FTP -Credential (New-UcsConfigCredentialPlaintext -Username 'PlcmSpIp' -Password 'PlcmSpIp') -DisplayName "Polycom default provisioning credential" -Priority 1000)
)

<#### Define defaults for configs ####>
$Script:MasterConfig = (
  (New-UcsConfig -API REST -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $false -Priority 1 -Enabled $true),
  (New-UcsConfig -API SIP -Timeout (New-TimeSpan -Seconds 5) -Retries 2 -Port 5060 -EnableEncryption $false -Priority 90 -Enabled $true),
  (New-UcsConfig -API Poll -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $false -Priority 30 -Enabled $true),
  (New-UcsConfig -API Push -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $false -Priority 40 -Enabled $true),
  (New-UcsConfig -API Web -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $false -Priority 20 -Enabled $true),
  (New-UcsConfig -API FTP -Timeout (New-TimeSpan -Seconds 5) -Retries 2 -Port 21 -EnableEncryption $false -Priority 100 -Enabled $true)
)
