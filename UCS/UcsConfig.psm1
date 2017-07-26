<###### UCS Configuration Utilities ######>

<#### PARAMETERS ####>
$Script:LocalStorageLocation = "$env:LOCALAPPDATA\UCS"
$Script:CredentialFileName = 'UcsCredential.xml'
$Script:ConfigFileName = 'UcsConfig.xml'
$Script:DisabledSuffix = '-disabled'
$Script:ConfigPath = Join-Path $Script:LocalStorageLocation $Script:ConfigFileName
$Script:CredentialPath = Join-Path $Script:LocalStorageLocation $Script:CredentialFileName
$Script:ImportedConfigInUse = $false
$Script:ImportedCredentialInUse = $false

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
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidateSet('REST','SIP','Poll','Push','Web','Provisioning')][String]$API,
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
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidateSet('REST','SIP','Poll','Push','Web','Provisioning')][String]$API
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
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidateSet('REST','SIP','Poll','Push','Web','Provisioning')][String]$API,
    [Nullable[Timespan]]$Timeout = $null,
    [Nullable[Int]][ValidateRange(1,100)]$Retries = $null,
    [Nullable[Int]][ValidateRange(0,65535)]$Port = $null,
    [Nullable[bool]]$EnableEncryption = $null,
    [Nullable[Int]]$Priority = $null,
    [Nullable[bool]]$Enabled = $null
  )

  Process
  {
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
        if($WorkingConfig.EnableEncryption -eq $null)
        {
          Write-Error ('Encryption is not supported by the {0} API.' -f $API)
        }
        else
        {
          $WorkingConfig.EnableEncryption = $EnableEncryption
        }
      }

      if($Priority -ne $null)
      {
        $MatchingPriority = $Script:MasterConfig | Where-Object -Property Priority -eq $Priority | Measure-Object
        if($MatchingPriority.Count -gt 0)
        {
          Write-Warning ('Cannot set priority of {0} to {1} because that priority level is in use on one or more other APIs.' -f $WorkingConfig.API,$Priority)
        }
        else
        {
          $WorkingConfig.Priority = $Priority
        }
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
  End
  {
     Update-UcsConfigStorage
  }
}

Function New-UcsConfigCredential
{
  Param (
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidateSet('REST','Poll','Push','Web')][String]$API,
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


  Add-UcsConfigCredential $OutputObject
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

Function Get-UcsConfigCredential
{
  Param (
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidateSet('REST','Poll','Push','Web')][String]$API,
    [Switch]$IncludeDisabled,
    [Switch]$CredentialOnly
  )

  $AllCredentials = $Script:MasterCredentials
  
  if(!$IncludeDisabled)
  {
    $AllCredentials = $AllCredentials | Where-Object -Property Enabled -EQ -Value $true
  }

  $ThisAPICredentials = $AllCredentials | Where-Object -Property API -EQ -Value $API
  $SortedCredentials = $ThisAPICredentials | Sort-Object -Property Priority,API,Index

  if($CredentialOnly)
  {
    Return $SortedCredentials.Credential
  }
  else
  {
    Return $SortedCredentials
  }
}

Function Add-UcsConfigCredential
{
  Param (
    [Parameter(Mandatory)][Object]$UcsConfigCredential
  )
  Process
  {
      if($UcsConfigCredential.Credential.GetType().Name -ne 'PSCredential' -or $UcsConfigCredential.Priority -eq $null)
      {
        Write-Error "Invalid UcsConfigCredential supplied."
      }

      $HighestIndex = $Script:MasterCredentials | Sort-Object -Property Index -Descending | Select -First 1 | Select -ExpandProperty Index
      $ThisIndex = $HighestIndex + 1

      $IndexRemoved = $UcsConfigCredential | Select-Object -Property * -ExcludeProperty Index
      $CredentialToSave = $IndexRemoved | Select-Object -Property *,@{Name='Index';Expression={$ThisIndex}}

      $null = $Script:MasterCredentials.Add($CredentialToSave)
  }
  End
  {
    Update-UcsConfigCredentialStorage
  }
}

Function Remove-UcsConfigCredential
{
  Param (
    [Parameter(Mandatory,ValueFromPipelineByPropertyName)][Int[]]$Index   
  )

  Process
  {
    Foreach($ThisIndex in $Index)
    {
      #We must rebuild the arraylist because doing a simple filter on the arraylist turns it into a collection of fixed size.
      $NewMasterCredentials = New-Object Collections.ArrayList
      Foreach($Credential in $Script:MasterCredentials)
      {
        if($Credential.Index -ne $ThisIndex)
        {
          $null = $NewMasterCredentials.Add($Credential)
        }
      }
    }
  }
  End
  {
    $Script:MasterCredentials = $NewMasterCredentials
    Update-UcsConfigCredentialStorage
  }
}

Function Set-UcsConfigCredential
{
   Param (
    [Parameter(Mandatory,ValueFromPipelineByPropertyName)][Int[]]$Index,
    [AllowEmptyString()][ValidateSet('REST','Poll','Push','Web')][String]$API = '',
    $Credential = $null,
    [String]$DisplayName = '',
    [Nullable[Int]]$Priority = $null,
    [String]$Identity = '',
    [Nullable[Boolean]]$Enabled = $null
  )

  Process
  {
    Foreach($ThisIndex in $Index)
    {
      $WorkingCredential = $Script:MasterCredentials | Where-Object -Property Index -EQ -Value $ThisIndex

      if($WorkingCredential -eq $null)
      {
        Write-Error "Invalid index $ThisIndex."
        Continue
      }

      if($API.Length -gt 0)
      {
        $WorkingCredential.API = $API
      }

      if($Credential -ne $null)
      {
        if($Credential.GetType().Name -eq 'PSCredential')
        {
          $WorkingCredential.Credential = $Credential
        }
      }

      if($DisplayName.Length -gt 0)
      {
        $WorkingCredential.DisplayName = $DisplayName
      }

      if($Priority -ne $null)
      {
        $WorkingCredential.Priority = $Priority
      }

      if($Identity.Length -gt 0)
      {
        $WorkingCredential.Identity = $Identity
      }

      if($Enabled -ne $null)
      {
        $WorkingCredential.Enabled = $Enabled
      }

      Foreach($Credential in $Script:MasterCredentials)
      {
        if($Credential.Index -eq $ThisIndex)
        {
          $Credential = $WorkingCredential
          Break
        }
      }
    }
  }
  End
  {
    Update-UcsConfigCredentialStorage
  }
}


<## Config storage ##>
Function Import-UcsConfigStorage
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

  $Script:MasterConfig = $Imported
  $Script:ImportedConfigInUse = $true
}

Function Update-UcsConfigStorage
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
    $Script:MasterConfig | Export-Clixml -Path $Path -Depth 1
  }
  else
  {
    Write-Debug "Imported config not currently in use, not updating."
  }
}

Function Enable-UcsConfigStorage
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

Function Disable-UcsConfigStorage
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

Function Get-UcsConfigStorageIsEnabled
{
  Return $Script:ImportedConfigInUse
}

<## Credential storage ##>
Function Import-UcsConfigCredentialStorage
{
  Param (
    [String]$Path = $Script:CredentialPath
  )

  if((Test-Path $Path) -eq $false)
  {
    Write-Error "Could not find file at $Path." -ErrorAction Stop
  }

  Write-Debug "Importing $Path to UcsConfig."
  $Imported = Import-Clixml -Path $Path

  $Script:MasterCredentials = New-Object Collections.ArrayList
  Foreach($Cred in $Imported)
  {
    $null = $Script:MasterCredentials.Add($Cred)
  }

  $Script:ImportedCredentialInUse = $true
}

Function Update-UcsConfigCredentialStorage
{
  Param (
    [String]$Path = $Script:CredentialPath
  )

  $Directory = Split-Path $Path

  if( (Test-Path $Directory) -eq $false)
  {
    Write-Debug "Path $Directory not found. Creating..."
    $null = New-Item -Path $Directory -ItemType Directory -Force
  }

  if($Script:ImportedCredentialInUse)
  {
    Write-Debug "Writing XML file to $Path."
    $Script:MasterCredentials | Export-Clixml -Path $Path -Depth 1
  }
  else
  {
    Write-Debug "Imported credentials not currently in use, not updating."
  }
}

Function Enable-UcsConfigCredentialStorage
{
   [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
   Param()

   if($Script:ImportedCredentialInUse -eq $true)
   {
    Write-Error "Credential storage already in use."
    Break
   }

   if($PSCmdlet.ShouldProcess($Script:CredentialPath))
   {
     $Script:ImportedCredentialInUse = $true
     Update-UcsConfigCredentialStorage
   }
}

Function Disable-UcsConfigCredentialStorage
{
   [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
   Param()

   if($Script:ImportedCredentialInUse -ne $true)
   {
    Write-Error "Credential storage not in use."
    Break
   }

   if($PSCmdlet.ShouldProcess($Script:CredentialPath))
   {
     $Script:ImportedCredentialInUse = $false
     $ThisItem = Get-Item -Path $Script:CredentialPath
     $NewName = ('{0}{1}{2}' -f $ThisItem.BaseName,$Script:DisabledSuffix,$ThisItem.Extension)
     $NewPath = Join-Path $ThisItem.Directory $NewName
     $null = Rename-Item -Path $Script:CredentialPath -NewName $NewPath -Force
   }
}
Function Get-UcsConfigCredentialStorageIsEnabled
{
  Return $Script:ImportedCredentialInUse
}

<#### Create Credential Storage ####>
$Script:MasterCredentials = New-Object Collections.ArrayList

<#### Initialize default credentials ####>
New-UcsConfigCredential -API REST -Credential (New-UcsConfigCredentialPlaintext -Username 'Polycom' -Password '456') -DisplayName "Polycom default REST credential" -Priority 1000
New-UcsConfigCredential -API Web -Credential (New-UcsConfigCredentialPlaintext -Username 'Polycom' -Password '456') -DisplayName "Polycom default Web credential" -Priority 1000
New-UcsConfigCredential -API Poll -Credential (New-UcsConfigCredentialPlaintext -Username 'UCSToolkit' -Password 'UCSToolkit') -DisplayName "Script default Polling credential" -Priority 1000
New-UcsConfigCredential -API Push -Credential (New-UcsConfigCredentialPlaintext -Username 'UCSToolkit' -Password 'UCSToolkit') -DisplayName "Script default Push credential" -Priority 1000

<#### Define defaults for configs ####>
$Script:MasterConfig = (
  (New-UcsConfig -API REST -Timeout (New-TimeSpan -Seconds 2) -Retries 1 -Port 80 -EnableEncryption $false -Priority 1 -Enabled $true),
  (New-UcsConfig -API SIP -Timeout (New-TimeSpan -Seconds 5) -Retries 2 -Port 5060 -EnableEncryption $null -Priority 90 -Enabled $true),
  (New-UcsConfig -API Poll -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $null -Priority 30 -Enabled $true),
  (New-UcsConfig -API Push -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $false -Priority 40 -Enabled $true),
  (New-UcsConfig -API Web -Timeout (New-TimeSpan -Seconds 2) -Retries 2 -Port 80 -EnableEncryption $null -Priority 20 -Enabled $true),
  (New-UcsConfig -API Provisioning -Timeout (New-TimeSpan -Seconds 5) -Retries 1 -Port 0 -EnableEncryption $null -Priority 100 -Enabled $true)
)

<#### Check for preferences ####>
if( Test-Path $Script:ConfigPath )
{
  Write-Debug "Found config file at $Script:ConfigPath."
  Import-UcsConfigStorage
}

if( Test-Path $Script:CredentialPath )
{
  Write-Debug "Found credential file at $Script:CredentialPath."
  Import-UcsConfigCredentialStorage
}