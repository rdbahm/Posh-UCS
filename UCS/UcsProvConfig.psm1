<###### UCS Provisioning Configuration Utilities ######>

<#### PARAMETERS ####>
$Script:LocalStorageLocation = "$env:LOCALAPPDATA\UCS"
$Script:ProvConfigFileName = 'UcsProvConfig.xml'
$Script:DisabledSuffix = '-disabled'
$Script:ProvConfigPath = Join-Path -Path $Script:LocalStorageLocation -ChildPath $Script:ProvConfigFileName
$Script:ImportedProvConfigInUse = $false

Function New-UcsProvConfigServer
{
  Param(
    [Parameter(Mandatory)][Alias('CN','ComputerName')][String]$ProvServerAddress,
    [Parameter(Mandatory)][Alias('Type','Protocol')][String][ValidateSet('FTP','FileSystem')]$ProvServerType,
    [PsCredential]$Credential = $null,
    [Int]$Priority = 100,
    [Parameter(Mandatory)][String]$DisplayName
  )

  $ThisNewServer = 1 | Select-Object -Property @{
    Name       = 'DisplayName'
    Expression = {
      $DisplayName
    }
  }, @{
    Name       = 'ProvServerAddress'
    Expression = {
      $ProvServerAddress
    }
  }, @{
    Name       = 'ProvServerType'
    Expression = {
      $ProvServerType
    }
  }, @{
    Name       = 'Credential'
    Expression = {
      $Credential
    }
  }, @{
    Name       = 'Priority'
    Expression = {
      $Priority
    }
  }
  
  Add-UcsProvConfigServer -UcsProvConfigServer $ThisNewServer
}

Function Get-UcsProvConfig
{
  $ThisResult = $Script:ProvConfig | Sort-Object -Property Priority, Index
  
  Return $ThisResult
}

Function Add-UcsProvConfigServer
{
  #Internal use only.
  Param(
    [Parameter(Mandatory)]$UcsProvConfigServer
  )
  
  $ToAddObject = $UcsProvConfigServer
  $Index = [Int](Get-UcsProvConfig | Measure-Object -Property ProvServerIndex -Maximum).Maximum
  $Index++
  $ToAddObject = $ToAddObject | Select-Object -Property *, @{
    Name       = 'ProvServerIndex'
    Expression = {
      $Index
    }
  }
  
  $null = $Script:ProvConfig.Add($ToAddObject)
  
  Update-UcsProvConfigStorage
}

Function Set-UcsProvConfigServer
{
  Param(
    [Parameter(Mandatory,ValueFromPipelineByPropertyName)][Int]$ProvServerIndex,
    [Alias('CN','ComputerName')][String]$ProvServerAddress = '',
    [Alias('Type','Protocol')][String][ValidateSet('FTP','FileSystem')]$ProvServerType = '',
    [PsCredential]$Credential = $null,
    [Nullable[Int]]$Priority = $null,
    [String]$DisplayName = ''
  )
  
  $WorkingConfig = Get-UcsProvConfig | Where-Object -Property Index -EQ -Value $ProvServerIndex
  
  if($ProvServerAddress.Length -gt 0)
  {
    $WorkingConfig.ProvServerAddress = $ProvServerAddress
  }
  
  if($ProvServerType.length -gt 0)
  {
    $WorkingConfig.ProvServerType = $ProvServerType
  }
  
  if($Credential -ne $null)
  {
    $WorkingConfig.Credential = $Credential
  }
  
  if($Priority -ne $null)
  {
    $WorkingConfig.Priority = $Priority
  }
  
  if($DisplayName.Length -gt 0)
  {
    $WorkingConfig.DisplayName = $DisplayName
  }
  
  Foreach($ThisConfig in $Script:ProvConfig)
  {
    if($ThisConfig.Index -eq $ProvServerIndex)
    {
      $ThisConfig = $WorkingConfig
      Break
    }
  }
  
  Update-UcsProvConfigStorage
}

Function Remove-UcsProvConfigServer
{
  Param(
    [Parameter(Mandatory,ValueFromPipelineByPropertyName)][Int[]]$ProvServerIndex
  )
  
  Process
  {
    Foreach($ThisIndex in $ProvServerIndex)
    {
      $NewConfig = New-Object System.Collections.ArrayList
      
      Foreach($ThisConfig in $Script:ProvConfig)
      {
        if($ThisConfig.ProvServerIndex -ne $ThisIndex)
        {
          $null = $NewConfig.Add($ThisConfig)
        }
      }
      
      $Script:ProvConfig = $NewConfig
    }
  }
  
  End
  {
    Update-UcsProvConfigStorage
  }
}


<## Config storage ##>
Function Import-UcsProvConfigStorage
{
  Param (
    [String]$Path = $Script:ProvConfigPath
  )

  if((Test-Path $Path) -eq $false)
  {
    Write-Error -Message "Could not find file at $Path." -ErrorAction Stop
  }

  Write-Debug -Message "Importing $Path to UcsConfig."
  $Imported = Import-Clixml -Path $Path

  $Script:ProvConfig = New-Object Collections.ArrayList
  Foreach($ThisConfig in $Imported)
  {
    $null = $Script:ProvConfig.Add($ThisConfig)
  }
  
  $Script:ImportedProvConfigInUse = $true
}

Function Update-UcsProvConfigStorage
{
  Param (
    [String]$Path = $Script:ProvConfigPath
  )

  $Directory = Split-Path $Path

  if( (Test-Path $Directory) -eq $false)
  {
    Write-Debug -Message "Path $Directory not found. Creating..."
    $null = New-Item -Path $Directory -ItemType Directory -Force
  }

  if($Script:ImportedProvConfigInUse)
  {
    Write-Debug -Message "Writing XML file to $Path."
    $Script:ProvConfig | Export-Clixml -Path $Path -Depth 1
  }
  else
  {
    Write-Debug -Message 'Imported config not currently in use, not updating.'
  }
}

Function Enable-UcsProvConfigStorage
{
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param()

  if($Script:ImportedProvConfigInUse -eq $true)
  {
    Write-Error -Message 'Config storage already in use.'
    Break
  }

  if($PSCmdlet.ShouldProcess($Script:ProvConfigPath))
  {
    $Script:ImportedProvConfigInUse = $true
    Update-UcsConfigStorage
  }
}

Function Disable-UcsProvConfigStorage
{
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param()

  if($Script:ImportedProvConfigInUse -ne $true)
  {
    Write-Error -Message 'Config storage not in use.'
    Break
  }

  if($PSCmdlet.ShouldProcess($Script:ProvConfigPath))
  {
    $Script:ImportedProvConfigInUse = $false
    $ThisItem = Get-Item -Path $Script:ProvConfigPath
    $NewName = ('{0}{1}{2}' -f $ThisItem.BaseName, $Script:DisabledSuffix, $ThisItem.Extension)
    $NewPath = Join-Path -Path $ThisItem.Directory -ChildPath $NewName
    $null = Rename-Item -Path $Script:ProvConfigPath -NewName $NewPath -Force
  }
}

Function Get-UcsProvConfigStorageIsEnabled
{
  Return $Script:ImportedProvConfigInUse
}


<### INITIALIZATION ###>

$Script:ProvConfig = New-Object -TypeName System.Collections.ArrayList

<#### Check for preferences ####>
if( Test-Path $Script:ProvConfigPath )
{
  Write-Debug -Message "Found config file at $Script:ProvConfigPath."
  Import-UcsProvConfigStorage
}
