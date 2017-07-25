<###### UCS Provisioning Configuration Utilities ######>

<#### PARAMETERS ####>
$Script:LocalStorageLocation = "$env:LOCALAPPDATA\UCS"
$Script:ConfigFileName = 'UcsProvConfig.xml'
$Script:DisabledSuffix = '-disabled'
$Script:ConfigPath = Join-Path $Script:LocalStorageLocation $Script:ConfigFileName
$Script:ImportedConfigInUse = $false

Function New-UcsProvConfigServer
{
  Param(
    [Parameter(Mandatory)][Alias('CN','ComputerName')][String][ValidatePattern('^[^\\/]+$')]$ProvServerAddress,
    [Parameter(Mandatory)][Alias('Type','Protocol')][String][ValidateSet('FTP','FileSystem')]$ProvServerType,
    [Parameter(Mandatory)][PsCredential]$Credential,
    [Int]$Priority = 100,
    [Parameter(Mandatory)][String]$DisplayName
  )

  $ThisNewServer = 1 | Select-Object -Property @{Name='DisplayName';Expression={$DisplayName}},@{Name='ProvServerAddress';Expression={$ProvServerAddress}},@{Name='ProvServerType';Expression={$ProvServerType}},@{Name='Credential';Expression={$Credential}},@{Name='Priority';Expression={$Priority}}
  
  Add-UcsProvConfigServer $ThisNewServer
}

Function Get-UcsProvConfig
{
  $ThisResult = $Script:ProvConfig | Sort-Object -Property Priority,Index
  
  Return $ThisResult
}

Function Add-UcsProvConfigServer
{
  #Internal use only.
  Param(
    [Parameter(Mandatory)]$UcsProvConfigServer
  )
  
  $ToAddObject = $UcsProvConfigServer
  $Index = [Int](Get-UcsProvConfig | Measure-Object -Property Index -Maximum).Maximum
  $Index++
  $ToAddObject = $ToAddObject | Select-Object *,@{Name='Index';Expression={$Index}}
  
  $null = $Script:ProvConfig.Add($ToAddObject)
  
  Update-UcsProvConfigStorage
}



<## Config storage ##>
Function Import-UcsProvConfigStorage
{
  Param (
    [String]$Path = $Script:ConfigPath
  )

  if((Test-Path $Path) -eq $false)
  {
    Write-Error "Could not find file at $Path." -ErrorAction Stop
  }

  Write-Debug "Importing $Path to UcsConfig."
  $Imported = Import-Clixml -Path $Path

  $Script:ProvConfig = $Imported
  $Script:ImportedConfigInUse = $true
}

Function Update-UcsProvConfigStorage
{
  Param (
    [String]$Path = $Script:ConfigPath
  )

  $Directory = Split-Path $Path

  if( (Test-Path $Directory) -eq $false)
  {
    Write-Debug "Path $Directory not found. Creating..."
    $null = New-Item -Path $Directory -ItemType Directory -Force
  }

  if($Script:ImportedConfigInUse)
  {
    Write-Debug "Writing XML file to $Path."
    $Script:ProvConfig | Export-Clixml -Path $Path -Depth 1
  }
  else
  {
    Write-Debug "Imported config not currently in use, not updating."
  }
}

Function Enable-UcsProvConfigStorage
{
   [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
   Param()

   if($Script:ImportedConfigInUse -eq $true)
   {
    Write-Error "Config storage already in use."
    Break
   }

   if($PSCmdlet.ShouldProcess($Script:ConfigPath))
   {
     $Script:ImportedConfigInUse = $true
     Update-UcsConfigStorage
   }
}

Function Disable-UcsProvConfigStorage
{
   [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
   Param()

   if($Script:ImportedConfigInUse -ne $true)
   {
    Write-Error "Config storage not in use."
    Break
   }

   if($PSCmdlet.ShouldProcess($Script:ConfigPath))
   {
     $Script:ImportedConfigInUse = $false
     $ThisItem = Get-Item -Path $Script:ConfigPath
     $NewName = ('{0}{1}{2}' -f $ThisItem.BaseName,$Script:DisabledSuffix,$ThisItem.Extension)
     $NewPath = Join-Path $ThisItem.Directory $NewName
     $null = Rename-Item -Path $Script:ConfigPath -NewName $NewPath -Force
   }
}

Function Get-UcsProvConfigStorageIsEnabled
{
  Return $Script:ImportedConfigInUse
}


<### INITIALIZATION ###>

$Script:ProvConfig = New-Object System.Collections.ArrayList

<#### Check for preferences ####>
if( Test-Path $Script:ConfigPath )
{
  Write-Debug "Found config file at $Script:ConfigPath."
  Import-UcsProvConfigStorage
}